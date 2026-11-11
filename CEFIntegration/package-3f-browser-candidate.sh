#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefclient/Release/cefclient.app"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
candidate_root="${1:-$repo_root/.build/3f-cef-full-browser-candidate}"
candidate_root="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$candidate_root")"
candidate="$candidate_root/3F Browser Preview.app"
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
staged_app="$stage/3F Browser Preview.app"
ditto "$source_app" "$staged_app"

# Keep CEF's compiled app/helper identifiers together; changing only the app
# bundle ID breaks helper rendezvous.
/usr/libexec/PlistBuddy -c "Set :CFBundleName $display_name" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $display_name" "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$staged_app/Contents/Info.plist"
profile_root="$candidate_root/User Data"
mkdir -p "$profile_root"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:THREEF_CEF_PROFILE_ROOT string $profile_root" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment:THREEF_CEF_STARTUP_TRACE string 1' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:THREEF_CEF_STARTUP_LOG string $profile_root/3f-startup.log" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.web-browsers' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :LSApplicationCategoryType public.app-category.web-browsers' "$staged_app/Contents/Info.plist"
cp "$repo_root/Resources/3f-icon.icns" "$staged_app/Contents/Resources/cefclient.icns"

codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mv "$staged_app" "$candidate"
printf 'Created standalone 3F Chromium browser candidate: %s\n' "$candidate"
