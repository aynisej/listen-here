// Renderer process patch for Yandex Music IPC bridge
// This script should be injected into Yandex Music's renderer process

// Monkey-patch the player state reporting to include track metadata

// Store the original reportState function
const originalReportState = window.reportState;

if (originalReportState) {
    // Override reportState to include track metadata
    window.reportState = function(state) {
        // Call the original function
        originalReportState.call(window, state);
        
        // Get track information from the player state
        const trackInfo = extractTrackInfo(window.sonataState);
        
        // Build enhanced state object
        const enhancedState = {
            isPlaying: state.isPlaying,
            canMoveBackward: state.canMoveBackward,
            canMoveForward: state.canMoveForward,
            track: trackInfo ? {
                trackId: trackInfo.id,
                title: trackInfo.title || 'Unknown Track',
                artist: trackInfo.artist?.name || 'Unknown Artist',
                album: trackInfo.album?.title || '',
                duration: trackInfo.duration || 0,
                position: window.sonataState?.position || 0
            } : null,
            timestamp: Date.now()
        };
        
        // Send via IPC
        if (window.ipcBridge) {
            window.ipcBridge.sendPlayerState(enhancedState);
        }
    };
}

// Helper function to extract track info from sonata state
function extractTrackInfo(sonataState) {
    if (!sonataState) return null;
    
    const entityMeta = sonataState.entityMeta;
    const contextType = sonataState.contextType;
    const contextId = sonataState.contextId;
    
    if (!entityMeta || !entityMeta.trackId) {
        return null;
    }
    
    return {
        id: entityMeta.trackId,
        title: entityMeta.title || null,
        artist: entityMeta.artist || null,
        album: entityMeta.album || null,
        duration: entityMeta.duration || 0
    };
}

// Alternative: Monitor state changes via MutationObserver
const stateObserver = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-playing') {
            // Player state changed, extract and send updated state
            const state = getCurrentPlayerState();
            if (state) {
                sendPlayerStateUpdate(state);
            }
        }
    });
});

// Start observing
if (document.querySelector('.player')) {
    stateObserver.observe(document.querySelector('.player'), {
        attributes: true,
        subtree: true
    });
}

// Alternative: Poll for state changes
setInterval(() => {
    const currentState = getPlayerStateFromDOM();
    if (currentState) {
        sendPlayerStateUpdate(currentState);
    }
}, 1000);

// Get current player state from DOM
function getPlayerStateFromDOM() {
    const playerElement = document.querySelector('[data-player-state]');
    if (!playerElement) return null;
    
    try {
        const isPlaying = playerElement.getAttribute('data-playing') === 'true';
        const position = parseFloat(playerElement.getAttribute('data-position') || '0');
        const duration = parseFloat(playerElement.getAttribute('data-duration') || '0');
        
        // Try to extract track info
        const titleEl = document.querySelector('.track-title') || document.querySelector('[data-track-title]');
        const artistEl = document.querySelector('.track-artist') || document.querySelector('[data-track-artist]');
        const albumEl = document.querySelector('.track-album') || document.querySelector('[data-track-album]');
        
        const title = titleEl ? titleEl.textContent.trim() : 'Unknown Track';
        const artist = artistEl ? artistEl.textContent.trim() : 'Unknown Artist';
        const album = albumEl ? albumEl.textContent.trim() : '';
        
        return {
            isPlaying,
            position,
            duration,
            track: {
                title,
                artist,
                album
            }
        };
    } catch (e) {
        console.error('Error extracting player state from DOM:', e);
        return null;
    }
}

// Send player state update via IPC
function sendPlayerStateUpdate(state) {
    if (window.ipcBridge) {
        window.ipcBridge.sendPlayerState(state);
    }
}

// Get player state from Yandex Music's internal state object
function getCurrentPlayerState() {
    try {
        // Access Yandex Music's internal sonata state
        const sonataState = window.sonataState || window.musicDesktop?.sonataState || window._ymState;
        
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
        console.error('Error accessing player state:', e);
        return null;
    }
}

export { extractTrackInfo, getCurrentPlayerState, sendPlayerStateUpdate };