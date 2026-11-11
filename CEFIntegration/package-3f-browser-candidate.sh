#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefclient/Release/cefclient.app"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
candidate_root="${1:-$repo_root/.build/3f-cef-full-browser-candidate}"
candidate="$candidate_root/3F Browser Preview.app"

if [[ ! -d "$source_app" ]]; then
  echo "Build the CEF full-browser candidate first: $source_app" >&2
  exit 2
fi
if [[ ! -f "$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h" ]] || \
   ! grep -q 'threef_auth::IsAllowedNavigation' \
     "$cef_root/tests/cefclient/browser/base_client_handler.cc" || \
   ! grep -q 'threef_auth::IsAllowedNavigation' \
     "$cef_root/tests/cefclient/browser/client_handler.cc" || \
   ! grep -q 'threef_auth::IsAllowedResource' \
     "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
  echo "Refusing to package an unrestricted CEF build. Rebuild with THREEF_CEF_NAVIGATION_MODE=restricted-auth." >&2
  exit 4
fi
if [[ -e "$candidate" ]]; then
  echo "Refusing to replace an existing candidate: $candidate" >&2
  exit 3
fi

mkdir -p "$candidate_root"
stage="$(mktemp -d "$candidate_root/.package-XXXXXX")"
trap 'rm -rf "$stage"' EXIT INT TERM
staged_app="$stage/3F Browser Preview.app"
ditto "$source_app" "$staged_app"

# Keep CEF's compiled app/helper identifiers together. Rewriting them after
# linking breaks the helper Mach rendezvous service; set product IDs at build time.
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 3F Browser Preview' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 3F Browser Preview' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 3F Browser Preview' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.web-browsers' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :LSApplicationCategoryType public.app-category.web-browsers' "$staged_app/Contents/Info.plist"
cp "$repo_root/Resources/3f-icon.icns" "$staged_app/Contents/Resources/cefclient.icns"

codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mv "$staged_app" "$candidate"
printf 'Created standalone 3F Chromium browser candidate: %s\n' "$candidate"
