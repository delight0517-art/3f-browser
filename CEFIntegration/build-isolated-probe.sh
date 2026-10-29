#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
build_dir="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build"
profile_patch="$repo_root/CEFIntegration/patches/0001-macos-use-app-specific-profile.patch"
load_log_patch="$repo_root/CEFIntegration/patches/0002-log-load-callbacks.patch"

if [[ ! -f "$cef_root/CMakeLists.txt" ]]; then
  echo "Missing local CEF 156 distribution: $cef_root" >&2
  exit 2
fi

if git -C "$cef_root" apply --reverse --check "$profile_patch" >/dev/null 2>&1; then
  : # The isolated-profile patch is already applied to this local probe source.
else
  git -C "$cef_root" apply "$profile_patch"
fi
if ! git -C "$cef_root" apply --reverse --check "$load_log_patch" >/dev/null 2>&1; then
  git -C "$cef_root" apply "$load_log_patch"
fi

cmake -S "$cef_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.6 \
  -DUSE_SANDBOX=OFF
cmake --build "$build_dir" --target cefsimple --parallel 6

app_bundle="$build_dir/tests/cefsimple/Release/cefsimple.app"
if [[ ! -d "$app_bundle" ]]; then
  echo "CEF probe bundle was not produced: $app_bundle" >&2
  exit 3
fi

# CEF 156's sample CMake macro copies the framework root into Versions/A,
# which recursively creates an A -> A symlink. Replace only this generated
# framework copy with the distribution's real Versions/A payload.
framework="$app_bundle/Contents/Frameworks/Chromium Embedded Framework.framework"
framework_source="$cef_root/Release/Chromium Embedded Framework.framework"
rm -rf "$framework/Versions/A"
mkdir -p "$framework/Versions/A"
cp -R "$framework_source/" "$framework/Versions/A/"
ln -sfn A "$framework/Versions/Current"
ln -sfn "Versions/A/Chromium Embedded Framework" "$framework/Chromium Embedded Framework"
ln -sfn "Versions/A/Libraries" "$framework/Libraries"
ln -sfn "Versions/A/Resources" "$framework/Resources"

# Sign nested helper bundles and the framework before the outer app bundle.
for helper in "$app_bundle"/Contents/Frameworks/cefsimple\ Helper*.app; do
  codesign --force --deep --sign - "$helper"
done
codesign --force --sign - "$framework"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
printf 'Isolated CEF probe ready: %s\n' "$app_bundle"
