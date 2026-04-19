import Foundation
import AppKit

@MainActor
final class LastFmService {
    static let shared = LastFmService()

    private init() {
        self.sessionKey = UserDefaults.standard.string(forKey: "lastfm_session_key")
    }

    private var pendingToken: String?

    private var sessionKey: String? {
        didSet {
            UserDefaults.standard.set(sessionKey, forKey: "lastfm_session_key")
        }
    }

    var hasPendingToken: Bool {
        pendingToken != nil
    }

    var isLoggedIn: Bool {
        sessionKey != nil
    }

    func startAuth() async {
        do {
            let token = try await LastFMAPI.shared.getToken()
            pendingToken = token

            let apiKey = "2fc0217be36469e4726dbeb8481e4c34"

            guard let url = URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)") else {
                print("❌ Bad URL")
                return
            }

            NSWorkspace.shared.open(url)

        } catch {
            print("❌ Auth error:", error)
        }
    }

    func finishLogin() async {
        guard let token = pendingToken else {
            print("❌ No pending token")
            return
        }

        do {
            let session = try await LastFMAPI.shared.getSession(token: token)
            print("✅ SESSION:", session)
            sessionKey = session
            pendingToken = nil
        } catch {
            print("❌ Session error:", error)
        }
    }
}
