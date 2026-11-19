#!/bin/bash
# Installation script for Modified Yandex Music IPC Bridge
# This script patches Yandex Music to include proper track metadata in IPC channel
# 
# Usage:
#   ./install-modified-yandex-music.sh       # Install IPC bridge (modifies preload.js)
#   ./install-modified-yandex-music.sh --uninstall  # Restore original files

set -e

YANDEX_MUSIC_APP="/Applications/Yandex Music.app"
BACKUP_DIR="$HOME/Library/Application Support/YandexMusic/ipc-bridge-backup"
IPC_BRIDGE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Yandex Music IPC Bridge Installer ==="
echo ""

# Handle uninstall
if [ "$1" = "--uninstall" ]; then
    echo "Uninstalling IPC bridge..."
    
    if [ -f "$BACKUP_DIR/preload.js.backup" ]; then
        mkdir -p "$YANDEX_MUSIC_APP/Contents/Resources/"
        cp "$BACKUP_DIR/preload.js.backup" "$YANDEX_MUSIC_APP/Contents/Resources/preload.js"
        echo "Restored original preload.js"
    else
        # Try to remove our added files
        if [ -f "$YANDEX_MUSIC_APP/Contents/Resources/preload.js" ]; then
            rm -f "$YANDEX_MUSIC_APP/Contents/Resources/preload.js"
            echo "Removed preload.js"
        fi
    fi
    
    if [ -f "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib" ]; then
        rm -f "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib"
        echo "Removed ipc-bridge.dylib"
    fi
    
    echo ""
    echo "=== Uninstall Complete ==="
    echo "Please restart Yandex Music for changes to take effect."
    exit 0
fi

# Check if Yandex Music is installed
if [ ! -d "$YANDEX_MUSIC_APP" ]; then
    echo "Error: Yandex Music not found at $YANDEX_MUSIC_APP"
    echo "Please install Yandex Music first."
    exit 1
fi

echo "Found Yandex Music at $YANDEX_MUSIC_APP"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if modified-preload.js exists
MODIFIED_PRELOAD="$IPC_BRIDGE_DIR/modified-preload.js"
if [ ! -f "$MODIFIED_PRELOAD" ]; then
    echo "Error: modified-preload.js not found in $IPC_BRIDGE_DIR"
    echo "Please ensure you're running this script from the YandexMusicIPC directory."
    exit 1
fi

# Create Resources directory if it doesn't exist
mkdir -p "$YANDEX_MUSIC_APP/Contents/Resources/"

# Backup original preload.js if it exists
ORIGINAL_PRELOAD="$YANDEX_MUSIC_APP/Contents/Resources/preload.js"
if [ -f "$ORIGINAL_PRELOAD" ]; then
    cp "$ORIGINAL_PRELOAD" "$BACKUP_DIR/preload.js.backup"
    echo "Backed up original preload.js"
fi

# Copy modified preload.js
cp "$MODIFIED_PRELOAD" "$ORIGINAL_PRELOAD"
chmod 644 "$ORIGINAL_PRELOAD"
echo "Installed modified preload.js"

# Compile and install IPC bridge dylib
IPCBridge_DYLIB="$IPC_BRIDGE_DIR/ipc-bridge.dylib"
IPCBridge_SRC="$IPC_BRIDGE_DIR/ipc-bridge.dylib.c"

if [ -f "$IPCBridge_SRC" ]; then
    echo "Compiling ipc-bridge.dylib..."
    clang -shared -fPIC \
        -install_name @rpath/ipc-bridge.dylib \
        -o "$IPCBridge_DYLIB" \
        "$IPCBridge_SRC" \
        -framework Foundation \
        -framework CoreFoundation \
        -target $(arch -machines -x86_64) 2>/dev/null || \
    clang -shared -fPIC \
        -install_name @rpath/ipc-bridge.dylib \
        -o "$IPCBridge_DYLIB" \
        "$IPCBridge_SRC" \
        -framework Foundation \
        -framework CoreFoundation
    
    # Install the dylib
    cp "$IPCBridge_DYLIB" "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib"
    chmod 755 "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib"
    echo "Installed ipc-bridge.dylib"
elif [ -f "$IPCBridge_DYLIB" ]; then
    cp "$IPCBridge_DYLIB" "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib"
    chmod 755 "$YANDEX_MUSIC_APP/Contents/Resources/ipc-bridge.dylib"
    echo "Installed existing ipc-bridge.dylib"
else
    echo "Warning: No ipc-bridge.dylib found or compiled"
fi

# Ensure track cache directory exists
TRACK_CACHE_DIR="$HOME/Library/Application Support/YandexMusic"
mkdir -p "$TRACK_CACHE_DIR"

# Copy track cache if not exists
TRACK_CACHE="$IPC_BRIDGE_DIR/track_cache.json"
if [ -f "$TRACK_CACHE" ] && [ ! -f "$TRACK_CACHE_DIR/ipc_track_cache.json" ]; then
    cp "$TRACK_CACHE" "$TRACK_CACHE_DIR/ipc_track_cache.json"
    echo "Installed track cache"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "The modified Yandex Music now includes IPC bridge support."
echo "Please restart Yandex Music for changes to take effect."
echo ""
echo "In Listen Here, select 'IPC' mode for best track metadata resolution."
echo ""
echo "Backup files are stored at: $BACKUP_DIR"