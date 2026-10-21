import Defaults
import Foundation
import Observation
import os

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

    let session: GitHubSession
    private let clientProvider: (String, BuildType) async throws -> GitHubClient
    private let settings: () -> PullRequestSettings
    private let storage: SnapshotStorage
    private let schedule = RefreshSchedule()
    private let preferences = PreferenceObserver()
    private let notifications = PullNotificationCoordinator()
    private var currentSnapshot: PullSnapshot?
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var settingsRefreshTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var sessionObservation: Task<Void, Never>?

    init(
        startAutomatically: Bool = true, session: GitHubSession? = nil,
        cache: PullSnapshotCache = .temporary(),
        clientProvider: ((String, BuildType) async throws -> GitHubClient)? = nil,
        settings: @escaping () -> PullRequestSettings = { .saved }
    ) {
        let session = session ?? GitHubSession()
        self.session = session
        self.storage = SnapshotStorage(cache: cache)
        self.settings = settings
        self.clientProvider = clientProvider ?? { try await session.client(baseURL: $0, buildType: $1) }
        guard startAutomatically else { return }
        startWithCache()
        observePreferences()
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
        schedule.invalidate()
        refreshTask?.cancel()
        startupTask?.cancel()
        settingsRefreshTask?.cancel()
        sessionObservation?.cancel()
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
        storage.remove(scope: currentSnapshot?.scope ?? snapshotScope)
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
        schedule.stopTicking()
    }

    private func startAutoRefresh() {
        let lastSync = currentSnapshot.flatMap { $0.scope == snapshotScope ? $0.syncedAt : nil }
        schedule.refresh(every: settings().refreshInterval, lastSync: lastSync) { [weak self] in
            self?.refresh(respectFreshness: true)
        }
        refresh(respectFreshness: true)
    }

    private func observePreferences() {
        let refetch: @MainActor () -> Void = { [weak self] in self?.scheduleSettingsRefresh() }
        let reproject: @MainActor () -> Void = { [weak self] in self?.rebuildTimelineItems() }
        preferences.onChange(of: .refreshRate) { [weak self] in self?.startAutoRefresh() }
        preferences.onChange(of: .counterType) {
            reproject()
            refetch()
        }
        // These change what is fetched or notified.
        preferences.onChange(
            of: [
                .showAssigned, .showCreated, .showRequested, .hideDrafts, .notifyReviewRequested,
                .notifyAssigned, .notifyCreated, .notifyRotting, .morningSummary
            ], refetch)
        preferences.onChange(of: .buildType, refetch)
        preferences.onChange(of: .githubApiBaseUrl, refetch)
        // These change presentation and counters, never the GitHub query.
        preferences.onChange(of: .morningSummaryMinutes, reproject)
        preferences.onChange(of: .freshnessThresholds, reproject)
        preferences.onChange(of: .ownCommentsCount, reproject)
        preferences.onChange(of: .botAccounts, reproject)
        preferences.onChange(of: .snoozedPulls, reproject)
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
        let snapshot = await storage.load(scope: token.scope)
        guard !Task.isCancelled, isCurrent(token), isConfigured, lastSyncedAt == nil, let snapshot else { return }
        currentSnapshot = snapshot
        assignedPulls = snapshot.assigned
        createdPulls = snapshot.created
        reviewRequestedPulls = snapshot.requested
        lastSyncedAt = snapshot.syncedAt
        isShowingCache = true
        hasIncompleteData = !snapshot.isComplete
        rebuildTimelineItems()
        startMinuteTicks()
        // Restoration never sends notifications or wakes snoozed PRs from old history.
    }

    func refresh(force: Bool = false, respectFreshness: Bool = false) {
        if respectFreshness, error == nil, let snapshot = currentSnapshot,
            snapshot.scope == snapshotScope,
            snapshot.isFresh(at: .now, interval: settings().refreshInterval)
        {
            return
        }
        guard !isLoading || force else { return }
        guard isConfigured else {
            refreshTask?.cancel()
            refreshTask = nil
            schedule.stopTicking()
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
        // Pull requests already on screen for the same account, host and check mode keep
        // their details unless the search reports a change; only the rest are fetched in full.
        let reusable =
            currentSnapshot.map {
                $0.scope.username == scope.username && $0.scope.baseURL == scope.baseURL && $0.scope.buildType == scope.buildType
            } ?? false
        let known =
            reusable
            ? Dictionary(
                (assignedPulls + createdPulls + reviewRequestedPulls).map { ($0.node.url, $0.node) },
                uniquingKeysWith: { first, _ in first }) : [:]
        let started = ContinuousClock.now
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { syncLog.notice("Sync finished in \(started.duration(to: .now), privacy: .public)") }
            do {
                let client = try await clientProvider(scope.baseURL, scope.buildType)
                try Task.checkCancellation()
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                let showProgressively = lastSyncedAt == nil && isEmpty
                var a = assignedPulls
                var c = createdPulls
                var r = reviewRequestedPulls
                var firstError: Error?
                for await result in PullSearch.run(client: client, scope: scope, known: known) {
                    guard isCurrent(token), !Task.isCancelled else { continue }
                    switch result.edges {
                    case .success(let edges):
                        switch result.search {
                        case .assigned: a = edges
                        case .created: c = edges
                        case .requested: r = edges
                        }
                        if showProgressively { publishPartial(scope: scope, assigned: a, created: c, requested: r) }
                    case .failure(let error):
                        if firstError == nil { firstError = error }
                    }
                }
                try Task.checkCancellation()
                if let firstError { throw firstError }

                let snapshot = PullSnapshot(scope: scope, syncedAt: .now, assigned: a, created: c, requested: r)
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                currentSnapshot = snapshot
                let fetched = PullSources(PullSearch.allCases.filter { $0.isEnabled(in: scope) }.map(\.source))
                finishRefresh(generation: generation, assigned: a, created: c, requested: r, fetched: fetched)
                await storage.save(snapshot).value
            } catch is CancellationError {
                finishCancelledRefresh(generation: generation)
            } catch {
                guard isCurrent(token) else { return finishCancelledRefresh(generation: generation) }
                finishFailedRefresh(error, generation: generation)
            }
        }
    }

    /// Shows each search as it arrives on the first load, and saves the partial result, so even
    /// quitting before the slowest search finishes leaves useful data for the next launch.
    private func publishPartial(scope: PullSnapshotScope, assigned: [Edge], created: [Edge], requested: [Edge]) {
        publishPulls(assigned: assigned, created: created, requested: requested)
        guard !isEmpty else { return }
        var partial = PullSnapshot(scope: scope, syncedAt: .now, assigned: assigned, created: created, requested: requested)
        partial.isComplete = false
        currentSnapshot = partial
        hasIncompleteData = true
        storage.save(partial)
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
                scope == snapshotScope, sessionGeneration == session.generation
            {
                mutationStarted = false
                clear()
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    /// Re-projects items each minute, so ages and quiet periods advance between refreshes.
    private func startMinuteTicks() {
        schedule.tickEveryMinute { [weak self] in self?.rebuildTimelineItems() }
    }

    private func finishRefresh(generation: Int, assigned: [Edge], created: [Edge], requested: [Edge], fetched: PullSources) {
        guard generation == refreshGeneration else { return }
        lastSyncedAt = currentSnapshot?.syncedAt ?? .now
        isShowingCache = false
        hasIncompleteData = false
        reconcileSnoozes(assigned + created + requested)
        publishPulls(assigned: assigned, created: created, requested: requested)
        if let day = notifications.refreshed(
            assigned: assigned, created: created, requested: requested,
            fetched: fetched, items: timelineItems, settings: settings())
        {
            Defaults[.lastMorningSummary] = day
        }
        startMinuteTicks()
        schedule.nextRefresh(at: (lastSyncedAt ?? .now).addingTimeInterval(settings().refreshInterval))
        isLoading = false
        refreshTask = nil
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
        let count = settings().counterType.count(
            items: timelineItems, assigned: assignedPulls.count,
            created: createdPulls.count, requested: reviewRequestedPulls.count)
        if totalCount != count { totalCount = count }
    }

    func timelineInput(
        now: Date = .now, thresholds: [Int]? = nil, bots: [String]? = nil,
        ownComments: Bool? = nil, snoozed: [String: Double]? = nil,
        includeAssigned: Bool = true, includeCreated: Bool = true,
        includeRequested: Bool = true, username: String? = nil
    ) -> TimelineInput {
        let settings = settings()
        return TimelineInput(
            assigned: assignedPulls, created: createdPulls, requested: reviewRequestedPulls,
            includeAssigned: includeAssigned, includeCreated: includeCreated, includeRequested: includeRequested,
            username: username ?? session.connection?.username ?? "", now: now,
            thresholds: thresholds ?? settings.thresholds, bots: bots ?? settings.bots,
            ownComments: ownComments ?? settings.ownComments, snoozed: snoozed ?? settings.snoozed)
    }

    private func reconcileSnoozes(_ edges: [Edge]) {
        let settings = settings()
        let (snoozed, activity) = TimelineSnoozePolicy.reconcile(
            edges: edges, snoozed: settings.snoozed,
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
