import Combine
import OSLog
import Security
import SwiftUI

typealias FromKeychain = KeychainStorage
typealias KeychainKeys = KeychainKey

@MainActor
@propertyWrapper
struct KeychainStorage: DynamicProperty {
    @ObservedObject private var observable: KeychainValue

    init(wrappedValue: String = "", _ key: KeychainKey) {
        if let storedValue = KeychainValueStore.values[key] {
            observable = storedValue
        } else {
            let storedValue = KeychainValue(key: key)
            KeychainValueStore.values[key] = storedValue
            observable = storedValue
        }
    }

    var wrappedValue: String {
        get { observable.value }
        nonmutating set { observable.value = newValue }
    }

    var projectedValue: Binding<String> { $observable.value }
}

struct KeychainKey: Hashable, Sendable {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}

@MainActor
private final class KeychainValue: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.nezdemkovski.prharbor",
        category: "Keychain"
    )

    let key: KeychainKey

    private var cachedValue: String?

    init(key: KeychainKey) {
        self.key = key
    }

    var value: String {
        get {
            if let cachedValue {
                return cachedValue
            }

            do {
                let value = try KeychainClient.shared.read(key)
                cachedValue = value
                return value
            } catch {
                Self.logger.error(
                    "Read failed for \(self.key.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                cachedValue = ""
                return ""
            }
        }
        set {
            guard newValue != cachedValue else { return }

            do {
                try KeychainClient.shared.write(newValue, for: key)
                cachedValue = newValue
                objectWillChange.send()
            } catch {
                Self.logger.error(
                    "Write failed for \(self.key.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

private struct KeychainClient: Sendable {
    static let shared = KeychainClient(
        service: Bundle.main.bundleIdentifier ?? "com.nezdemkovski.prharbor"
    )

    let service: String

    func read(_ key: KeychainKey) throws -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(for: key, returningData: true) as CFDictionary,
            &result
        )

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return ""
        default:
            throw KeychainError.security(status)
        }
    }

    func write(_ value: String, for key: KeychainKey) throws {
        if value.isEmpty {
            let status = SecItemDelete(query(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.security(status)
            }
            return
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            query(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query(for: key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.security(addStatus)
            }
        default:
            throw KeychainError.security(updateStatus)
        }
    }

    private func query(for key: KeychainKey, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.name
        ]

        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }

        return query
    }
}

private enum KeychainError: LocalizedError {
    case invalidData
    case security(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "The stored Keychain value is not valid UTF-8."
        case .security(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        }
    }
}

@MainActor
private enum KeychainValueStore {
    static var values: [KeychainKey: KeychainValue] = [:]
}
