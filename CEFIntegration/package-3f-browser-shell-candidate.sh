#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_app="$repo_root/.build/cef-156-arm64/cefsimple-isolated-build/tests/cefsimple/Release/cefsimple.app"
candidate_root="${1:-$repo_root/.build/3f-cefsimple-browser-shell-v6-candidate}"
candidate="$candidate_root/3F Browser Shell Candidate.app"

if [[ ! -d "$source_app" ]]; then
  echo "Build the 3F CEF browser shell first: $source_app" >&2
  exit 2
fi
if [[ -e "$candidate" ]]; then
  echo "Refusing to replace existing candidate: $candidate" >&2
  exit 3
fi

mkdir -p "$candidate_root"
python3 - "$source_app" "$candidate_root" "$repo_root/Resources/3f-icon.icns" <<'PY'
from pathlib import Path
import shutil
import sys
import tempfile
import subprocess

source, root, icon = map(Path, sys.argv[1:])
target = root / "3F Browser Shell Candidate.app"
if target.exists():
    raise SystemExit(f"Refusing to replace existing candidate: {target}")

with tempfile.TemporaryDirectory(prefix=".3f-shell-package-", dir=root) as temp:
    staged = Path(temp) / target.name
    shutil.copytree(source, staged, symlinks=True)
    plist = staged / "Contents/Info.plist"
    for key, value in (
        ("LSApplicationCategoryType", "public.app-category.web-browsers"),
    ):
        result = subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :{key} {value}", str(plist)], capture_output=True)
        if result.returncode:
            subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Add :{key} string {value}", str(plist)], check=True, stdout=subprocess.DEVNULL)
    shutil.copy2(icon, staged / "Contents/Resources/cefsimple.icns")
    for helper in (staged / "Contents/Frameworks").glob("cefsimple Helper*.app"):
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(helper)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(staged)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
    staged.rename(target)
PY
printf 'Created isolated 3F CEF Views browser-shell candidate: %s\n' "$candidate"
