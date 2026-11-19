import SwiftUI

@main
struct Listen_HereApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .defaultSize(width: 980, height: 720)

        Window("Вход в Last.fm", id: "lastfm-login") {
            LoginWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 420, height: 480)
        .windowResizability(.contentSize)
    }
}
