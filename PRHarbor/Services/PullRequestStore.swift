
import Foundation
import Defaults
import Observation
import os

private nonisolated enum PullCategory: CaseIterable, Sendable { case assigned, created, requested }
private nonisolated struct PullCategoryResult: Sendable {
    let category: PullCategory
    let result: Result<[Edge], Error>
}

/// The identity a refresh started with. Any newer refresh, account or query scope supersedes it.
private nonisolated struct RefreshToken: Sendable {
    let generation: Int
    let sessionGeneration: Int
    let scope: PullSnapshotScope
}

@MainActor @Observable
final class PullRequestStore {

    var assignedPulls: [Edge] = []
    var createdPulls: [Edge] = []
    var reviewRequestedPulls: [Edge] = []
    var isLoading = false
    var error: String?
    var lastSyncedAt: Date?
    private(set) var isShowingCache = false
    private(set) var hasIncompleteData = false
    /// Every fetched PR projected once, for the menu bar count, notifications and the panel.
    private(set) var timelineItems: [TimelineItem] = []
    /// The time `timelineItems` describes; ages and the panel axis share it.
    private(set) var now = Date.now
    private(set) var totalCount = 0

    /// Re-projects items each minute, so ages and quiet periods advance between refreshes.
    private var minuteTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var settingsRefreshTask: Task<Void, Never>?
    private var refreshRateObservation: Defaults.Observation?
    private var counterTypeObservation: Defaults.Observation?
    private var settingsObservations: [Defaults.Observation] = []
    private var sessionObservation: Task<Void, Never>?
    private let notifications = PullNotificationCoordinator()
    private var refreshGeneration = 0
    private let session: GitHubSession
    private let cache: PullSnapshotCache
    private let clientProvider: (String, BuildType) async throws -> GitHubClient
    private var cacheWriteTask: Task<Void, Never>?
    private var cacheRemovalTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var currentSnapshot: PullSnapshot?

    init(startAutomatically: Bool = true, session: GitHubSession? = nil,
         cache: PullSnapshotCache = .shared,
         clientProvider: ((String, BuildType) async throws -> GitHubClient)? = nil) {
        let session = session ?? GitHubSession.shared
        self.session = session
        self.cache = cache
        self.clientProvider = clientProvider ?? { try await session.client(baseURL: $0, buildType: $1) }
        guard startAutomatically else { return }
        startWithCache()
        observeRefreshRate()
        observeCounterType()
        observeDataSettings()
        sessionObservation = Task { [weak self, session] in
            var previous = session.connection
            // Work already started for the old account is rejected by the session generation,
            // which changes synchronously; this restarts loading for the new identity.
            for await connection in Observations({ session.connection }) where connection != previous {
                previous = connection
                self?.clear()
                self?.startWithCache()
            }
        }
    }

    isolated deinit {
        refreshTimer?.invalidate()
        minuteTimer?.invalidate()
        refreshTask?.cancel()
        startupTask?.cancel()
        settingsRefreshTask?.cancel()
        sessionObservation?.cancel()
    }

    private var currentCount: Int {
        switch Defaults[.counterType] {
        case .rotting:
            timelineItems.filter { $0.hasKnownQuietPeriod && $0.freshness == .rotting && $0.snoozedUntil == nil }.count
        case .waitingOnYou:
            TimelineNotificationPolicy.waitingForReview(timelineItems).count
        case .assigned: assignedPulls.count
        case .created: createdPulls.count
        case .reviewRequested: reviewRequestedPulls.count
        case .none: 0
        }
    }

    var isEmpty: Bool {
        assignedPulls.isEmpty && createdPulls.isEmpty && reviewRequestedPulls.isEmpty
    }

    var isConfigured: Bool {
        session.isConfigured
    }

    func clear() {
        startupTask?.cancel()
        startupTask = nil
        cacheWriteTask?.cancel()
        let scope = currentSnapshot?.scope ?? snapshotScope
        let cache = cache
        let previousWrite = cacheWriteTask
        let previousRemoval = cacheRemovalTask
        cacheRemovalTask = Task {
            await previousWrite?.value
            await previousRemoval?.value
            await cache.remove(scope: scope)
        }
        currentSnapshot = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        assignedPulls = []
        createdPulls = []
        reviewRequestedPulls = []
        isLoading = false
        error = nil
        lastSyncedAt = nil
        isShowingCache = false
        hasIncompleteData = false
        notifications.reset()
        rebuildTimelineItems()
        minuteTimer?.invalidate()
        minuteTimer = nil
    }
    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = Double(max(1, Defaults[.refreshRate])) * 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(respectFreshness: true)
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        if let snapshot = currentSnapshot, snapshot.scope == snapshotScope {
            timer.fireDate = max(.now, snapshot.syncedAt.addingTimeInterval(interval))
        }
        refresh(respectFreshness: true)
    }

    private func observeRefreshRate() {
        refreshRateObservation = Defaults.observe(.refreshRate) { [weak self] change in
            guard change.oldValue != change.newValue else { return }
            Task { @MainActor in
                self?.startAutoRefresh()
            }
        }
    }

    private func observeCounterType() {
        counterTypeObservation = Defaults.observe(.counterType) { [weak self] change in
            guard change.oldValue != change.newValue else { return }
            Task { @MainActor in
                self?.rebuildTimelineItems()
                self?.scheduleSettingsRefresh()
            }
        }
    }

    private func observeDataSettings() {
        func watch<T: Defaults.Serializable & Equatable>(_ key: Defaults.Key<T>) {
            settingsObservations.append(
                Defaults.observe(key) { [weak self] change in
                    guard change.oldValue != change.newValue else { return }
                    Task { @MainActor in self?.scheduleSettingsRefresh() }
                }
            )
        }
        watch(.showAssigned)
        watch(.showCreated)
        watch(.showRequested)
        watch(.buildType)
        watch(.hideDrafts)
        watch(.notifyReviewRequested)
        watch(.notifyAssigned)
        watch(.notifyCreated)
        watch(.notifyRotting)
        watch(.morningSummary)
        watch(.githubApiBaseUrl)
        // These change presentation and counters, never the GitHub query.
        func watchLocal<T: Defaults.Serializable & Equatable>(_ key: Defaults.Key<T>) {
            settingsObservations.append(Defaults.observe(key) { [weak self] change in
                guard change.oldValue != change.newValue else { return }
                Task { @MainActor in self?.rebuildTimelineItems() }
            })
        }
        watchLocal(.morningSummaryMinutes)
        watchLocal(.freshnessThresholds)
        watchLocal(.ownCommentsCount)
        watchLocal(.botAccounts)
        watchLocal(.snoozedPulls)
    }

    private func scheduleSettingsRefresh() {
        settingsRefreshTask?.cancel()
        settingsRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            settingsRefreshTask = nil
            refresh(force: currentSnapshot?.scope != snapshotScope, respectFreshness: true)
        }
    }

    var snapshotScope: PullSnapshotScope {
        let username = session.connection?.username ?? ""
        let showAssigned = Defaults[.showAssigned]
        let showCreated = Defaults[.showCreated]
        let showRequested = Defaults[.showRequested]
        let counterType = Defaults[.counterType]
        let fetchAssigned = showAssigned
            || Defaults[.notifyAssigned]
            || counterType == .assigned
        let fetchCreated = showCreated
            || Defaults[.notifyRotting]
            || Defaults[.morningSummary]
            || counterType == .rotting
            || Defaults[.notifyCreated]
            || counterType == .created
        let fetchRequested = showRequested
            || Defaults[.morningSummary]
            || counterType == .waitingOnYou
            || counterType == .rotting
            || Defaults[.notifyReviewRequested]
            || counterType == .reviewRequested
        return PullSnapshotScope(username: username, baseURL: Defaults[.githubApiBaseUrl],
                                 buildType: Defaults[.buildType], hideDrafts: Defaults[.hideDrafts],
                                 assigned: fetchAssigned, created: fetchCreated, requested: fetchRequested)
    }

    private func currentToken() -> RefreshToken {
        RefreshToken(generation: refreshGeneration, sessionGeneration: session.generation, scope: snapshotScope)
    }

    private func isCurrent(_ token: RefreshToken) -> Bool {
        token.generation == refreshGeneration && token.sessionGeneration == session.generation && token.scope == snapshotScope
    }

    private func startWithCache() {
        startupTask?.cancel()
        if isConfigured && lastSyncedAt == nil { isLoading = true }
        startupTask = Task { [weak self] in
            guard let self else { return }
            await loadCachedSnapshot()
            guard !Task.isCancelled else { return }
            isLoading = false
            startAutoRefresh()
            startupTask = nil
        }
    }

    func loadCachedSnapshot() async {
        guard isConfigured else { return }
        let token = currentToken()
        await cacheRemovalTask?.value
        let snapshot = await cache.load(scope: token.scope)
        guard !Task.isCancelled, isCurrent(token), isConfigured, lastSyncedAt == nil, let snapshot else { return }
        currentSnapshot = snapshot
        assignedPulls = snapshot.assigned
        createdPulls = snapshot.created
        reviewRequestedPulls = snapshot.requested
        lastSyncedAt = snapshot.syncedAt
        isShowingCache = true
        hasIncompleteData = !snapshot.isComplete
        rebuildTimelineItems()
        startMinuteTimer()
        // Restoration never sends notifications or wakes snoozed PRs from old history.
    }

    func refresh(force: Bool = false, respectFreshness: Bool = false) {
        if respectFreshness, error == nil, let snapshot = currentSnapshot,
           snapshot.scope == snapshotScope,
           snapshot.isFresh(at: .now, interval: Double(max(1, Defaults[.refreshRate])) * 60) { return }
        guard !isLoading || force else { return }
        guard isConfigured else {
            refreshTask?.cancel()
            refreshTask = nil
            minuteTimer?.invalidate()
            minuteTimer = nil
            isLoading = false
            error = nil
            return
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let token = currentToken()
        let generation = token.generation
        isLoading = true
        error = nil
        let scope = token.scope
        let username = scope.username
        let fetchAssigned = scope.assigned
        let fetchCreated = scope.created
        let fetchRequested = scope.requested
        let hideDrafts = scope.hideDrafts
        let baseURL = scope.baseURL
        let buildType = scope.buildType
        let started = ContinuousClock.now
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { syncLog.notice("Sync finished in \(started.duration(to: .now), privacy: .public)") }
            do {
                let client = try await clientProvider(baseURL, buildType)
                try Task.checkCancellation()
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                let showProgressively = lastSyncedAt == nil && isEmpty
                var a = assignedPulls, c = createdPulls, r = reviewRequestedPulls
                var firstError: Error?
                await withTaskGroup(of: PullCategoryResult.self) { group in
                    for category in PullCategory.allCases {
                        group.addTask {
                            let enabled: Bool
                            let filter: String
                            switch category {
                            case .assigned: enabled = fetchAssigned; filter = "assignee:\(username)"
                            case .created: enabled = fetchCreated; filter = "author:\(username)"
                            case .requested: enabled = fetchRequested; filter = "review-requested:\(username)"
                            }
                            do {
                                let edges = enabled ? try await client.fetchPulls(filter: filter) : []
                                return PullCategoryResult(category: category, result: .success(edges))
                            } catch { return PullCategoryResult(category: category, result: .failure(error)) }
                        }
                    }
                    for await result in group {
                        guard isCurrent(token), !Task.isCancelled else { continue }
                        switch result.result {
                        case .success(let edges):
                            let edges = hideDrafts ? edges.filter { !$0.node.isDraft } : edges
                            switch result.category {
                            case .assigned: a = edges
                            case .created: c = edges
                            case .requested: r = edges
                            }
                            if showProgressively {
                                publishPulls(assigned: a, created: c, requested: r)
                                if !isEmpty {
                                    // Even quitting before the slowest category finishes
                                    // leaves useful data for the next launch.
                                    var partial = PullSnapshot(scope: scope, syncedAt: .now, assigned: a, created: c, requested: r)
                                    partial.isComplete = false
                                    currentSnapshot = partial
                                    hasIncompleteData = true
                                    _ = persist(partial)
                                }
                            }
                        case .failure(let error):
                            if firstError == nil { firstError = error }
                        }
                    }
                }
                try Task.checkCancellation()
                if let firstError { throw firstError }

                let snapshot = PullSnapshot(scope: scope, syncedAt: .now, assigned: a, created: c, requested: r)
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                currentSnapshot = snapshot
                var fetched: PullSources = []
                if fetchAssigned { fetched.insert(.assigned) }
                if fetchCreated { fetched.insert(.created) }
                if fetchRequested { fetched.insert(.requested) }
                self.finishRefresh(generation: generation, assigned: a, created: c, requested: r, fetched: fetched)
                await persist(snapshot).value
            } catch is CancellationError {
                self.finishCancelledRefresh(generation: generation)
            } catch {
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                self.finishFailedRefresh(error, generation: generation)
            }
        }
    }

    func rebaseStack(_ stack: PullRequestStack) async throws -> StackRebaseResult {
        let scope = snapshotScope
        let sessionGeneration = session.generation
        var mutationStarted = false
        // Supersede any response started before the mutation. A cancelled stack
        // can also have completed layers, so conservatively revalidate it.
        defer {
            if mutationStarted, scope == snapshotScope, sessionGeneration == session.generation, isConfigured {
                refresh(force: true)
            }
        }
        do {
            let client = try await clientProvider(scope.baseURL, scope.buildType)
            try Task.checkCancellation()
            guard scope == snapshotScope, sessionGeneration == session.generation, isConfigured else { throw CancellationError() }
            mutationStarted = true
            let result = try await client.rebaseStack(stack)
            guard scope == snapshotScope, sessionGeneration == session.generation, isConfigured else { throw CancellationError() }
            return result
        } catch {
            if let accessError = error as? GitHubAccessError, accessError == .accountChanged,
               scope == snapshotScope, sessionGeneration == session.generation {
                mutationStarted = false
                clear()
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    private func startMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildTimelineItems() }
        }
    }

    private func finishRefresh(generation: Int, assigned: [Edge], created: [Edge], requested: [Edge], fetched: PullSources) {
        guard generation == refreshGeneration else { return }
        lastSyncedAt = currentSnapshot?.syncedAt ?? .now
        isShowingCache = false
        hasIncompleteData = false
        reconcileSnoozes(assigned + created + requested)
        publishPulls(assigned: assigned, created: created, requested: requested)
        notifications.refreshed(assigned: assigned, created: created, requested: requested,
                                fetched: fetched, items: timelineItems)
        startMinuteTimer()
        // Schedule from completion, so a slow request cannot make the next tick
        // fall just before freshness expires and accidentally skip a whole interval.
        refreshTimer?.fireDate = (lastSyncedAt ?? .now).addingTimeInterval(Double(max(1, Defaults[.refreshRate])) * 60)
        isLoading = false
        refreshTask = nil
    }

    private func persist(_ snapshot: PullSnapshot) -> Task<Void, Never> {
        let cache = cache
        let previousWrite = cacheWriteTask
        let previousRemoval = cacheRemovalTask
        let task = Task {
            await previousWrite?.value
            await previousRemoval?.value
            guard !Task.isCancelled else { return }
            await cache.save(snapshot)
        }
        cacheWriteTask = task
        return task
    }

    private func publishPulls(assigned: [Edge], created: [Edge], requested: [Edge]) {
        let changed = assignedPulls != assigned || createdPulls != created || reviewRequestedPulls != requested
        if assignedPulls != assigned { assignedPulls = assigned }
        if createdPulls != created { createdPulls = created }
        if reviewRequestedPulls != requested { reviewRequestedPulls = requested }
        if changed { rebuildTimelineItems() }
    }

    private func rebuildTimelineItems() {
        now = .now
        timelineItems = timelineInput(now: now).makeItems()
        let count = currentCount
        if totalCount != count { totalCount = count }
    }

    func timelineInput(now: Date = .now, thresholds: [Int]? = nil, bots: [String]? = nil,
                       ownComments: Bool? = nil, snoozed: [String: Double]? = nil,
                       includeAssigned: Bool = true, includeCreated: Bool = true,
                       includeRequested: Bool = true, username: String? = nil) -> TimelineInput {
        TimelineInput(assigned: assignedPulls, created: createdPulls, requested: reviewRequestedPulls,
                      includeAssigned: includeAssigned, includeCreated: includeCreated, includeRequested: includeRequested,
                      username: username ?? session.connection?.username ?? "", now: now,
                      thresholds: thresholds ?? Defaults[.freshnessThresholds], bots: bots ?? Defaults[.botAccounts],
                      ownComments: ownComments ?? Defaults[.ownCommentsCount], snoozed: snoozed ?? Defaults[.snoozedPulls])
    }

    private func reconcileSnoozes(_ edges: [Edge]) {
        let (snoozed, activity) = TimelineSnoozePolicy.reconcile(edges: edges, snoozed: Defaults[.snoozedPulls],
            activity: Defaults[.snoozeActivity], now: .now, wakeOnComment: Defaults[.wakeOnComment],
            username: session.connection?.username ?? "")
        if Defaults[.snoozedPulls] != snoozed { Defaults[.snoozedPulls] = snoozed }
        if Defaults[.snoozeActivity] != activity { Defaults[.snoozeActivity] = activity }
    }

    private func finishFailedRefresh(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }
        if let accessError = error as? GitHubAccessError, accessError == .accountChanged {
            clear()
        }
        self.error = error.localizedDescription
        isLoading = false
        refreshTask = nil
    }

    private func finishCancelledRefresh(generation: Int) {
        guard generation == refreshGeneration else { return }
        isLoading = false
        refreshTask = nil
    }
}
