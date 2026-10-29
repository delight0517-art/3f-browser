#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
build_dir="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build"
profile_patch="$repo_root/CEFIntegration/patches/0001-macos-use-app-specific-profile.patch"

if [[ ! -f "$cef_root/CMakeLists.txt" ]]; then
  echo "Missing local CEF 156 distribution: $cef_root" >&2
  exit 2
fi

if git -C "$cef_root" apply --reverse --check "$profile_patch" >/dev/null 2>&1; then
  : # The isolated-profile patch is already applied to this local probe source.
else
  git -C "$cef_root" apply "$profile_patch"
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

codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
printf 'Isolated CEF probe ready: %s\n' "$app_bundle"
