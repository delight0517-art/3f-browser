#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefclient/Release/cefclient.app"
candidate_root="${1:-$repo_root/.build/3f-cef-full-browser-candidate}"
candidate="$candidate_root/3F Browser Preview.app"

if [[ ! -d "$source_app" ]]; then
  echo "Build the CEF full-browser candidate first: $source_app" >&2
  exit 2
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

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.rogan.threef.browser.cefpreview' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 3F Browser Preview' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 3F Browser Preview' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 3F Browser Preview' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.web-browsers' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :LSApplicationCategoryType public.app-category.web-browsers' "$staged_app/Contents/Info.plist"
cp "$repo_root/Resources/3f-icon.icns" "$staged_app/Contents/Resources/cefclient.icns"

# Keep CEF's helper identifiers under the renamed browser identifier so the
# browser process can resolve its GPU, renderer, plugin, and alert helpers.
for helper in "$staged_app"/Contents/Frameworks/cefclient\ Helper*.app; do
  helper_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$helper/Contents/Info.plist")"
  case "$helper_id" in
    org.cef.cefclient.helper*) suffix="${helper_id#org.cef.cefclient}" ;;
    *) echo "Unexpected CEF helper identifier: $helper_id" >&2; exit 4 ;;
  esac
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.rogan.threef.browser.cefpreview${suffix}" "$helper/Contents/Info.plist"
done

codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mv "$staged_app" "$candidate"
printf 'Created standalone 3F Chromium browser candidate: %s\n' "$candidate"
