# Listen Here

Listen Here is a macOS Last.fm scrobbler with a native SwiftUI interface. It reads the currently playing track from the Yandex Music desktop app and submits it to Last.fm after the normal scrobble threshold.

## Yandex Music support

The current implementation reads the visible player metadata from Yandex Music's macOS Accessibility tree. It checks the title, artist, album, play state, elapsed position, and duration. It does not capture, save, or upload audio.

The app runs outside the macOS App Sandbox because Apple does not support cross-application Accessibility APIs from sandboxed apps. This build is intended for direct distribution, not the Mac App Store.

### Alternative: Logging-based monitoring

Since Yandex Music doesn't provide a public API, Listen Here also supports **logging-based monitoring** as a fallback/coping mechanism:

1. **Primary method (default):** Accessibility API - reads the Yandex Music player window directly
2. **Fallback method:** System log monitoring - parses log entries from Yandex Music process

To enable logging-based monitoring:
- Go to **Settings** in the app
- Enable **"Использовать мониторинг через логи"** (Use logging monitor)
- This is useful when Accessibility permissions fail or when Yandex Music UI changes

The logging monitor attempts to:
- Read system logs via the `log` command (macOS unified logging)
- Parse log content for track metadata (supports both JSON and text formats)
- Work even when Accessibility API is blocked

**Note:** Logging-based monitoring may not work if Yandex Music doesn't emit track events to system logs. It requires Yandex Music to use structured logging.

To enable debug logging in Yandex Music (may require Terminal flags):
```bash
# Example: launch Yandex Music with debug output
/Applications/Yandex\ Music.app/Contents/MacOS/Yandex\ Music --debug > ~/yandex-music.log 2>&1
```

To enable Yandex Music scrobbling:

1. Connect a Last.fm account in Settings. The app opens Last.fm authorization in the browser; return to the app and finish the login.
2. Turn on **Scrobbling**.
3. Allow Listen Here under **System Settings → Privacy & Security → Accessibility**. macOS needs this permission to read the Yandex Music player window.
4. Play music in the Yandex Music desktop app.

Tracks shorter than 30 seconds are ignored. A scrobble is submitted after half the track or four minutes, whichever comes first. Network failures are kept in a local queue and retried after connection returns.

## Last.fm behavior

- OAuth-style browser sign-in using Last.fm's token/session flow.
- Session key stored in the macOS Keychain.
- `track.updateNowPlaying` when a new Yandex track starts.
- `track.scrobble` after the listening threshold.
- Recent successful submissions and pending count in the dashboard.

## Build

Open `Listen Here.xcodeproj` in Xcode and build the **Listen Here** scheme for macOS.
