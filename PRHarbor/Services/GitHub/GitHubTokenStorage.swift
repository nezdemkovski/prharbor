import Foundation
import Security
import Synchronization

/// Where tokens are kept: the login Keychain in the app, memory in tests.
nonisolated struct GitHubTokenStorage: Sendable {
    var read: @Sendable (_ apiBaseURL: String) throws -> String?
    var save: @Sendable (_ token: String, _ apiBaseURL: String) throws -> Void
    var delete: @Sendable (_ apiBaseURL: String) throws -> Void

    static let keychain = GitHubTokenStorage(
        read: { apiBaseURL in
            var query = keychainQuery(apiBaseURL)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw keychainError(status) }
            return String(data: data, encoding: .utf8)
        },
        save: { token, apiBaseURL in
            let query = keychainQuery(apiBaseURL)
            let attributes: [String: Any] = [
                kSecValueData as String: Data(token.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw keychainError(status) }
        },
        delete: { apiBaseURL in
            let status = SecItemDelete(keychainQuery(apiBaseURL) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
        })

    static func memory() -> GitHubTokenStorage {
        let tokens = TokenBox()
        return GitHubTokenStorage(read: { tokens[$0] }, save: { tokens[$1] = $0 }, delete: { tokens[$0] = nil })
    }

    private static func keychainQuery(_ apiBaseURL: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.nezdemkovski.prharbor",
            kSecAttrAccount as String: "personal-access-token " + apiBaseURL
        ]
    }

    private static func keychainError(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

private nonisolated final class TokenBox: Sendable {
    private let values = Mutex<[String: String]>([:])
    subscript(key: String) -> String? {
        get { values.withLock { $0[key] } }
        set { values.withLock { $0[key] = newValue } }
    }
}
