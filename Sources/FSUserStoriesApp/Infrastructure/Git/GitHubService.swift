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
            if status == errSecAuthFailed {
                L10n.string("macOS could not access Keychain. Lock and unlock the login keychain in Keychain Access, then try again.")
            } else {
                String(
                    format: L10n.string("Keychain error: %@"),
                    SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                )
            }
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
                // Direct Swift Package runs are ad-hoc signed and can lack the
                // Keychain entitlement. Authorization must still complete; the
                // app keeps the token only in memory when secure storage fails.
                try? storeToken(token)
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
        let baseName = repositoryName("\(name)-user-stories")
        for attempt in 1...50 {
            let candidate = attempt == 1 ? baseName : "\(baseName)-\(attempt)"
            var request = URLRequest(url: URL(string: "https://api.github.com/user/repos")!)
            request.httpMethod = "POST"
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": candidate,
                "description": "User stories shared with FS User Stories",
                "private": true,
                "auto_init": false,
                "has_issues": false,
                "has_projects": false,
                "has_wiki": false
            ])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 422,
               let apiError = try? JSONDecoder().decode(APIError.self, from: data),
               apiError.isRepositoryNameConflict {
                continue
            }
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
        throw GitHubServiceError.api(
            L10n.string("GitHub could not find an available repository name.")
        )
    }

    func inviteCollaborator(
        username: String,
        repositoryURL: String,
        token: String
    ) async throws {
        guard let repository = githubRepositoryPath(from: repositoryURL) else {
            throw GitHubServiceError.api(L10n.string("This is not a GitHub repository."))
        }
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty,
              let escapedUsername = normalizedUsername.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
              ),
              let url = URL(
                string: "https://api.github.com/repos/\(repository)/collaborators/\(escapedUsername)"
              ) else {
            throw GitHubServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["permission": "push"])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubServiceError.invalidResponse
        }
        guard response.statusCode == 201 || response.statusCode == 204 else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).displayMessage)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw GitHubServiceError.api(message)
        }
    }

    func storedToken() throws -> String? {
        var lastFailure: OSStatus?
        for baseQuery in Self.tokenQueries {
            var query = baseQuery
            query.merge([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]) { _, new in new }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { continue }
            if status == errSecSuccess,
               let data = result as? Data,
               let token = String(data: data, encoding: .utf8) {
                return token
            }
            lastFailure = status
        }
        if let lastFailure { throw GitHubServiceError.keychain(lastFailure) }
        return nil
    }

    private static var baseTokenQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
    }

    private static var tokenQueries: [[String: Any]] {
        var protected = baseTokenQuery
        protected[kSecUseDataProtectionKeychain as String] = true
        protected[kSecAttrSynchronizable as String] = false
        return [protected, baseTokenQuery]
    }

    private func storeToken(_ token: String) throws {
        let value = [kSecValueData as String: Data(token.utf8)]
        var lastFailure = errSecNotAvailable
        for query in Self.tokenQueries {
            let updateStatus = SecItemUpdate(query as CFDictionary, value as CFDictionary)
            if updateStatus == errSecSuccess { return }
            guard updateStatus == errSecItemNotFound else {
                lastFailure = updateStatus
                continue
            }

            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus == errSecSuccess { return }
            lastFailure = addStatus
        }
        throw GitHubServiceError.keychain(lastFailure)
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
            let message = (try? JSONDecoder().decode(APIError.self, from: data).displayMessage)
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

    private func githubRepositoryPath(from value: String) -> String? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("git@github.com:") {
            normalized.removeFirst("git@github.com:".count)
        } else if let url = URL(string: normalized), url.host?.lowercased() == "github.com" {
            normalized = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        let parts = normalized.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return parts.map(String.init).joined(separator: "/")
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
    let errors: [Detail]?

    struct Detail: Decodable {
        let resource: String?
        let code: String?
        let field: String?
        let message: String?
    }

    var isRepositoryNameConflict: Bool {
        errors?.contains { detail in
            detail.resource == "Repository" && detail.field == "name"
        } == true
    }

    var displayMessage: String {
        let details = errors?.compactMap(\.message).filter { !$0.isEmpty } ?? []
        return details.isEmpty ? message : "\(message) \(details.joined(separator: " "))"
    }
}
