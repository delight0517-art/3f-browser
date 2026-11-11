#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefclient/Release/cefclient.app"
candidate_root="${1:-$repo_root/.build/3f-primary-browser-candidate}"
candidate_root="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$candidate_root")"
candidate="$candidate_root/3F Browser.app"
profile_root="$candidate_root/User Data"

if [[ ! -d "$source_app" ]]; then
  echo "Build the CEF full-browser target first: $source_app" >&2
  exit 2
fi

mode_file="$source_app/Contents/Resources/3f-navigation-mode"
if [[ ! -f "$mode_file" || "$(<"$mode_file")" != "full-browser" ]]; then
  echo "Refusing to package a non-full-browser CEF target." >&2
  exit 3
fi

source_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")"
if [[ "$source_bundle_id" != "org.cef.cefclient" ]]; then
  echo "Refusing CEF bundle ID $source_bundle_id; the verified helper rendezvous uses org.cef.cefclient." >&2
  exit 4
fi
if [[ -e "$candidate" ]]; then
  echo "Refusing to replace an existing candidate: $candidate" >&2
  exit 5
fi

mkdir -p "$candidate_root"
stage="$(mktemp -d "$candidate_root/.package-XXXXXX")"
trap 'rm -rf "$stage"' EXIT INT TERM
staged_app="$stage/3F Browser.app"
ditto "$source_app" "$staged_app"

# Keep the tested CEF identity and helper IDs; customize only the browser's
# product-facing name, icon, profile path, and macOS browser category.
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 3F Browser' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 3F Browser' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 3F Browser' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSApplicationCategoryType string public.app-category.web-browsers' "$staged_app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Set :LSApplicationCategoryType public.app-category.web-browsers' "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:THREEF_CEF_PROFILE_ROOT string $profile_root" "$staged_app/Contents/Info.plist"
cp "$repo_root/Resources/3f-icon.icns" "$staged_app/Contents/Resources/cefclient.icns"

codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mv "$staged_app" "$candidate"
mkdir -p "$profile_root"

printf 'Created isolated 3F primary-browser candidate: %s\n' "$candidate"
printf 'Bundle identifier retained for CEF helpers: %s\n' "$source_bundle_id"
printf 'Isolated profile: %s\n' "$profile_root"
