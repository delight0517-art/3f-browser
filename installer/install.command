#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THREEF_SRC="$SCRIPT_DIR/3F Browser.app"
FF_SRC="$SCRIPT_DIR/Focus Fence.app"

echo "=========================================="
echo "  3F Browser & Focus Fence Installer"
echo "=========================================="
echo ""

install_app() {
    local src="$1"
    local name="$2"
    local target="/Applications/$name"
    if [ ! -w "/Applications" ]; then
        target="$HOME/Applications/$name"
        mkdir -p "$HOME/Applications"
    fi
    echo "Installing $name -> $target"
    rm -rf "$target"
    ditto "$src" "$target"
    xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
    printf '%s\n' "$target"
}

THREEF_DEST=""
FF_DEST=""

if [ -d "$THREEF_SRC" ]; then
    THREEF_DEST="$(install_app "$THREEF_SRC" "3F Browser.app" | tail -n 1)"
    echo "Installed 3F Browser at: $THREEF_DEST"
else
    echo "Note: 3F Browser.app not found next to install.command; skipping 3F Browser install."
fi

if [ -d "$FF_SRC" ]; then
    FF_DEST="$(install_app "$FF_SRC" "Focus Fence.app" | tail -n 1)"
    echo "Installed Focus Fence at: $FF_DEST"
fi

echo ""
if [ -n "$THREEF_DEST" ]; then
    read -r -p "Open System Settings > Desktop & Dock to set 3F Browser as your default browser? [y/N] " SET_DEFAULT
    if [[ "$SET_DEFAULT" =~ ^[Yy]$ ]]; then
        open "x-apple.systempreferences:com.apple.Desktop-Settings.extension" || true
    fi
fi

if [ -n "$FF_DEST" ]; then
    echo ""
    echo "Focus Fence can block unverified/distracting browsers (Safari, Chrome, etc.) so browsing stays protected inside 3F Browser."
    read -r -p "Do you consent to launching Focus Fence with browser blocking enabled? [y/N] " ENABLE_FF
    if [[ "$ENABLE_FF" =~ ^[Yy]$ ]]; then
        open "$FF_DEST"
        echo "Focus Fence launched."
    else
        echo "Skipped launching Focus Fence. You can open it manually later from $FF_DEST."
    fi
fi

if [ -n "$THREEF_DEST" ]; then
    open "$THREEF_DEST"
    echo "3F Browser launched."
fi

echo ""
echo "Installation complete!"
