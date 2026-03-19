import SwiftUI
import Security
import Defaults

typealias FromKeychain = KeychainStorage
typealias KeychainKeys = KeychainAccessKey

private enum NativeKeychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.nezdemkovski.prharbor"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@propertyWrapper
struct KeychainStorage: DynamicProperty {
    private let key: KeychainAccessKey
    @ObservedObject private var observable: ObservableString

    init(wrappedValue: String = "", _ key: KeychainAccessKey) {
        self.key = key
        let presentObservable: ObservableString? = ObservablesStore.store[key]
        if let presentObservable {
            self.observable = presentObservable
        } else {
            let newObservable = ObservableString(key)
            ObservablesStore.store[key] = newObservable
            self.observable = newObservable
        }
    }

    var wrappedValue: String {
        get { observable.value }
        nonmutating set { observable.value = newValue }
    }

    var projectedValue: Binding<String> { $observable.value }
}

@MainActor
private class ObservableString: ObservableObject {
    let key: KeychainAccessKey
    var currentValue: String? = nil

    init(_ key: KeychainAccessKey) {
        self.key = key
    }

    var value: String {
        get {
            if currentValue == nil {
                currentValue = NativeKeychain.get(key.keyName) ?? ""
            }
            return currentValue!
        }
        set {
            objectWillChange.send()
            currentValue = newValue
            if newValue.isEmpty {
                NativeKeychain.delete(key.keyName)
            } else {
                NativeKeychain.set(newValue, key: key.keyName)
            }
        }
    }
}

struct KeychainAccessKey: Hashable, Sendable {
    let keyName: String
    init(key: String) { self.keyName = key }
}

@MainActor
private struct ObservablesStore {
    static var store: [KeychainAccessKey: ObservableString] = [:]
}
