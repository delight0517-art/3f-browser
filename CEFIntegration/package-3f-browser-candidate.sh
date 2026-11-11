#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefclient/Release/cefclient.app"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
candidate_root="${1:-$repo_root/.build/3f-cef-full-browser-candidate}"
candidate_root="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$candidate_root")"
candidate="$candidate_root/cefclient.app"
mode_file="$source_app/Contents/Resources/3f-navigation-mode"

if [[ ! -d "$source_app" ]]; then
  echo "Build the CEF full-browser candidate first: $source_app" >&2
  exit 2
fi
if [[ ! -f "$mode_file" ]]; then
  echo "CEF build is missing its navigation-mode marker; rebuild with build-cefclient-probe.sh." >&2
  exit 4
fi
navigation_mode="$(<"$mode_file")"
case "$navigation_mode" in
  restricted-auth)
    if [[ ! -f "$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h" ]] || \
       ! grep -q 'IsAuthOnlyMode' \
         "$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h" || \
       ! grep -Fq 'return scheme == "https";' \
         "$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h" || \
       ! grep -q 'threef_auth::IsAllowedNavigation' \
         "$cef_root/tests/cefclient/browser/base_client_handler.cc" || \
       ! grep -q 'threef_auth::IsAllowedNavigation' \
         "$cef_root/tests/cefclient/browser/client_handler.cc" || \
       ! grep -q 'threef_auth::IsAllowedResource' \
         "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
      echo "Restricted-auth build is missing a required navigation-policy hook." >&2
      exit 4
    fi
    display_name="3F Auth Browser Preview"
    ;;
  full-browser)
    if grep -q 'threef_auth_browser_policy.h' \
       "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
      echo "Full-browser mode still contains auth-only navigation hooks." >&2
      exit 4
    fi
    display_name="3F Browser Preview"
    ;;
  *)
    echo "Unsupported CEF navigation mode: $navigation_mode" >&2
    exit 4
    ;;
esac
if [[ -e "$candidate" ]]; then
  echo "Refusing to replace an existing candidate: $candidate" >&2
  exit 3
fi

mkdir -p "$candidate_root"
stage="$(mktemp -d "$candidate_root/.package-XXXXXX")"
trap 'rm -rf "$stage"' EXIT INT TERM
staged_app="$stage/cefclient.app"
ditto "$source_app" "$staged_app"

# Keep CEF's compiled bundle name and app/helper identifiers aligned for
# LaunchServices helper registration. Change only the user-visible display name.
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $display_name" "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$staged_app/Contents/Info.plist"
profile_root="$candidate_root/User Data"
mkdir -p "$profile_root"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:THREEF_CEF_PROFILE_ROOT string $profile_root" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment:THREEF_CEF_NATIVE_WINDOW string 1' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment:THREEF_CEF_STARTUP_TRACE string 1' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:THREEF_CEF_STARTUP_LOG string $profile_root/3f-startup.log" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.web-browsers' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :LSApplicationCategoryType public.app-category.web-browsers' "$staged_app/Contents/Info.plist"
cp "$repo_root/Resources/3f-icon.icns" "$staged_app/Contents/Resources/cefclient.icns"

signing_identity="${THREEF_CEF_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --deep --sign - "$staged_app"
else
  entitlements="$stage/entitlements"
  mkdir -p "$entitlements"
  cat > "$entitlements/empty.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
  cat > "$entitlements/jit.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>
PLIST

  framework="$staged_app/Contents/Frameworks/Chromium Embedded Framework.framework"
  libraries="$framework/Versions/Current/Libraries"
  while IFS= read -r -d '' library; do
    if /usr/bin/file -b "$library" | /usr/bin/grep -q 'Mach-O'; then
      codesign --force --sign "$signing_identity" --timestamp=none "$library"
    fi
  done < <(find "$libraries" -type f -print0)
  codesign --force --sign "$signing_identity" --timestamp=none "$framework"

  for helper in "$staged_app"/Contents/Frameworks/cefclient\ Helper*.app; do
    [[ -d "$helper" ]] || continue
    case "$helper" in
      *' (Renderer).app'|*' (GPU).app') helper_entitlements="$entitlements/jit.plist" ;;
      *) helper_entitlements="$entitlements/empty.plist" ;;
    esac
    codesign --force --sign "$signing_identity" --options runtime \
      --timestamp=none --entitlements "$helper_entitlements" "$helper"
  done
  codesign --force --sign "$signing_identity" --options runtime \
    --timestamp=none --entitlements "$entitlements/empty.plist" "$staged_app"
fi
codesign --verify --deep --strict "$staged_app"
mv "$staged_app" "$candidate"
printf 'Created standalone 3F Chromium browser candidate: %s\n' "$candidate"
