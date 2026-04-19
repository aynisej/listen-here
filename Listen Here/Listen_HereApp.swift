import SwiftUI

@main
struct Listen_HereApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    print("CALLBACK:", url)
                    Task {
                        await LastFmService.shared.handleCallback(url: url)
                    }
                }
            }
        }
    }

