
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
    let session: GitHubSession
    private let cache: PullSnapshotCache
    private let clientProvider: (String, BuildType) async throws -> GitHubClient
    private let settings: () -> PullRequestSettings
    private var cacheWriteTask: Task<Void, Never>?
    private var cacheRemovalTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var currentSnapshot: PullSnapshot?

    init(startAutomatically: Bool = true, session: GitHubSession? = nil,
         cache: PullSnapshotCache = .temporary(),
         clientProvider: ((String, BuildType) async throws -> GitHubClient)? = nil,
         settings: @escaping () -> PullRequestSettings = { .saved }) {
        let session = session ?? GitHubSession()
        self.session = session
        self.cache = cache
        self.settings = settings
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
        switch settings().counterType {
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
        let interval = settings().refreshInterval
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
        onChange(of: .refreshRate) { $0.startAutoRefresh() }
    }

    private func observeCounterType() {
        onChange(of: .counterType) {
            $0.rebuildTimelineItems()
            $0.scheduleSettingsRefresh()
        }
    }

    private func observeDataSettings() {
        for key in [Defaults.Key<Bool>.showAssigned, .showCreated, .showRequested, .hideDrafts, .notifyReviewRequested,
                    .notifyAssigned, .notifyCreated, .notifyRotting, .morningSummary] {
            onChange(of: key) { $0.scheduleSettingsRefresh() }
        }
        onChange(of: .buildType) { $0.scheduleSettingsRefresh() }
        onChange(of: .githubApiBaseUrl) { $0.scheduleSettingsRefresh() }
        // These change presentation and counters, never the GitHub query.
        onChange(of: .morningSummaryMinutes) { $0.rebuildTimelineItems() }
        onChange(of: .freshnessThresholds) { $0.rebuildTimelineItems() }
        onChange(of: .ownCommentsCount) { $0.rebuildTimelineItems() }
        onChange(of: .botAccounts) { $0.rebuildTimelineItems() }
        onChange(of: .snoozedPulls) { $0.rebuildTimelineItems() }
    }

    /// Preference changes made in the UI arrive on the main thread and are handled in the same
    /// turn, so the panel never draws a frame with the previous projection.
    private func onChange<T: Defaults.Serializable & Equatable>(of key: Defaults.Key<T>,
                                                               _ action: @escaping @MainActor (PullRequestStore) -> Void) {
        settingsObservations.append(Defaults.observe(key) { [weak self] change in
            guard change.oldValue != change.newValue else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self.map(action) }
            } else {
                Task { @MainActor in self.map(action) }
            }
        })
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
        settings().scope(username: session.connection?.username ?? "")
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
           snapshot.isFresh(at: .now, interval: settings().refreshInterval) { return }
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
        // Pull requests already on screen for the same account, host and check mode keep
        // their details unless the search reports a change; only the rest are fetched in full.
        let reusable = currentSnapshot.map {
            $0.scope.username == scope.username && $0.scope.baseURL == scope.baseURL && $0.scope.buildType == scope.buildType
        } ?? false
        let known = reusable ? Dictionary((assignedPulls + createdPulls + reviewRequestedPulls).map { ($0.node.url, $0.node) },
                                          uniquingKeysWith: { first, _ in first }) : [:]
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
                                let edges = enabled ? try await client.fetchPulls(filter: filter, known: known) : []
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
        if let day = notifications.refreshed(assigned: assigned, created: created, requested: requested,
                                             fetched: fetched, items: timelineItems, settings: settings()) {
            Defaults[.lastMorningSummary] = day
        }
        startMinuteTimer()
        // Schedule from completion, so a slow request cannot make the next tick
        // fall just before freshness expires and accidentally skip a whole interval.
        refreshTimer?.fireDate = (lastSyncedAt ?? .now).addingTimeInterval(settings().refreshInterval)
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
        let settings = settings()
        return TimelineInput(assigned: assignedPulls, created: createdPulls, requested: reviewRequestedPulls,
                      includeAssigned: includeAssigned, includeCreated: includeCreated, includeRequested: includeRequested,
                      username: username ?? session.connection?.username ?? "", now: now,
                      thresholds: thresholds ?? settings.thresholds, bots: bots ?? settings.bots,
                      ownComments: ownComments ?? settings.ownComments, snoozed: snoozed ?? settings.snoozed)
    }

    private func reconcileSnoozes(_ edges: [Edge]) {
        let settings = settings()
        let (snoozed, activity) = TimelineSnoozePolicy.reconcile(edges: edges, snoozed: settings.snoozed,
            activity: settings.snoozeActivity, now: .now, wakeOnComment: settings.wakeOnComment,
            username: session.connection?.username ?? "")
        // Waking a snoozed pull request is the store's only preference write besides the summary day.
        if settings.snoozed != snoozed { Defaults[.snoozedPulls] = snoozed }
        if settings.snoozeActivity != activity { Defaults[.snoozeActivity] = activity }
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
