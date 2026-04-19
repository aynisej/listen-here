import Foundation
import CryptoKit

final class LastFMAPI {
    static let shared = LastFMAPI()

    private let apiKey = "2fc0217be36469e4726dbeb8481e4c34"
    private let apiSecret = "6da4151a280b2237dbfe4e0d7589c6f3"

    private init() {}

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }

    // MARK: - Get Token
    func getToken() async throws -> String {
        let url = URL(string:
            "https://ws.audioscrobbler.com/2.0/?method=auth.getToken&api_key=\(apiKey)&format=json"
        )!

        let (data, _) = try await makeSession().data(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["token"] as? String else {
            throw NSError(domain: "LastFM", code: -1)
        }

        return token
    }

    // MARK: - Get Session
    func getSession(token: String) async throws -> String {
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]

        let signature = makeSignature(params: params)
        params["api_sig"] = signature
        params["format"] = "json"

        // Build POST body (URL-encoded)
        let bodyString = params
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        var request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, _) = try await makeSession().data(for: request)

        // Debug raw response
        if let raw = String(data: data, encoding: .utf8) {
            print("📦 RAW SESSION RESPONSE:", raw)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let error = json?["error"], let message = json?["message"] {
            print("❌ LastFM API ERROR:", error, message)
        }

        let session = json?["session"] as? [String: Any]
        guard let key = session?["key"] as? String else {
            throw NSError(domain: "LastFM", code: -2)
        }

        return key
    }

    // MARK: - Signature
    private func makeSignature(params: [String: String]) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let base = sorted.map { "\($0.key)\($0.value)" }.joined() + apiSecret
        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
