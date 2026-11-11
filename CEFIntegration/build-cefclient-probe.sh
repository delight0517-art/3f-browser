#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cef_root="$repo_root/.build/cef-156-arm64/unpacked"
build_dir="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build"
app_bundle="$build_dir/tests/cefclient/Release/cefclient.app"
framework="$app_bundle/Contents/Frameworks/Chromium Embedded Framework.framework"
framework_source="$cef_root/Release/Chromium Embedded Framework.framework"
profile_patch="$repo_root/CEFIntegration/patches/0003-cefclient-profile.patch"
profile_override_patch="$repo_root/CEFIntegration/patches/0010-cefclient-profile-override.patch"
native_window_patch="$repo_root/CEFIntegration/patches/0015-3f-native-window-mode.patch"
auth_policy_patch="$repo_root/CEFIntegration/patches/0005-3f-auth-only-navigation.patch"
auth_redirect_patch="$repo_root/CEFIntegration/patches/0017-3f-auth-callback-redirect-only.patch"
auth_mode_patch="$repo_root/CEFIntegration/patches/0009-3f-auth-only-launch-switch.patch"
auth_policy_header="$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h"
startup_trace_patch="$repo_root/CEFIntegration/patches/0006-3f-startup-trace.patch"
startup_trace_file_patch="$repo_root/CEFIntegration/patches/0011-3f-startup-trace-file.patch"
root_window_trace_patch="$repo_root/CEFIntegration/patches/0012-3f-root-window-startup-trace.patch"
root_views_trace_patch="$repo_root/CEFIntegration/patches/0013-3f-root-views-startup-trace.patch"
views_window_trace_patch="$repo_root/CEFIntegration/patches/0014-3f-views-window-startup-trace.patch"
bundle_id_patch="$repo_root/CEFIntegration/patches/0008-cef-product-bundle-id-at-build.patch"
navigation_mode="${THREEF_CEF_NAVIGATION_MODE:-restricted-auth}"
startup_trace="${THREEF_CEF_STARTUP_TRACE:-0}"
bundle_id="${THREEF_CEF_BUNDLE_ID:-org.cef.cefclient}"

if [[ ! "$bundle_id" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ ]]; then
  echo "Invalid THREEF_CEF_BUNDLE_ID: $bundle_id" >&2
  exit 2
fi

case "$navigation_mode" in
  restricted-auth|full-browser) ;;
  *) echo "Unsupported THREEF_CEF_NAVIGATION_MODE: $navigation_mode" >&2; exit 2 ;;
esac

if [[ ! -f "$cef_root/CMakeLists.txt" || ! -f "$build_dir/build.ninja" ]]; then
  echo "Missing configured CEF 156 isolated build: $build_dir" >&2
  exit 2
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

if grep -q 'root_cache_path' "$cef_root/tests/cefclient/browser/main_context_impl.cc" && \
   grep -q '3f-profile-root' "$cef_root/tests/cefclient/browser/main_context_impl.cc"; then
  : # The base isolated-profile patch is already applied to this local CEF tree.
else
  patch -p1 -i "$profile_patch" -d "$cef_root"
fi

if grep -q 'THREEF_CEF_PROFILE_ROOT' \
    "$cef_root/tests/cefclient/browser/main_context_impl.cc"; then
  : # The profile override is already applied to this local unpacked CEF tree.
else
  patch -p1 -i "$profile_override_patch" -d "$cef_root"
fi
if grep -q 'THREEF_CEF_NATIVE_WINDOW' \
    "$cef_root/tests/cefclient/browser/main_context_impl.cc"; then
  : # The package selects the native macOS window host.
else
  patch -p1 -i "$native_window_patch" -d "$cef_root"
fi

if [[ "$navigation_mode" == "restricted-auth" ]]; then
  if grep -q 'threef_auth_browser_policy.h' \
      "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
    if ! grep -Fq 'return scheme == "https";' "$auth_policy_header"; then
      python3 - "$auth_policy_header" <<'PY'
from pathlib import Path
import sys

header = Path(sys.argv[1])
text = header.read_text()
old = 'if (IsGoogleAuthHost(host)) {\n    return true;\n  }'
new = 'if (IsGoogleAuthHost(host)) {\n    return scheme == "https";\n  }'
if text.count(old) != 1:
    raise SystemExit("Cannot safely update stale 3F Google auth scheme policy.")
header.write_text(text.replace(old, new))
PY
    fi
  else
    patch -p1 -i "$auth_policy_patch" -d "$cef_root"
  fi
  if grep -q 'IsAuthOnlyMode' \
      "$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h"; then
    : # The restricted policy requires 3F's explicit auth-only launch switch.
  else
    patch -p1 -i "$auth_mode_patch" -d "$cef_root"
  fi
  if ! grep -Fq 'bool is_redirect' "$auth_policy_header"; then
    patch -p1 -i "$auth_redirect_patch" -d "$cef_root"
  fi
  grep -Fq '}  // namespace threef_auth' "$auth_policy_header"
  grep -Fq '}  // namespace client' "$auth_policy_header"
else
  policy_header="$cef_root/tests/cefclient/browser/threef_auth_browser_policy.h"
  if [[ -f "$policy_header" ]] && grep -q 'IsAuthOnlyMode' "$policy_header"; then
    patch -R -p1 -i "$auth_mode_patch" -d "$cef_root"
  fi
  if grep -q 'threef_auth_browser_policy.h' \
      "$cef_root/tests/cefclient/browser/base_client_handler.cc"; then
    patch -R -p1 -i "$auth_policy_patch" -d "$cef_root"
  fi
fi

if [[ "$startup_trace" == "1" ]]; then
  if grep -q 'void StartupTrace' "$cef_root/tests/cefclient/cefclient_mac.mm"; then
    : # Already applied to this local unpacked CEF tree.
  else
    patch -p1 -i "$startup_trace_patch" -d "$cef_root"
  fi
  if grep -q 'THREEF_CEF_STARTUP_LOG' "$cef_root/tests/cefclient/cefclient_mac.mm"; then
    : # The trace is already captured in the candidate's isolated profile.
  else
    patch -p1 -i "$startup_trace_file_patch" -d "$cef_root"
  fi
  if grep -q 'RootWindowStartupTrace' \
      "$cef_root/tests/cefclient/browser/root_window_mac.mm"; then
    : # Window lifecycle milestones are already instrumented.
  else
    patch -p1 -i "$root_window_trace_patch" -d "$cef_root"
  fi
  if grep -q 'RootViewsStartupTrace' \
      "$cef_root/tests/cefclient/browser/root_window_views.cc"; then
    : # Views lifecycle milestones are already instrumented.
  else
    patch -p1 -i "$root_views_trace_patch" -d "$cef_root"
  fi
  if grep -q 'ViewsWindowStartupTrace' \
      "$cef_root/tests/cefclient/browser/views_window.cc"; then
    : # Native Views window creation and display are already instrumented.
  else
    patch -p1 -i "$views_window_trace_patch" -d "$cef_root"
  fi
elif grep -q 'StartupTrace(' "$cef_root/tests/cefclient/cefclient_mac.mm"; then
  if grep -q 'ViewsWindowStartupTrace' \
      "$cef_root/tests/cefclient/browser/views_window.cc"; then
    patch -R -p1 -i "$views_window_trace_patch" -d "$cef_root"
  fi
  if grep -q 'RootViewsStartupTrace' \
      "$cef_root/tests/cefclient/browser/root_window_views.cc"; then
    patch -R -p1 -i "$root_views_trace_patch" -d "$cef_root"
  fi
  if grep -q 'RootWindowStartupTrace' \
      "$cef_root/tests/cefclient/browser/root_window_mac.mm"; then
    patch -R -p1 -i "$root_window_trace_patch" -d "$cef_root"
  fi
  if grep -q 'THREEF_CEF_STARTUP_LOG' "$cef_root/tests/cefclient/cefclient_mac.mm"; then
    patch -R -p1 -i "$startup_trace_file_patch" -d "$cef_root"
  fi
  patch -R -p1 -i "$startup_trace_patch" -d "$cef_root"
fi

if grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/mac/Info.plist.in" && \
   grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/mac/helper-Info.plist.in" && \
   grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/CMakeLists.txt"; then
  : # Already applied to this local unpacked CEF tree.
elif grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/mac/Info.plist.in" || \
     grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/mac/helper-Info.plist.in" || \
     grep -q 'CEF_CLIENT_BUNDLE_ID' "$cef_root/tests/cefclient/CMakeLists.txt"; then
  echo "CEF bundle-ID patch is only partially applied." >&2
  exit 5
else
  patch -p1 -i "$bundle_id_patch" -d "$cef_root"
fi

# Reconfigure after applying source patches so CMake generates matching app and
# helper bundle identifiers from one value before code signing.
cmake -S "$cef_root" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.6 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DUSE_SANDBOX=OFF \
  -DCEF_CLIENT_BUNDLE_ID="$bundle_id"

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

# The CMake bundle target can retain stale nested helper bundles after the
# helper Info.plists are regenerated for a different CEF_CLIENT_BUNDLE_ID.
# Sync the freshly generated, identifier-matched helper apps before signing.
python3 - "$app_bundle" "$build_dir/tests/cefclient/Release" <<'PY'
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile

app_bundle = Path(sys.argv[1])
release_dir = Path(sys.argv[2])
frameworks = app_bundle / "Contents/Frameworks"
app_info = plistlib.loads((app_bundle / "Contents/Info.plist").read_bytes())
expected_prefix = app_info["CFBundleIdentifier"] + ".helper"
source_helpers = sorted(release_dir.glob("cefclient Helper*.app"))
if not source_helpers:
    raise SystemExit("CEF helper app outputs are missing.")

with tempfile.TemporaryDirectory(prefix=".cef-helper-sync-", dir=frameworks) as temp:
    staged_root = Path(temp)
    for source in source_helpers:
        info_path = source / "Contents/Info.plist"
        helper_id = plistlib.loads(info_path.read_bytes()).get("CFBundleIdentifier", "")
        if helper_id != expected_prefix and not helper_id.startswith(expected_prefix + "."):
            raise SystemExit(f"CEF helper bundle ID mismatch: {source.name}: {helper_id}")
        shutil.copytree(source, staged_root / source.name, symlinks=True)

    for source in source_helpers:
        destination = frameworks / source.name
        if destination.exists() or destination.is_symlink():
            if destination.is_dir() and not destination.is_symlink():
                shutil.rmtree(destination)
            else:
                destination.unlink()
        (staged_root / source.name).rename(destination)
PY

for helper in "$app_bundle"/Contents/Frameworks/cefclient\ Helper*.app; do
  codesign --force --deep --sign - "$helper"
done
codesign --force --sign - "$framework"
printf '%s\n' "$navigation_mode" > \
  "$app_bundle/Contents/Resources/3f-navigation-mode"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
printf 'Isolated Chromium browser candidate ready: %s\n' "$app_bundle"
