import Foundation

/// The store's two clocks: the refresh interval, and a minute tick that advances ages
/// between refreshes.
@MainActor
final class RefreshSchedule {
    private var refreshTimer: Timer?
    private var minuteTimer: Timer?

    /// Refreshes every `interval`. The first tick waits until `lastSync` plus the interval.
    func refresh(every interval: TimeInterval, lastSync: Date?, _ action: @escaping @MainActor () -> Void) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        if let lastSync { timer.fireDate = max(.now, lastSync.addingTimeInterval(interval)) }
    }

    /// Schedules from a completed refresh, so a slow request cannot make the next tick fall
    /// just before freshness expires and skip a whole interval.
    func nextRefresh(at date: Date) {
        refreshTimer?.fireDate = date
    }

    func tickEveryMinute(_ action: @escaping @MainActor () -> Void) {
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in action() }
        }
    }

    func stopTicking() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    func invalidate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopTicking()
    }
}
