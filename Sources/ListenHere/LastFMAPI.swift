import Foundation
import CryptoKit

struct LastFMSession {
    let key: String
    let username: String
}

struct LastFMScrobble {
    let track: Track
    let album: String?
    let duration: Int
    let timestamp: Int
}

// LastFMAPI is MainActor-isolated because it's used from the UI context
// All async methods dispatch to background automatically via URLSession
@MainActor
final class LastFMAPI {
    // Singleton instance accessible from MainActor context
    static let shared = LastFMAPI()

    // Desktop clients need an API key/secret to sign Last.fm write requests.
    private let apiKey = "2fc0217be36469e4726dbeb8481e4c34"
    private let apiSecret = "6da4151a280b2237dbfe4e0d7589c6f3"
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    private init() {}

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }

    func getToken() async throws -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "method", value: "auth.getToken"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, response) = try await makeSession().data(from: components.url!)
        try validateHTTP(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["message"] as? String { throw LastFMError.api(error) }
        guard let token = json?["token"] as? String else { throw LastFMError.invalidResponse }
        return token
    }

    func authorizationURL(token: String) -> URL {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    func getSession(token: String) async throws -> LastFMSession {
        let parameters = ["method": "auth.getSession", "api_key": apiKey, "token": token]
        let json = try await post(parameters)
        guard let session = json["session"] as? [String: Any],
              let key = session["key"] as? String,
              let username = session["name"] as? String else {
            throw LastFMError.invalidResponse
        }
        return LastFMSession(key: key, username: username)
    }

    func updateNowPlaying(_ scrobble: LastFMScrobble, sessionKey: String) async throws {
        var parameters: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": scrobble.track.artist,
            "track": scrobble.track.title,
            "duration": String(scrobble.duration),
            "api_key": apiKey,
            "sk": sessionKey
        ]
        if let album = scrobble.album, !album.isEmpty { parameters["album"] = album }
        _ = try await post(parameters)
    }

    func submit(_ scrobble: LastFMScrobble, sessionKey: String) async throws {
        var parameters: [String: String] = [
            "method": "track.scrobble",
            "artist": scrobble.track.artist,
            "track": scrobble.track.title,
            "timestamp": String(scrobble.timestamp),
            "duration": String(scrobble.duration),
            "api_key": apiKey,
            "sk": sessionKey
        ]
        if let album = scrobble.album, !album.isEmpty { parameters["album"] = album }
        _ = try await post(parameters)
    }

    private func post(_ parameters: [String: String]) async throws -> [String: Any] {
        var signed = parameters
        signed["api_sig"] = makeSignature(params: parameters)
        signed["format"] = "json"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = signed.sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await makeSession().data(for: request)
        try validateHTTP(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let message = json["message"] as? String, json["error"] != nil {
            throw LastFMError.api(message)
        }
        if let scrobbles = json["scrobbles"] as? [String: Any],
           let ignored = scrobbles["@attr"] as? [String: String], ignored["ignored"] == "1" {
            throw LastFMError.api("Last.fm отклонил этот трек как неподходящие метаданные")
        }
        return json
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LastFMError.http(status)
        }
    }

    private func makeSignature(params: [String: String]) -> String {
        let base = params.sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined() + apiSecret
        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

enum LastFMError: LocalizedError {
    case api(String)
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        case .http(let code): return "Ошибка Last.fm (HTTP \(code))"
        case .invalidResponse: return "Last.fm вернул неожиданный ответ"
        }
    }
}