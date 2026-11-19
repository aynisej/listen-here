// Modified preload script for Yandex Music IPC bridge
// This script exposes track metadata through IPC channels

const { contextBridge, ipcRenderer, ipcMain } = require('electron');
const { Notification } = require('electron');
const { remote } = require('electron');

// Track metadata structure
class TrackMetadata {
    constructor(trackId, title, artist, album, duration) {
        this.trackId = trackId;
        this.title = title;
        this.artist = artist;
        this.album = album;
        this.duration = duration;
    }
}

// Player state structure
class PlayerState {
    constructor(isPlaying, canMoveBackward, canMoveForward, track) {
        this.isPlaying = isPlaying;
        this.canMoveBackward = canMoveBackward;
        this.canMoveForward = canMoveForward;
        this.track = track;
    }
}

// IPC Bridge service
const IPCBridge = {
    // Channel names
    CHANNELS: {
        PLAYER_STATE: 'desktop:player:state:metadata',
        TRACK_REQUEST: 'desktop:player:track:request',
        TRACK_RESPONSE: 'desktop:player:track:response'
    },
    
    // Get current player state with track metadata
    getPlayerState: async () => {
        try {
            const state = await ipcRenderer.invoke('get-player-state');
            return state;
        } catch (error) {
            console.error('Failed to get player state:', error);
            return null;
        }
    },
    
    // Listen for player state changes
    onPlayerStateChange: (callback) => {
        ipcRenderer.on('player-state-change', (event, state) => {
            callback(state);
        });
    },
    
    // Request track details for a track ID
    requestTrackDetails: async (trackId) => {
        try {
            const track = await ipcRenderer.invoke('TRACK_RESPONSE', trackId);
            return track;
        } catch (error) {
            console.error('Failed to get track details:', error);
            return null;
        }
    }
};

// Expose safe API to renderer
contextBridge.exposeInMainWorld('ipcBridge', IPCBridge);

// Listen for state changes from main process
ipcRenderer.on('player-state-update', (event, state) => {
    // Broadcast to Listen Here via distributed notification
    const notification = new Notification({
        name: 'com.yandex.music.player.state',
        userInfo: state
    });
    // In a real implementation, this would use NSDistributedNotificationCenter
    // For Electron, we use ipcRenderer event system
});

module.exports = {
    IPCBridge,
    TrackMetadata,
    PlayerState
};