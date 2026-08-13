// SPDX-License-Identifier: MIT

import Foundation
import Security

enum GitHubServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case authorizationPending
    case authorizationExpired
    case authorizationDenied
    case api(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.string("GitHub repository creation is not configured in this build.")
        case .invalidResponse:
            L10n.string("GitHub returned an invalid response.")
        case .authorizationPending:
            L10n.string("Waiting for GitHub authorization…")
        case .authorizationExpired:
            L10n.string("The GitHub authorization code expired. Try again.")
        case .authorizationDenied:
            L10n.string("GitHub authorization was cancelled.")
        case let .api(message):
            message
        case let .keychain(status):
            "Keychain error: \(status)"
        }
    }
}

struct GitHubDeviceAuthorization: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: TimeInterval
}

struct GitHubRepository: Sendable {
    let name: String
    let fullName: String
    let cloneURL: String
    let webURL: URL
}

struct GitHubService: Sendable {
    private static let apiVersion = "2022-11-28"
    private static let keychainService = "com.fsuserstories.app.github"
    private static let keychainAccount = "oauth-token"

    private let clientID: String
    private let session: URLSession

    init(clientID: String? = nil, session: URLSession = .shared) {
        let configuredID = clientID
            ?? ProcessInfo.processInfo.environment["FS_GITHUB_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "FSGitHubOAuthClientID") as? String
            ?? Self.bundledClientID()
            ?? ""
        self.clientID = configuredID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    private static func bundledClientID() -> String? {
        guard let url = Bundle.module.url(forResource: "GitHub", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return object["OAuthClientID"] as? String
    }

    var isConfigured: Bool {
        !clientID.isEmpty && clientID != "YOUR_GITHUB_OAUTH_CLIENT_ID"
    }

    func beginAuthorization() async throws -> GitHubDeviceAuthorization {
        guard isConfigured else { throw GitHubServiceError.notConfigured }
        let response: DeviceCodeResponse = try await postForm(
            URL(string: "https://github.com/login/device/code")!,
            values: ["client_id": clientID, "scope": "repo"]
        )
        guard let verificationURL = URL(string: response.verificationURI) else {
            throw GitHubServiceError.invalidResponse
        }
        return GitHubDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURL: verificationURL,
            expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)),
            interval: TimeInterval(response.interval)
        )
    }

    func finishAuthorization(_ authorization: GitHubDeviceAuthorization) async throws -> String {
        var interval = authorization.interval
        while Date.now < authorization.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            let response: AccessTokenResponse = try await postForm(
                URL(string: "https://github.com/login/oauth/access_token")!,
                values: [
                    "client_id": clientID,
                    "device_code": authorization.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            if let token = response.accessToken {
                try storeToken(token)
                return token
            }
            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "expired_token":
                throw GitHubServiceError.authorizationExpired
            case "access_denied":
                throw GitHubServiceError.authorizationDenied
            case let message?:
                throw GitHubServiceError.api(response.errorDescription ?? message)
            case nil:
                throw GitHubServiceError.invalidResponse
            }
        }
        throw GitHubServiceError.authorizationExpired
    }

    func createPrivateRepository(name: String, token: String) async throws -> GitHubRepository {
        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos")!)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": repositoryName(name),
            "description": "User stories shared with FS User Stories",
            "private": true,
            "auto_init": false,
            "has_issues": false,
            "has_projects": false,
            "has_wiki": false
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, expected: 201)
        let repository = try JSONDecoder().decode(RepositoryResponse.self, from: data)
        guard let webURL = URL(string: repository.htmlURL) else {
            throw GitHubServiceError.invalidResponse
        }
        return GitHubRepository(
            name: repository.name,
            fullName: repository.fullName,
            cloneURL: repository.cloneURL,
            webURL: webURL
        )
    }

    func storedToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw GitHubServiceError.keychain(status)
        }
        return token
    }

    private func storeToken(_ token: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GitHubServiceError.keychain(status) }
    }

    private func postForm<Response: Decodable>(
        _ url: URL,
        values: [String: String]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, expected: 200)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data, expected: Int) throws {
        guard let response = response as? HTTPURLResponse else {
            throw GitHubServiceError.invalidResponse
        }
        guard response.statusCode == expected else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw GitHubServiceError.api(message)
        }
    }

    private func repositoryName(_ value: String) -> String {
        let components = value.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted
        )
        let name = components.filter { !$0.isEmpty }.joined(separator: "-")
        return String((name.isEmpty ? "fs-user-stories" : name).prefix(90))
    }

    private func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
        case errorDescription = "error_description"
    }
}

private struct RepositoryResponse: Decodable {
    let name: String
    let fullName: String
    let cloneURL: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case cloneURL = "clone_url"
        case htmlURL = "html_url"
    }
}

private struct APIError: Decodable {
    let message: String
}
