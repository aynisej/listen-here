# Yandex Music IPC Bridge

This directory contains the modified Yandex Music client components that enable proper track metadata scrobbling through IPC channels.

## Overview

The IPC Bridge allows Listen Here to receive detailed track information (title, artist, album, duration) from Yandex Music through a distributed notification system.

## Components

### 1. preload.js
Modified Electron preload script that exposes the IPC bridge API to Yandex Music's renderer process.

### 2. main.js
Modified main process additions that handle IPC messages and API calls to Yandex Music.

### 3. renderer-patch.js
JavaScript patches for instrumenting Yandex Music's player state management and extracting track metadata.

### 4. ipc-bridge.dylib
Native macOS dynamic library that provides distributed notification support.

### 5. patch-layout.js
Patch file for modifying Yandex Music's layout JavaScript to include track metadata in the `reportState` function.

## Installation

Run the installation script:

```bash
cd /path/to/YandexMusicIPC
chmod +x install-modified-yandex-music.sh
./install-modified-yandex-music.sh
```

## IPC Channels

### PLAYER_STATE (`desktop:player:state:metadata`)
Sends player state with track metadata:

```json
{
    "isPlaying": true,
    "canMoveBackward": true,
    "canMoveForward": true,
    "track": {
        "trackId": 464769,
        "title": "The Rise and Fall of Ziggy Stardust",
        "artist": "Pulp",
        "album": "This Is Hardcore",
        "duration": 240,
        "position": 120.5
    },
    "timestamp": 1699123456789
}
```

## Track Metadata Sources

Yandex Music provides track information from multiple sources:

1. **entityMeta** - Direct track metadata from Yandex Music's state object
2. **Context info** - Playlist/album information for radio tracks
3. **DOM scraping** - Fallback method to extract track info from UI elements
4. **API calls** - Yandex Music API for resolving track IDs

## Integration with Listen Here

Listen Here's IPC mode automatically:
- Detects the modified Yandex Music installation
- Subscribes to `com.yandex.music.player.state` notifications
- Receives track metadata in real-time
- Handles scrobbling to Last.fm

## API Reference

See `last_fm_api.md` for scrobbling API details.

## Troubleshooting

1. **No track info**: Ensure modified Yandex Music is installed correctly
2. **IPC not working**: Check if Yandex Music was restarted after installation
3. **Wrong track names**: The bridge uses multiple fallback methods to find track info

## Building the dylib

For macOS development, compile the native extension:

```bash
clang -shared -fPIC \
    -o ipc-bridge.dylib ipc-bridge.dylib.c \
    -framework Foundation \
    -framework CoreFoundation \
    -target arm64-apple-macos14.0
```