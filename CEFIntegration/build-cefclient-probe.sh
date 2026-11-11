#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
build_dir="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build"
app_bundle="$build_dir/tests/cefclient/Release/cefclient.app"
framework="$app_bundle/Contents/Frameworks/Chromium Embedded Framework.framework"
framework_source="$cef_root/Release/Chromium Embedded Framework.framework"
profile_patch="$repo_root/CEFIntegration/patches/0003-cefclient-profile.patch"
auth_policy_patch="$repo_root/CEFIntegration/patches/0005-3f-auth-only-navigation.patch"
navigation_mode="${THREEF_CEF_NAVIGATION_MODE:-restricted-auth}"

case "$navigation_mode" in
  restricted-auth|full-browser) ;;
  *) echo "Unsupported THREEF_CEF_NAVIGATION_MODE: $navigation_mode" >&2; exit 2 ;;
esac

if [[ ! -f "$cef_root/CMakeLists.txt" || ! -f "$build_dir/build.ninja" ]]; then
  echo "Missing configured CEF 156 isolated build: $build_dir" >&2
  exit 2
fi

# CEF's generated Ninja files can retain an SDK versioned path across Xcode
# updates. Reconfigure against the currently selected SDK before compiling.
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
cmake -S "$cef_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.6 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DUSE_SANDBOX=OFF

if patch --dry-run -R -p1 -i "$profile_patch" -d "$cef_root" >/dev/null 2>&1; then
  : # Already applied to this local unpacked CEF tree.
else
  patch -p1 -i "$profile_patch" -d "$cef_root"
fi

if [[ "$navigation_mode" == "restricted-auth" ]]; then
  if grep -q 'threef_auth_browser_policy.h' \
      "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
    : # Already applied to this local unpacked CEF tree.
  else
    patch -p1 -i "$auth_policy_patch" -d "$cef_root"
  fi
elif grep -q 'threef_auth_browser_policy.h' \
    "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
  patch -R -p1 -i "$auth_policy_patch" -d "$cef_root"
fi

cmake --build "$build_dir" --target cefclient --parallel 6

if [[ ! -d "$app_bundle" || ! -d "$framework_source" ]]; then
  echo "CEF Browser shell output is incomplete." >&2
  exit 3
fi

# CEF 156's sample CMake macro copies a flat framework inside Versions/A,
# creating a recursive A -> A link. Rebuild only this generated copy.
python3 - "$framework" "$framework_source" <<'PY'
from pathlib import Path
import shutil
import sys

framework = Path(sys.argv[1])
source = Path(sys.argv[2])
versions_a = framework / "Versions/A"
if versions_a.exists() or versions_a.is_symlink():
    if versions_a.is_dir() and not versions_a.is_symlink():
        shutil.rmtree(versions_a)
    else:
        versions_a.unlink()
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
        if link.is_dir() and not link.is_symlink():
            shutil.rmtree(link)
        else:
            link.unlink()
    link.symlink_to(target)
PY

for helper in "$app_bundle"/Contents/Frameworks/cefclient\ Helper*.app; do
  codesign --force --deep --sign - "$helper"
done
codesign --force --sign - "$framework"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
printf 'Isolated Chromium browser candidate ready: %s\n' "$app_bundle"
