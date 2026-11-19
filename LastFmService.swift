import Foundation
import AppKit
import Combine
import Security

@MainActor
final class LastFmService: ObservableObject {
    static let shared = LastFmService()

    @Published private(set) var username: String?
    @Published private(set) var pendingToken: String?
    @Published private(set) var errorMessage: String?

    private var sessionKey: String? {
        didSet {
            if let sessionKey { saveSessionKey(sessionKey) }
            else { deleteSessionKey() }
        }
    }

    private init() {
        sessionKey = readSessionKey()
        username = UserDefaults.standard.string(forKey: "lastfm_username")
    }

    var hasPendingToken: Bool { pendingToken != nil }
    var isLoggedIn: Bool { sessionKey != nil }
    var sessionUsername: String? { username }

    func startAuth() async {
        errorMessage = nil
        do {
            let token = try await LastFMAPI.shared.getToken()
            pendingToken = token
            NSWorkspace.shared.open(LastFMAPI.shared.authorizationURL(token: token))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reopenAuthorizationPage() {
        guard let pendingToken else { return }
        NSWorkspace.shared.open(LastFMAPI.shared.authorizationURL(token: pendingToken))
    }

    func finishLogin() async {
        guard let pendingToken else { return }
        errorMessage = nil
        do {
            let session = try await LastFMAPI.shared.getSession(token: pendingToken)
            sessionKey = session.key
            username = session.username
            UserDefaults.standard.set(session.username, forKey: "lastfm_username")
            self.pendingToken = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        sessionKey = nil
        username = nil
        UserDefaults.standard.removeObject(forKey: "lastfm_username")
        pendingToken = nil
    }

    func sendNowPlaying(_ item: LastFMScrobble) async throws {
        guard let sessionKey else { throw LastFMError.api("Сначала подключите Last.fm") }
        try await LastFMAPI.shared.updateNowPlaying(item, sessionKey: sessionKey)
    }

    func scrobble(_ item: LastFMScrobble) async throws {
        guard let sessionKey else { throw LastFMError.api("Сначала подключите Last.fm") }
        try await LastFMAPI.shared.submit(item, sessionKey: sessionKey)
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "listen-here.lastfm",
         kSecAttrAccount as String: "session-key"]
    }

    private func readSessionKey() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        // Migrate earlier builds' session key from defaults into Keychain.
        if let legacy = UserDefaults.standard.string(forKey: "lastfm_session_key") {
            UserDefaults.standard.removeObject(forKey: "lastfm_session_key")
            saveSessionKey(legacy)
            return legacy
        }
        return nil
    }

    private func saveSessionKey(_ value: String) {
        var query = keychainQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(keychainQuery as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteSessionKey() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}
