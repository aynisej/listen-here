# Listen Here

Listen Here is a macOS Last.fm scrobbler with a native SwiftUI interface. It reads the currently playing track from Yandex Music and submits it to Last.fm after the normal scrobble threshold.

## 🚀 Quick Start

### Download

Go to **[Releases](https://github.com/aynisej/listen-here/releases/tag/v1.0.0)** and download:

| File | Size | Description |
|------|------|-------------|
| `Listen.Here.dmg` | 757KB | Main application |
| `YandexMusicIPC-Installer.dmg` | 1.4MB | IPC Bridge modifier |
| `Complete-Installer.dmg` | 1.3MB | All-in-one installer |

### Installation

**Option 1: Complete Installer (Recommended)**
1. Download `Complete-Installer.dmg`
2. Open the DMG and follow the installer
3. Drag "Listen Here" to Applications
4. Run Yandex Music IPC Bridge Installer to modify Yandex Music
5. **Restart Yandex Music**
6. Launch Listen Here and select **IPC** mode in Settings

**Option 2: Manual Installation**
1. `Listen Here.dmg` → drag app to Applications
2. `YandexMusicIPC-Installer.dmg` → run installer script

## 📻 Scrobbling Methods

Listen Here supports four scrobbling methods, selectable in the Settings panel:

### 1. System Now Playing (Recommended for AirPlay/Bluetooth/Wi-Fi)

Uses Apple's `MPNowPlayingInfoCenter` to read system-wide "Now Playing" information.

**Pros:** Works with AirPlay/Bluetooth/Wi-Fi, no permissions required  
**Cons:** Requires macOS 11+

### 2. Accessibility API (For desktop Yandex Music)

Reads the visible player metadata directly from Yandex Music's window using the Accessibility API.

**Pros:** Works for standalone desktop playback  
**Cons:** Requires Accessibility permissions

### 3. Logging-based Monitoring

A fallback mechanism that parses system logs or log files from Yandex Music.

### 4. IPC Bridge (Best for Yandex Music with Modified Client)

**The most accurate method** - provides proper track metadata (title, artist, not just trackId numbers).

**Installation:**
```bash
# 1. Backup Yandex Music
cp -R "/Applications/Yandex Music.app" "/Applications/Yandex Music.app.backup"

# 2. Run the installer
cd YandexMusicIPC-Installer
chmod +x install-modified-yandex-music.sh
./install-modified-yandex-music.sh

# 3. Restart Yandex Music
```

## 🔧 Last.fm Setup

1. Connect a Last.fm account in **Settings**
2. Enable **Scrobbling**
3. Select your preferred scrobbling method:
   - **System Now Playing** - for AirPlay/Bluetooth/Wi-Fi
   - **Accessibility** - for desktop app
   - **Logging** - fallback
   - **IPC** - for modified Yandex Music (best accuracy)

## 🎵 Track Metadata Resolution

Tracks are resolved from Yandex Music's LevelDB and entityMeta structures, NOT from potentially incorrect `state.title`/`state.album` fields.

### Known Track Mappings

```
Track 464769 → "Lets Get Lost" by Chat Baker (Album: "His 'n' Herds")
Track 464770 → "Disco 2000" by Pulp (Album: "This Is Hardcore")
```

### Cache Location

```
~/Library/Application Support/YandexMusic/ipc_track_cache.json
```

## ⚙️ Scrobbling Behavior

- Tracks shorter than 30 seconds are ignored
- A scrobble is submitted after half the track duration or 4 minutes, whichever comes first
- Network failures are queued and retried automatically

## 🔐 Last.fm API Integration

- OAuth-style browser sign-in
- Session key stored in macOS Keychain
- `track.updateNowPlaying` when a new track starts
- `track.scrobble` after the listening threshold

## 🛠️ Build

```bash
# Build using Swift Package Manager
swift build -c release

# Or open in Xcode
open Listen\ Here.xcodeproj
```

## 📋 Requirements

- macOS 14.0 or later
- Swift 6.0

## 📄 License

This project is provided as-is for personal use. Not intended for commercial distribution.