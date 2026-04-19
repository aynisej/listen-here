import AppKit

final class LastFmService {
    static let shared = LastFmService()

    func openAuth(token: String) {

        let apiKey = "2fc0217be36469e4726dbeb8481e4c34"

        let url = URL(string:

            "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)&cb=listenhere://callback"

        )!

        NSWorkspace.shared.open(url)

    }
    func startAuth() async {
        do {
            let token = try await LastFMAPI.shared.getToken()

            let authURL = URL(string:
                "https://www.last.fm/api/auth/?api_key=\(token)&cb=listenhere://callback"
            )!

            NSWorkspace.shared.open(authURL)

        } catch {
            print("❌ Auth error:", error)
        }
    }

    func handleCallback(url: URL) async {
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?.value else {
            return
        }

        do {
            let session = try await LastFMAPI.shared.getSession(token: token)
            print("SESSION:", session)
        } catch {
            print("❌ Session error:", error)
        }
    }
}
