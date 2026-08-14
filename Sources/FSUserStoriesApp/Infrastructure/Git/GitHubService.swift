// SPDX-License-Identifier: MIT

import Foundation
import Security

enum GitHubServiceError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
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

struct GitHubDeviceAuthorization: Codable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: UInt64
}

struct GitHubRepository: Codable, Sendable {
    let name: String
    let fullName: String
    let cloneURL: String
    let webURL: URL
}

/// Thin macOS adapter. GitHub HTTP, polling, naming, and validation live in Rust.
/// Swift only discovers the packaged client ID and stores the token in Keychain.
struct GitHubService: Sendable {
    private static let keychainService = "com.fsuserstories.app.github"
    private static let keychainAccount = "oauth-token"

    private let clientID: String

    init(clientID: String? = nil) {
        let configuredID = clientID
            ?? ProcessInfo.processInfo.environment["FS_GITHUB_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "FSGitHubOAuthClientID") as? String
            ?? Self.bundledClientID()
            ?? ""
        self.clientID = configuredID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !clientID.isEmpty && clientID != "YOUR_GITHUB_OAUTH_CLIENT_ID"
    }

    func beginAuthorization() async throws -> GitHubDeviceAuthorization {
        let clientID = clientID
        return try await Task.detached {
            try Self.decode(
                try RustCoreClient().execute([
                    "command": "github_begin_authorization",
                    "client_id": clientID
                ]),
                as: GitHubDeviceAuthorization.self
            )
        }.value
    }

    func finishAuthorization(_ authorization: GitHubDeviceAuthorization) async throws -> String {
        let clientID = clientID
        let token = try await Task.detached {
            let encodedAuthorization = try Self.encode(authorization)
            let result = try RustCoreClient().execute([
                "command": "github_finish_authorization",
                "client_id": clientID,
                "authorization": encodedAuthorization
            ])
            guard let token = result["accessToken"] as? String else {
                throw RustCoreError.invalidResponse
            }
            return token
        }.value
        // Ad-hoc development builds may lack the Keychain entitlement. The
        // caller also retains the token in memory for the current process.
        try? storeToken(token)
        return token
    }

    func createPrivateRepository(name: String, token: String) async throws -> GitHubRepository {
        try await Task.detached {
            try Self.decode(
                try RustCoreClient().execute([
                    "command": "github_create_private_repository",
                    "name": name,
                    "access_token": token
                ]),
                as: GitHubRepository.self
            )
        }.value
    }

    func inviteCollaborator(
        username: String,
        repositoryURL: String,
        token: String
    ) async throws {
        try await Task.detached {
            _ = try RustCoreClient().execute([
                "command": "github_invite_collaborator",
                "username": username,
                "repository_url": repositoryURL,
                "access_token": token
            ])
        }.value
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

    private static func bundledClientID() -> String? {
        guard let url = AppResources.bundle.url(forResource: "GitHub", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return object["OAuthClientID"] as? String
    }

    private static var baseTokenQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
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

    private static func encode<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private static func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
}
