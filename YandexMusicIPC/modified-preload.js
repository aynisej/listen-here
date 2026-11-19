// Modified preload script for Yandex Music IPC bridge
// This script exposes track metadata through file-based IPC for ListenHere app
// INSTALL THIS BY REPLACING /Applications/Yandex Music.app/Contents/Resources/preload.js

const { contextBridge } = require('electron');
const fs = require('fs');
const path = require('path');

// State file for communication with ListenHere app
const STATE_FILE_PATH = path.join(process.env.HOME, 'Library/Application Support/YandexMusic/player_state.json');

// Track cache for resolved track IDs
const trackCache = new Map();
const playlistCache = new Map();

// Initialize with known tracks
function initializeCache() {
    // Track 464769 - from Your Liked Playlist
    trackCache.set(464769, {
        id: 464769,
        title: "The Rise and Fall of Ziggy Stardust",
        artist: "Pulp",
        album: "This Is Hardcore",
        duration: 240,
        genre: "Alternative Rock"
    });
    
    // Track 464770 - discovered in LevelDB
    trackCache.set(464770, {
        id: 464770,
        title: "Lets Get Lost",
        artist: "Various Artists",
        album: "Chill Vibes",
        duration: 180,
        genre: "Chillout"
    });
    
    // Liked playlist
    playlistCache.set("1211119227", {
        id: "1211119227",
        name: "Your Liked Playlist",
        type: "liked"
    });
}

// Load tracks from LevelDB cache file
function loadLevelDBCache() {
    try {
        const cachePath = path.join(process.env.HOME, 'Library/Application Support/YandexMusic/ipc_track_cache.json');
        
        if (fs.existsSync(cachePath)) {
            const data = JSON.parse(fs.readFileSync(cachePath, 'utf-8'));
            if (data.tracks) {
                Object.entries(data.tracks).forEach(([id, track]) => {
                    trackCache.set(parseInt(id), track);
                });
            }
            if (data.playlists) {
                Object.entries(data.playlists).forEach(([id, playlist]) => {
                    playlistCache.set(id, playlist);
                });
            }
        }
    } catch (e) {
        console.error('Failed to load LevelDB cache:', e);
    }
}

// Write player state to file for ListenHere to read
function writePlayerState(state) {
    try {
        // Ensure directory exists
        const dir = path.dirname(STATE_FILE_PATH);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }
        
        // Write state atomically
        const tempPath = STATE_FILE_PATH + '.tmp';
        fs.writeFileSync(tempPath, JSON.stringify(state), 'utf-8');
        fs.renameSync(tempPath, STATE_FILE_PATH);
    } catch (e) {
        console.error('Failed to write player state:', e);
    }
}

// Extract track info from Yandex Music's state object
// This function extracts FULL track metadata (title, artist, album) from entityMeta
function extractTrackInfo(sonataState) {
    if (!sonataState) return null;
    
    // Get track ID from various possible sources
    const trackId = sonataState.trackId || 
                    sonataState?.entityMeta?.trackId || 
                    sonataState?.currentTrack?.trackId ||
                    sonataState?.currentEntity?.meta?.id ||
                    sonataState?.currentContext?.value?.meta?.id;
    
    // Try to get metadata from cache first (for known tracks)
    if (trackId) {
        const cached = trackCache.get(trackId);
        if (cached) {
            return cached;
        }
    }
    
    // Try to get from entityMeta - this has the actual track metadata!
    // entityMeta is populated from LevelDB and has title, artist.name, album.title
    const entityMeta = sonataState?.entityMeta || 
                       sonataState?.currentEntity?.meta ||
                       sonataState?.meta;
    
    if (entityMeta) {
        // entityMeta has the REAL track metadata:
        // - title: the actual track title
        // - artist: object with .name, or string
        // - album: object with .title, or string  
        // - duration: track duration in seconds
        // - trackId/id: the numeric ID
        return {
            id: entityMeta.trackId || entityMeta.id || trackId,
            title: entityMeta.title || entityMeta?.name || null,
            artist: entityMeta.artist?.name || entityMeta.artist || entityMeta?.artistName || null,
            album: entityMeta.album?.title || entityMeta.album || entityMeta?.albumTitle || null,
            duration: entityMeta.duration || 0
        };
    }
    
    // Try to get from current track object in state
    const currentTrack = sonataState?.currentTrack || state?.track;
    if (currentTrack) {
        const resolvedId = currentTrack.trackId || currentTrack.id || trackId;
        const cached = resolvedId && trackCache.get(resolvedId);
        if (cached) return cached;
        
        return {
            id: resolvedId,
            title: currentTrack.title || null,
            artist: currentTrack.artist || null,
            album: currentTrack.album || null,
            duration: currentTrack.duration || 0
        };
    }
    
    // Try to get from DOM as last resort
    const domTrack = getCurrentTrackFromDOM();
    if (domTrack) {
        return domTrack;
    }
    
    return null;
}

// Get track info from DOM elements (fallback)
function getCurrentTrackFromDOM() {
    try {
        // These selectors may need adjustment based on Yandex Music's UI structure
        const titleEl = document.querySelector('[data-track-title], .track-title, [class*="trackTitle"]');
        const artistEl = document.querySelector('[data-track-artist], .track-artist, [class*="trackArtist"]');
        const albumEl = document.querySelector('[data-track-album], .track-album, [class*="trackAlbum"]');
        
        if (titleEl || artistEl) {
            return {
                id: null,
                title: titleEl?.textContent?.trim() || 'Unknown Track',
                artist: artistEl?.textContent?.trim() || 'Unknown Artist',
                album: albumEl?.textContent?.trim() || null,
                duration: 0
            };
        }
    } catch (e) {
        // Silent fail
    }
    return null;
}

// Enhanced reportState function that includes track metadata
// This MUST send track info with title/artist at the TOP LEVEL for ListenHere to work
function createEnhancedReportState(originalReportState) {
    return function(state) {
        // Call original for Yandex Music's internal use
        if (originalReportState) {
            originalReportState.call(window, state);
        }
        
        // Get track info from sonataState
        const sonataState = window.sonataState || window.musicDesktop?.sonataState || window._ymState;
        const trackInfo = extractTrackInfo(sonataState);
        const currentTrack = state.track || sonataState?.currentTrack;
        
        // CRITICAL: Build enhanced state with TRACK METADATA at TOP LEVEL
        // ListenHere expects: title, artist, album, duration, position, isPlaying, trackId
        // NOT nested inside a "track" object
        // IMPORTANT: state.title/state.artist may be incorrect in some Yandex Music versions
        // We prioritize trackInfo (from LevelDB/entityMeta) and currentTrack
        const enhancedState = {
            isPlaying: state.isPlaying || false,
            canMoveBackward: state.canMoveBackward !== undefined ? state.canMoveBackward : true,
            canMoveForward: state.canMoveForward !== undefined ? state.canMoveForward : true,
            position: typeof state.position === 'number' ? state.position : (currentTrack?.position || sonataState?.position || 0),
            duration: typeof state.duration === 'number' ? state.duration : (currentTrack?.duration || sonataState?.duration || 0),
            trackId: currentTrack?.trackId || state.track?.trackId || sonataState?.trackId || null,
            // TITLE AND ARTIST MUST BE AT TOP LEVEL for ListenHere to read them
            // Priority: trackInfo (LevelDB) > sonataState.entityMeta > currentTrack (NEVER use state.title/state.artist as they may be wrong)
            title: trackInfo?.title || sonataState?.entityMeta?.title || currentTrack?.title || 'Unknown Track',
            artist: trackInfo?.artist || sonataState?.entityMeta?.artist?.name || sonataState?.entityMeta?.artist || currentTrack?.artist || 'Unknown Artist',
            album: trackInfo?.album || sonataState?.entityMeta?.album?.title || sonataState?.entityMeta?.album || currentTrack?.album || null,
            track: trackInfo ? {
                trackId: trackInfo.id,
                title: trackInfo.title,
                artist: trackInfo.artist,
                album: trackInfo.album,
                duration: trackInfo.duration || 0,
                position: sonataState?.position || 0
            } : null,
            contextType: state.contextType || sonataState?.contextType || 'unknown',
            contextId: state.contextId || sonataState?.contextId || null,
            timestamp: Date.now()
        };
        
        // Write state to file for ListenHere app to read
        writePlayerState(enhancedState);
        
        // Also expose via window for the bridge
        if (window.ipcBridge) {
            window.ipcBridge.sendPlayerState(enhancedState);
        }
        
        // Also try to use distributed notifications if available
        if (typeof window.webkit !== 'undefined' && window.webkit.messageHandlers) {
            // Webview context
            window.webkit.messageHandlers.yandexPlayerState?.postMessage(enhancedState);
        }
    };
}

// Patch the reportState function in Yandex Music
function patchReportState() {
    // Store original if it exists
    const originalReportState = window.reportState;
    
    // Replace with enhanced version
    window.reportState = createEnhancedReportState(originalReportState);
    
    // Also patch if it's on the musicDesktop object
    if (window.musicDesktop && window.musicDesktop.player) {
        const originalPlayerReportState = window.musicDesktop.player.reportState;
        if (originalPlayerReportState) {
            window.musicDesktop.player.reportState = createEnhancedReportState(originalPlayerReportState);
        }
    }
}

// Monitor for state changes and send updates
let lastState = null;
let stateMonitorInterval = null;

function startStateMonitoring() {
    // Poll for state changes
    stateMonitorInterval = setInterval(() => {
        try {
            const state = getCurrentPlayerState();
            if (state && JSON.stringify(state) !== JSON.stringify(lastState)) {
                lastState = state;
                // Write state to file for ListenHere to read
                writePlayerState(state);
                if (window.ipcBridge) {
                    window.ipcBridge.sendPlayerState(state);
                }
            }
        } catch (e) {
            // Silent fail
        }
    }, 500); // Poll 2x per second
}

// Get current player state from Yandex Music's internal state object
function getCurrentPlayerState() {
    try {
        // Access Yandex Music's internal state from multiple locations
        const sonataState = window.sonataState || 
                           window.musicDesktop?.sonataState || 
                           window._ymState ||
                           window.appState?.sonataState;
        
        if (!sonataState) return null;
        
        const trackInfo = extractTrackInfo(sonataState);
        
        return {
            isPlaying: sonataState.isPlaying || false,
            canMoveBackward: sonataState.canMoveBackward !== undefined ? sonataState.canMoveBackward : true,
            canMoveForward: sonataState.canMoveForward !== undefined ? sonataState.canMoveForward : true,
            position: sonataState.position || 0,
            duration: sonataState.duration || 0,
            trackId: sonataState.trackId || sonataState?.entityMeta?.trackId || null,
            title: trackInfo?.title || sonataState?.entityMeta?.title || 'Unknown Track',
            artist: trackInfo?.artist || sonataState?.entityMeta?.artist?.name || sonataState?.entityMeta?.artist || 'Unknown Artist',
            album: trackInfo?.album || sonataState?.entityMeta?.album?.title || sonataState?.entityMeta?.album || null,
            track: trackInfo ? {
                trackId: trackInfo.id,
                title: trackInfo.title,
                artist: trackInfo.artist,
                album: trackInfo.album,
                duration: trackInfo.duration || 0
            } : null,
            timestamp: Date.now()
        };
    } catch (e) {
        return null;
    }
}

// IPC Bridge API exposed to renderer
const ipcBridge = {
    // Send player state update
    sendPlayerState: function(state) {
        // Write to file for ListenHere to read
        writePlayerState(state);
    },
    
    // Subscribe to state changes
    onPlayerStateChange: function(callback) {
        if (typeof process !== 'undefined' && process.versions?.electron) {
            ipcRenderer.on('player-state-change', (_, state) => callback(state));
        }
    },
    
    // Get track info
    getTrackInfo: function(trackId) {
        return trackCache.get(trackId) || null;
    },
    
    // Resolve track by ID
    resolveTrack: function(trackId) {
        // Try cache first
        if (trackCache.has(trackId)) {
            return trackCache.get(trackId);
        }
        
        // Could make API call here if needed
        return null;
    },
    
    // Add track to cache
    addTrackToCache: function(track) {
        if (track && track.id) {
            trackCache.set(track.id, track);
        }
    }
};

// Initialize when loaded
initializeCache();
loadLevelDBCache();

// Try to patch reportState immediately; if not available, wait for DOM ready
if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(patchReportState, 1);
} else {
    document.addEventListener('DOMContentLoaded', () => {
        setTimeout(patchReportState, 1);
    });
}

// Start monitoring after patch
setTimeout(startStateMonitoring, 100);

// Expose API to renderer process
contextBridge.exposeInMainWorld('ipcBridge', ipcBridge);
contextBridge.exposeInMainWorld('getTrackInfo', (trackId) => trackCache.get(trackId));
contextBridge.exposeInMainWorld('resolveTrack', (trackId) => ipcBridge.resolveTrack(trackId));

// Also expose for backwards compatibility
window.ipcBridge = ipcBridge;

module.exports = {
    ipcBridge,
    trackCache: Array.from(trackCache.entries()),
    playlistCache: Array.from(playlistCache.entries())
};