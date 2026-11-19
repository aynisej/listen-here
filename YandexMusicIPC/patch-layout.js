/**
 * Patch for Yandex Music layout-559f...js
 * This patch modifies the reportState function to include track metadata
 * 
 * Apply this patch by:
 * 1. Extract app.asar from Yandex Music
 * 2. Find the layout chunk file (e.g., layout-559f151556799079.js)
 * 3. Replace the reportState call with the enhanced version below
 * 4. Re-pack app.asar
 */

// ORIGINAL CODE (what needs to be replaced):
// (e)=>{let{sonata:t}=e,a=(0,iS.c)(e=>{var t;let{isPlaying:a,canMoveBackward:r,canMoveForward:i}=e;null==(t=window.musicDesktop)||t.player.reportState({isPlaying:a,canMoveBackward:r,canMoveForward:i})})}

// MODIFIED CODE (with track metadata):
const reportStateWithMetadata = (e) => {
    const sonata = e.sonata;
    const a = (0, iS.c)(e) => {
        var t;
        
        // Get basic player state
        const isPlaying = e.isPlaying;
        const canMoveBackward = e.canMoveBackward;
        const canMoveForward = e.canMoveForward;
        
        // Extract track metadata from sonata state
        const trackMetadata = extractTrackMetadata(e);
        
        // Build enhanced state object
        const enhancedState = {
            isPlaying,
            canMoveBackward,
            canMoveForward,
            track: trackMetadata ? {
                trackId: trackMetadata.trackId,
                title: trackMetadata.title,
                artist: trackMetadata.artist,
                album: trackMetadata.album,
                duration: trackMetadata.duration,
                position: trackMetadata.position
            } : null,
            timestamp: Date.now()
        };
        
        // Send via IPC bridge if available
        if (window.ipcBridge) {
            window.ipcBridge.sendPlayerState(enhancedState);
        }
        
        // Call original reportState for Yandex Music's internal use
        null == (t = window.musicDesktop) || t.player.reportState({
            isPlaying,
            canMoveBackward,
            canMoveForward
        });
    };
};

// Helper function to extract track metadata from Yandex Music state
function extractTrackMetadata(e) {
    if (!e.sonata) return null;
    
    const sonataState = e.sonata;
    const entityMeta = sonataState.entityMeta;
    const contextType = sonataState.contextType;
    const contextId = sonataState.contextId;
    
    // Radio tracks don't have traditional metadata in entityMeta
    // We need to check multiple sources
    
    // Primary source: entityMeta
    if (entityMeta && entityMeta.trackId) {
        return {
            trackId: entityMeta.trackId,
            title: entityMeta.title || null,
            artist: entityMeta.artist ? (entityMeta.artist.name || entityMeta.artist) : null,
            album: entityMeta.album ? (entityMeta.album.title || entityMeta.album) : null,
            duration: entityMeta.duration || 0,
            position: sonataState.position || 0
        };
    }
    
    // Secondary source: context information
    if (contextType && contextId) {
        // For radio, we might need to fetch track info from API
        // This would require additional API calls
        return {
            trackId: null,
            title: 'Radio Track',
            artist: 'Unknown Artist',
            album: contextType,
            duration: 0,
            position: sonataState.position || 0
        };
    }
    
    // Fallback: try to get from current track object
    const currentTrack = getCurrentTrackFromDOM();
    if (currentTrack) {
        return {
            trackId: currentTrack.id,
            title: currentTrack.title,
            artist: currentTrack.artist,
            album: currentTrack.album,
            duration: currentTrack.duration,
            position: sonataState.position || 0
        };
    }
    
    return null;
}

// Helper function to get current track from DOM (fallback method)
function getCurrentTrackFromDOM() {
    try {
        // Look for track info in the DOM
        const titleEl = document.querySelector('[data-track-title], .track-title, [class*="trackTitle"]');
        const artistEl = document.querySelector('[data-track-artist], .track-artist, [class*="trackArtist"]');
        const albumEl = document.querySelector('[data-track-album], .track-album, [class*="trackAlbum"]');
        
        return {
            id: window.currentTrackId || null,
            title: titleEl ? titleEl.textContent.trim() : null,
            artist: artistEl ? artistEl.textContent.trim() : null,
            album: albumEl ? albumEl.textContent.trim() : null,
            duration: 0
        };
    } catch (e) {
        return null;
    }
}

// Alternative: Monitor state changes via global state object
let lastState = null;
setInterval(() => {
    const currentState = getPlayerStateFromWindow();
    if (currentState && JSON.stringify(currentState) !== JSON.stringify(lastState)) {
        lastState = currentState;
        if (window.ipcBridge) {
            window.ipcBridge.sendPlayerState(currentState);
        }
    }
}, 1000);

// Get player state from Yandex Music's window object
function getPlayerStateFromWindow() {
    try {
        // Multiple possible locations for player state
        const musicDesktop = window.musicDesktop;
        const sonataState = window.sonataState || musicDesktop?.sonataState || window._ymState;
        
        if (!sonataState) return null;
        
        return {
            isPlaying: sonataState.isPlaying || false,
            canMoveBackward: sonataState.canMoveBackward !== undefined ? sonataState.canMoveBackward : true,
            canMoveForward: sonataState.canMoveForward !== undefined ? sonataState.canMoveForward : true,
            position: sonataState.position || 0,
            duration: sonataState.duration || 0,
            track: {
                trackId: sonataState.trackId || sonataState.entityMeta?.trackId,
                title: sonataState.title || sonataState.entityMeta?.title,
                artist: sonataState.artist?.name || sonataState.entityMeta?.artist?.name,
                album: sonataState.album?.title || sonataState.entityMeta?.album?.title,
                duration: sonataState.duration || sonataState.entityMeta?.duration
            }
        };
    } catch (e) {
        return null;
    }
}

// For integration with Yandex Music, also patch localStorage to store last known track
const originalLocalStorageSetItem = localStorage.setItem;
localStorage.setItem = function(key, value) {
    if (key === 'lastTrack' || key.startsWith('ym_')) {
        try {
            const parsed = JSON.parse(value);
            // Add timestamp for IPC bridge
            parsed.timestamp = Date.now();
            localStorage.setItem(key, JSON.stringify(parsed));
            // Notify IPC bridge
            if (window.ipcBridge) {
                window.ipcBridge.sendPlayerState(getPlayerStateFromWindow());
            }
            return;
        } catch (e) {
            // Not JSON, use original
        }
    }
    originalLocalStorageSetItem.call(this, key, value);
};

module.exports = {
    reportStateWithMetadata,
    extractTrackMetadata,
    getCurrentTrackFromDOM,
    getPlayerStateFromWindow
};