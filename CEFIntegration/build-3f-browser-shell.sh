#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
build_dir="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build"
profile_patch="$repo_root/CEFIntegration/patches/0001-macos-use-app-specific-profile.patch"
load_patch="$repo_root/CEFIntegration/patches/0002-log-load-callbacks.patch"
shell_patch="$repo_root/CEFIntegration/patches/0007-3f-cefsimple-browser-shell.patch"

if [[ ! -f "$cef_root/CMakeLists.txt" || ! -f "$build_dir/build.ninja" ]]; then
  echo "Missing configured CEF 156 arm64 source/build: $cef_root" >&2
  exit 2
fi

apply_once() {
  local patch_file="$1"
  if git -C "$cef_root" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    return
  fi
  git -C "$cef_root" apply "$patch_file"
}

apply_once "$profile_patch"
apply_once "$load_patch"
apply_once "$shell_patch"

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
cmake -S "$cef_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.6 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DUSE_SANDBOX=OFF
cmake --build "$build_dir" --target cefsimple --parallel 6

app_bundle="$build_dir/tests/cefsimple/Release/cefsimple.app"
framework="$app_bundle/Contents/Frameworks/Chromium Embedded Framework.framework"
framework_source="$cef_root/Release/Chromium Embedded Framework.framework"
if [[ ! -d "$app_bundle" || ! -d "$framework_source" ]]; then
  echo "CEF browser-shell build output is incomplete." >&2
  exit 3
fi

python3 - "$framework" "$framework_source" <<'PY'
from pathlib import Path
import shutil
import sys

framework, source = map(Path, sys.argv[1:])
versions_a = framework / "Versions/A"
if versions_a.exists() or versions_a.is_symlink():
    shutil.rmtree(versions_a) if versions_a.is_dir() and not versions_a.is_symlink() else versions_a.unlink()
versions_a.mkdir(parents=True)
shutil.copytree(source, versions_a, dirs_exist_ok=True)
for name, target in (
    ("Versions/Current", "A"),
    ("Chromium Embedded Framework", "Versions/A/Chromium Embedded Framework"),
    ("Libraries", "Versions/A/Libraries"),
    ("Resources", "Versions/A/Resources"),
):
    link = framework / name
    if link.exists() or link.is_symlink():
        shutil.rmtree(link) if link.is_dir() and not link.is_symlink() else link.unlink()
    link.symlink_to(target)
PY

for helper in "$app_bundle"/Contents/Frameworks/cefsimple\ Helper*.app; do
  codesign --force --deep --sign - "$helper"
done
codesign --force --sign - "$framework"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
printf '3F CEF Views browser-shell build ready: %s\n' "$app_bundle"
