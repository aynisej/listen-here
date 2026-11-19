/**
 * Yandex Music Layout Patch Template
 * 
 * This is a TEMPLATE for patching Yandex Music's layout JavaScript file.
 * Find the layout-559f...js file in app.asar and apply this patch.
 * 
 * ORIGINAL CODE (find this pattern):
 * (e)=>{let{sonata:t}=e,a=(0,iS.c)(e=>{var t;let{isPlaying:a,canMoveBackward:r,canMoveForward:i}=e;null==(t=window.musicDesktop)||t.player.reportState({isPlaying:a,canMoveBackward:r,canMoveForward:i})})}
 * 
 * REPLACEMENT:
 */

// Enhanced player state reporter with track metadata
(function() {
    // Store original reportState reference
    const originalReportState = window.reportState;
    const originalMusicDesktopReportState = window.musicDesktop?.player?.reportState;
    
    // Track cache
    const trackCache = new Map();
    
    // Initialize with known tracks
    function initCache() {
        // Track 464769 - from Your Liked Playlist (discovered in LevelDB)
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
    }
    
    // Extract track info from sonata state
    function extractTrackInfo(e) {
        const sonata = e.sonata;
        if (!sonata) return null;
        
        // Get track ID
        const trackId = sonata.trackId || sonata.entityMeta?.trackId;
        
        // Try cache first
        if (trackId && trackCache.has(trackId)) {
            return trackCache.get(trackId);
        }
        
        // Try entityMeta
        if (sonata.entityMeta) {
            return {
                id: sonata.entityMeta.trackId || trackId,
                title: sonata.entityMeta.title || null,
                artist: sonata.entityMeta.artist?.name || sonata.entityMeta.artist || null,
                album: sonata.entityMeta.album?.title || sonata.entityMeta.album || null,
                duration: sonata.entityMeta.duration || 0
            };
        }
        
        // Try to get from current track object
        try {
            const playerState = window.musicDesktop?.player?.state;
            if (playerState?.track) {
                return playerState.track;
            }
        } catch (e) {}
        
        return null;
    }
    
    // Create enhanced state reporter
    function createEnhancedReporter() {
        return function(e) {
            const sonata = e.sonata;
            
            // Extract basic state
            const isPlaying = e.isPlaying;
            const canMoveBackward = e.canMoveBackward;
            const canMoveForward = e.canMoveForward;
            
            // Get track info
            const trackInfo = extractTrackInfo(e);
            
            // Build enhanced state
            const enhancedState = {
                isPlaying: isPlaying,
                canMoveBackward: canMoveBackward,
                canMoveForward: canMoveForward,
                track: trackInfo ? {
                    trackId: trackInfo.id,
                    title: trackInfo.title,
                    artist: trackInfo.artist,
                    album: trackInfo.album,
                    duration: trackInfo.duration || 0,
                    position: sonata?.position || 0
                } : null,
                timestamp: Date.now()
            };
            
            // Send via IPC bridge to Listen Here
            if (window.ipcBridge) {
                window.ipcBridge.sendPlayerState(enhancedState);
            }
            
            // Call original reportState for Yandex Music's internal use
            if (originalReportState) {
                originalReportState.call(window, {
                    isPlaying: isPlaying,
                    canMoveBackward: canMoveBackward,
                    canMoveForward: canMoveForward
                });
            }
            
            // Also call musicDesktop.player.reportState if available
            try {
                const t = window.musicDesktop;
                if (t && t.player) {
                    t.player.reportState({
                        isPlaying: isPlaying,
                        canMoveBackward: canMoveBackward,
                        canMoveForward: canMoveForward
                    });
                }
            } catch (e) {}
        };
    }
    
    // Initialize
    initCache();
    
    // Override the original reporter
    window.reportState = createEnhancedReporter();
    
    // If musicDesktop exists, patch its player.reportState too
    if (window.musicDesktop && window.musicDesktop.player) {
        const originalPlayerReportState = window.musicDesktop.player.reportState;
        window.musicDesktop.player.reportState = createEnhancedReporter();
    }
    
    // Also export enhanced reporter
    window.createEnhancedReporter = createEnhancedReporter;
    window.extractTrackInfo = extractTrackInfo;
    window.trackCache = trackCache;
})();

/**
 * END PATCH TEMPLATE
 * 
 * HOW TO APPLY:
 * 1. Extract app.asar: npx @electron/asar extract app.asar app/
 * 2. Find layout file: find app/ -name "layout-*.js" -type f
 * 3. Patch the file with the replacement code above
 * 4. Re-pack: npx @electron/asar pack app/ app.asar
 * 5. Replace the original app.asar in Yandex Music.app
 */