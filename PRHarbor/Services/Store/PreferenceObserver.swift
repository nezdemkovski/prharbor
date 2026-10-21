import Defaults
import Foundation

/// Runs actions when preferences change, for as long as the observer lives.
@MainActor
final class PreferenceObserver {
    private var observations: [Defaults.Observation] = []

    /// Preference changes made in the UI arrive on the main thread and are handled in the same
    /// turn, so the panel never draws a frame with the previous projection.
    func onChange<T: Defaults.Serializable & Equatable>(of key: Defaults.Key<T>, _ action: @escaping @MainActor () -> Void) {
        observations.append(
            Defaults.observe(key) { change in
                guard change.oldValue != change.newValue else { return }
                if Thread.isMainThread {
                    MainActor.assumeIsolated { action() }
                } else {
                    Task { @MainActor in action() }
                }
            })
    }

    func onChange<T: Defaults.Serializable & Equatable>(of keys: [Defaults.Key<T>], _ action: @escaping @MainActor () -> Void) {
        for key in keys { onChange(of: key, action) }
    }
}
