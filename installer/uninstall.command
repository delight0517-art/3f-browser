#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "  3F Browser & Focus Fence Uninstaller"
echo "=========================================="
echo ""

read -r -p "Remove 3F Browser.app and Focus Fence.app from your Mac? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo "Quitting running apps..."
pkill -x ThreeFBrowser 2>/dev/null || true
pkill -x FocusFence 2>/dev/null || true
sleep 1

for app in \
    "/Applications/3F Browser.app" \
    "$HOME/Applications/3F Browser.app" \
    "/Applications/Focus Fence.app" \
    "$HOME/Applications/Focus Fence.app"; do
    if [ -d "$app" ]; then
        echo "Removing $app"
        rm -rf "$app"
    fi
done

echo ""
read -r -p "Also remove saved app data (3F Browser, FocusFence, BlueCloud settings)? [y/N] " REMOVE_DATA
if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    for dir in \
        "$HOME/Library/Application Support/3F Browser" \
        "$HOME/Library/Application Support/FocusFence" \
        "$HOME/Library/Application Support/BlueCloud"; do
        if [ -d "$dir" ]; then
            echo "Removing $dir"
            rm -rf "$dir"
        fi
    done
fi

echo ""
read -r -p "Open System Settings > Desktop & Dock to restore your default web browser? [y/N] " OPEN_SETTINGS
if [[ "$OPEN_SETTINGS" =~ ^[Yy]$ ]]; then
    open "x-apple.systempreferences:com.apple.Desktop-Settings.extension" || true
fi

echo ""
echo "Uninstall complete."
