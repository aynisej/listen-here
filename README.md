# Listen Here

Listen Here is a macOS Last.fm scrobbler with a native SwiftUI interface. It reads the currently playing track from Yandex Music and submits it to Last.fm after the normal scrobble threshold.

## Scrobbling Methods

Listen Here supports three scrobbling methods, selectable in the Settings panel:

### 1. System Now Playing (Recommended for Yandex Music via AirPlay/Bluetooth/Wi-Fi)

This is the most reliable method. It uses Apple's `MPNowPlayingInfoCenter` to read system-wide "Now Playing" information, which works regardless of how Yandex Music is playing (desktop app, AirPlay, Bluetooth, or Wi-Fi).

**How it works:**
- Monitors the system's now playing info via `MPNowPlayingInfoCenter.default().nowPlayingInfo`
- Works with Yandex Music, Spotify, Apple Music, and any app that publishes now playing info
- Detects playback state through `playbackRate` value

**Pros:**
- Works with AirPlay/Bluetooth/Wi-Fi playback
- No Accessibility permissions required
- Most reliable for Yandex Music streamed content

**Cons:**
- Requires macOS 11+

### 2. Accessibility API (For desktop Yandex Music)

The default method when selecting "Accessibility" monitoring. Reads the visible player metadata directly from Yandex Music's window using the Accessibility API.

**How it works:**
- Uses `AXUIElementCopyAttributeValue` to read Yandex Music's player window
- Parses title, artist, album, position, duration, and play state
- Works with the Yandex Music desktop application

**Pros:**
- Works for standalone desktop playback
- No need for Yandex Music to log track info

**Cons:**
- Requires Accessibility permissions from System Settings
- May break if Yandex Music UI changes

### 3. Logging-based Monitoring

A fallback mechanism that parses system logs or log files from Yandex Music.

**How it works:**
- Reads macOS unified logs via the `log` command
- Parses JSON or text log entries for track metadata
- Can also read from custom log files specified in settings

**Pros:**
- Works when Accessibility API is blocked
- Useful as a fallback when other methods fail

**Cons:**
- May not work if Yandex Music doesn't emit track events to logs
- Requires Yandex Music to use structured logging

## Enabling Logging Mode

To enable logging-based monitoring:
1. Go to **Settings** in the app
2. Enable **"Использовать мониторинг через логи"** (Use logging monitor)
3. Optionally specify a custom log file path

**Note:** Logging-based monitoring will auto-create a log file at:
```
~/Library/Caches/YandexMusic/logs/current.log
```

## Installation

Download the latest `Listen Here.dmg` from the releases page:

1. Open the DMG file
2. Drag "Listen Here" to your Applications folder
3. Launch the app

## Last.fm Setup

To enable Yandex Music scrobbling:

1. Connect a Last.fm account in Settings. The app opens Last.fm authorization in the browser; return to the app and finish the login.
2. Turn on **Scrobbling**.
3. Select your preferred scrobbling method in Settings:
   - **System Now Playing** - for AirPlay/Bluetooth/Wi-Fi playback
   - **Accessibility** - for desktop app playback (may require permission)
   - **Logging** - fallback method for when others fail

For Accessibility method:
4. Allow Listen Here under **System Settings → Privacy & Security → Accessibility**

## Scrobbling Behavior

- Tracks shorter than 30 seconds are ignored
- A scrobble is submitted after half the track duration or 4 minutes, whichever comes first
- Network failures are kept in a local queue and retried automatically
- Recent successful submissions and pending count displayed in the dashboard

## Last.fm API Integration

- OAuth-style browser sign-in using Last.fm's token/session flow
- Session key stored in the macOS Keychain
- `track.updateNowPlaying` when a new track starts
- `track.scrobble` after the listening threshold

## Build

```bash
# Build using Swift Package Manager
swift build -c release

# Or open in Xcode
open Listen\ Here.xcodeproj
```

## Requirements

- macOS 14.0 or later
- Swift 6.0

## License

This project is provided as-is for personal use. Not intended for commercial distribution.