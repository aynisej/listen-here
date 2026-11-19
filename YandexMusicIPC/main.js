// Modified main process for Yandex Music IPC bridge
// This file should be integrated into Yandex Music's Electron main process

const { app, BrowserWindow, ipcMain, ipcRenderer, Notification } = require('electron');
const { session } = require('electron');
const path = require('path');
const fs = require('fs');

// IPC Bridge service
const IPCBridge = {
    // IPC channel names
    PLAYER_STATE_CHANNEL: 'desktop:player:state:metadata',
    TRACK_DETAILS_CHANNEL: 'desktop:player:track:details',
    
    // Store current player state
    currentState: null,
    
    // Current track information
    currentTrack: null,
    
    // Send player state update to Listen Here
    sendPlayerState(state) {
        this.currentState = state;
        
        // Send via IPC
        if (BrowserWindow.getAllWindows().length > 0) {
            const mainWindow = BrowserWindow.getAllWindows()[0];
            mainWindow.webContents.send('player-state-update', state);
        }
        
        // Also try to use distributed notifications if available
        // This would require native extension
    },
    
    // Request track details from Yandex Music API
    async fetchTrackDetails(trackId) {
        try {
            // Make API call to Yandex Music API to get track details
            // This requires authentication
            const response = await fetch(`https://api.music.yandex.ru/v1/tracks/${trackId}`, {
                headers: {
                    'Authorization': `YandexToken ${getToken()}`
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                return {
                    trackId: trackId,
                    title: data.title || 'Unknown Track',
                    artist: data.artist?.name || 'Unknown Artist',
                    album: data.album?.title || '',
                    duration: data.duration || 0
                };
            }
        } catch (error) {
            console.error('Failed to fetch track details:', error);
        }
        
        return {
            trackId: trackId,
            title: `Track ${trackId}`,
            artist: 'Unknown Artist',
            album: '',
            duration: 0
        };
    }
};

// IPC handlers
ipcMain.handle('get-player-state', async () => {
    return IPCBridge.currentState;
});

ipcMain.handle('TRACK_RESPONSE', async (event, trackId) => {
    return await IPCBridge.fetchTrackDetails(trackId);
});

// Modified reportState function that includes track metadata
function reportStateWithMetadata(isPlaying, canMoveBackward, canMoveForward, trackInfo) {
    const state = {
        isPlaying: isPlaying,
        canMoveBackward: canMoveBackward,
        canMoveForward: canMoveForward,
        track: trackInfo ? {
            trackId: trackInfo.id,
            title: trackInfo.title || 'Unknown Track',
            artist: trackInfo.artist?.name || 'Unknown Artist',
            album: trackInfo.album?.title || '',
            duration: trackInfo.duration || 0,
            position: trackInfo.position || 0
        } : null,
        timestamp: Date.now()
    };
    
    IPCBridge.sendPlayerState(state);
}

// Export for integration
module.exports = {
    IPCBridge,
    reportStateWithMetadata
};

function getToken() {
    // Get token from Yandex Music's authentication system
    // This would need to be extracted from the app's stored credentials
    try {
        const tokenPath = path.join(app.getPath('userData'), '.ya_music_token');
        if (fs.existsSync(tokenPath)) {
            return fs.readFileSync(tokenPath, 'utf-8').trim();
        }
    } catch (e) {
        console.error('Failed to read token:', e);
    }
    return null;
}