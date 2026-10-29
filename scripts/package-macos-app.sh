#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT/output}"
APP="$OUTPUT_DIR/3F Browser.app"
CONTENTS="$APP/Contents"

mkdir -p "$OUTPUT_DIR"
swift build --package-path "$ROOT" --build-path "$ROOT/.build" -c release --product ThreeFBrowser
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/ThreeFBrowser" "$CONTENTS/MacOS/ThreeFBrowser"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
printf 'Created %s\n' "$APP"
