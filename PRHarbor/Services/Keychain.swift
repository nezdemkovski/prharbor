import SwiftUI
import Defaults
import KeychainAccess

typealias FromKeychain = KeychainStorage
typealias KeychainKeys = KeychainAccessKey

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
    private var currentValue = ""
    private var hasLoadedValue = false

    init(_ key: KeychainAccessKey) {
        self.key = key
    }

    var value: String {
        get {
            if !hasLoadedValue {
                currentValue = (try? appKeychain.get(key.keyName)) ?? ""
                hasLoadedValue = true
            }
            return currentValue
        }
        set {
            objectWillChange.send()
            currentValue = newValue
            hasLoadedValue = true
            do {
                if newValue.isEmpty {
                    try appKeychain.remove(key.keyName)
                } else {
                    try appKeychain.set(newValue, key: key.keyName)
                }
            } catch {
                print("Keychain write failed for key \(key.keyName): \(error)")
            }
        }
    }
}

struct KeychainAccessKey: Hashable, Sendable {
    let keyName: String
    init(key: String) { self.keyName = key }
}

@MainActor
private let appKeychain = Keychain(service: Bundle.main.bundleIdentifier ?? "com.nezdemkovski.prharbor")

@MainActor
private struct ObservablesStore {
    static var store: [KeychainAccessKey: ObservableString] = [:]
}
