import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {

            Button("Login Last.fm") {
                Task {
                    await LastFmService.shared.startAuth()
                }
            }

            if LastFmService.shared.isLoggedIn {
                Text("Logged in to Last.fm ✅")
                    .foregroundColor(.green)
            } else if LastFmService.shared.hasPendingToken {
                Text("Authorization pending…")
                    .foregroundColor(.orange)
            } else {
                Text("Not logged in")
                    .foregroundColor(.red)
            }

            if LastFmService.shared.hasPendingToken {
                Button("I’ve authorized") {
                    Task {
                        await LastFmService.shared.finishLogin()
                    }
                }
                .disabled(!LastFmService.shared.hasPendingToken)
            }

            Divider()

            if let track = appState.currentTrack {
                Text("Сейчас играет:")
                Text("\(track.artist) — \(track.title)")
                    .font(.headline)
            }

            Text(appState.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
