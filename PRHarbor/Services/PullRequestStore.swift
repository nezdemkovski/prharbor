
import Combine
import Foundation
import Defaults

nonisolated struct PullRefreshTracker: Sendable {
    private var knownURLs: Set<String> = []
    private var wasFetched = false

    mutating func update(edges: [Edge], fetched: Bool, canNotify: Bool) -> [Pull] {
        let newPulls: [Pull]
        if canNotify && fetched && wasFetched {
            newPulls = edges
                .filter { !knownURLs.contains($0.node.url.absoluteString) }
                .map(\.node)
        } else {
            newPulls = []
        }

        if fetched {
            knownURLs = Set(edges.map { $0.node.url.absoluteString })
        }
        wasFetched = fetched
        return newPulls
    }

    mutating func reset() {
        knownURLs = []
        wasFetched = false
    }
}

private nonisolated enum PullCategory: CaseIterable, Sendable { case assigned, created, requested }
private nonisolated struct PullCategoryResult: Sendable {
    let category: PullCategory
    let result: Result<[Edge], Error>
}

@MainActor
final class PullRequestStore: ObservableObject {

    @Published var assignedPulls: [Edge] = []
    @Published var createdPulls: [Edge] = []
    @Published var reviewRequestedPulls: [Edge] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastSyncedAt: Date?
    @Published private(set) var isShowingCache = false
    @Published private(set) var hasIncompleteData = false
    @Published var minutesUntilRefresh: Int = 0


    private var countdownTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var settingsRefreshTask: Task<Void, Never>?
    private var refreshRateObservation: Defaults.Observation?
    private var counterTypeObservation: Defaults.Observation?
    private var settingsObservations: [Defaults.Observation] = []
    private var sessionObservation: AnyCancellable?
    private var hasLoadedOnce = false
    private var knownRotting: Set<String>?
    private var previousThresholds: [Int]?
    private var cachedTimelineItems: [TimelineItem] = []
    private var refreshGeneration = 0
    private let session: GitHubSession
    private let cache: PullSnapshotCache
    private let clientProvider: (String, BuildType) async throws -> GitHubClient
    private var cacheWriteTask: Task<Void, Never>?
    private var cacheRemovalTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var currentSnapshot: PullSnapshot?


    private var reviewRequestedTracker = PullRefreshTracker()
    private var assignedTracker = PullRefreshTracker()
    private var createdTracker = PullRefreshTracker()

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
        sessionObservation = session.$cliConnection
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Published sends before the connection changes. Invalidate old work
                // synchronously, then read the new identity in the startup task.
                self?.clear()
                self?.startWithCache()
            }
    }

    isolated deinit {
        refreshTimer?.invalidate()
        countdownTimer?.invalidate()
        refreshTask?.cancel()
        startupTask?.cancel()
        settingsRefreshTask?.cancel()
    }

    var totalCount: Int {
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
        minutesUntilRefresh = 0
        lastSyncedAt = nil
        isShowingCache = false
        hasIncompleteData = false
        hasLoadedOnce = false
        knownRotting = nil
        previousThresholds = nil
        cachedTimelineItems = []
        reviewRequestedTracker.reset()
        assignedTracker.reset()
        createdTracker.reset()
        countdownTimer?.invalidate()
        countdownTimer = nil
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
                self?.objectWillChange.send()
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
                Task { @MainActor in
                    self?.rebuildTimelineItems()
                    self?.objectWillChange.send()
                }
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
        let username = session.cliConnection?.username ?? ""
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
        let scope = snapshotScope
        let sessionGeneration = session.generation
        let generation = refreshGeneration
        await cacheRemovalTask?.value
        let snapshot = await cache.load(scope: scope)
        guard !Task.isCancelled, generation == refreshGeneration, scope == snapshotScope,
              sessionGeneration == session.generation, isConfigured, lastSyncedAt == nil, let snapshot else { return }
        currentSnapshot = snapshot
        assignedPulls = snapshot.assigned
        createdPulls = snapshot.created
        reviewRequestedPulls = snapshot.requested
        lastSyncedAt = snapshot.syncedAt
        isShowingCache = true
        hasIncompleteData = !snapshot.isComplete
        rebuildTimelineItems()
        startCountdown()
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
            countdownTimer?.invalidate()
            countdownTimer = nil
            minutesUntilRefresh = 0
            isLoading = false
            error = nil
            return
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        error = nil
        let scope = snapshotScope
        let sessionGeneration = session.generation
        let username = scope.username
        let fetchAssigned = scope.assigned
        let fetchCreated = scope.created
        let fetchRequested = scope.requested
        let hideDrafts = scope.hideDrafts
        let baseURL = scope.baseURL
        let buildType = scope.buildType
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try await clientProvider(baseURL, buildType)
                try Task.checkCancellation()
                guard sessionGeneration == session.generation, scope == snapshotScope else { return finishCancelledRefresh(generation: generation) }
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
                        guard generation == refreshGeneration, sessionGeneration == session.generation,
                              scope == snapshotScope, !Task.isCancelled else { continue }
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
                guard generation == refreshGeneration, sessionGeneration == session.generation,
                      scope == snapshotScope else { return finishCancelledRefresh(generation: generation) }
                currentSnapshot = snapshot
                self.finishRefresh(
                    generation: generation,
                    assigned: a,
                    created: c,
                    requested: r,
                    fetchedAssigned: fetchAssigned,
                    fetchedCreated: fetchCreated,
                    fetchedRequested: fetchRequested
                )
                await persist(snapshot).value
            } catch is CancellationError {
                self.finishCancelledRefresh(generation: generation)
            } catch {
                guard sessionGeneration == session.generation, scope == snapshotScope else { return finishCancelledRefresh(generation: generation) }
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
            if let cliError = error as? GitHubCLIError, case .accountChanged = cliError,
               scope == snapshotScope, sessionGeneration == session.generation {
                mutationStarted = false
                clear()
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        let interval = Double(max(1, Defaults[.refreshRate])) * 60
        minutesUntilRefresh = max(0, Int(ceil(((lastSyncedAt ?? .now).addingTimeInterval(interval).timeIntervalSinceNow) / 60)))

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rebuildTimelineItems()
                self.minutesUntilRefresh = max(0, self.minutesUntilRefresh - 1)
            }
        }
    }

    private func finishRefresh(
        generation: Int,
        assigned: [Edge],
        created: [Edge],
        requested: [Edge],
        fetchedAssigned: Bool,
        fetchedCreated: Bool,
        fetchedRequested: Bool
    ) {
        guard generation == refreshGeneration else { return }

        let newRequested = reviewRequestedTracker.update(
            edges: requested,
            fetched: fetchedRequested,
            canNotify: hasLoadedOnce
        )
        let newAssigned = assignedTracker.update(
            edges: assigned,
            fetched: fetchedAssigned,
            canNotify: hasLoadedOnce
        )
        let newCreated = createdTracker.update(
            edges: created,
            fetched: fetchedCreated,
            canNotify: hasLoadedOnce
        )

        if hasLoadedOnce {
            sendPRNotifications(
                newReviewRequested: newRequested,
                newAssigned: newAssigned,
                newCreated: newCreated
            )
        }

        lastSyncedAt = currentSnapshot?.syncedAt ?? .now
        isShowingCache = false
        hasIncompleteData = false
        reconcileSnoozes(assigned + created + requested)
        publishPulls(assigned: assigned, created: created, requested: requested)
        sendTimelineSummaries()
        hasLoadedOnce = true

        startCountdown()
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

    private var timelineItems: [TimelineItem] { cachedTimelineItems }

    private func rebuildTimelineItems() {
        cachedTimelineItems = timelineInput().makeItems()
    }

    func timelineInput(now: Date = .now, thresholds: [Int]? = nil, bots: [String]? = nil,
                       ownComments: Bool? = nil, snoozed: [String: Double]? = nil,
                       includeAssigned: Bool = true, includeCreated: Bool = true,
                       includeRequested: Bool = true, username: String? = nil) -> TimelineInput {
        TimelineInput(assigned: assignedPulls, created: createdPulls, requested: reviewRequestedPulls,
                      includeAssigned: includeAssigned, includeCreated: includeCreated, includeRequested: includeRequested,
                      username: username ?? session.cliConnection?.username ?? "", now: now,
                      thresholds: thresholds ?? Defaults[.freshnessThresholds], bots: bots ?? Defaults[.botAccounts],
                      ownComments: ownComments ?? Defaults[.ownCommentsCount], snoozed: snoozed ?? Defaults[.snoozedPulls])
    }

    private func sendTimelineSummaries() {
        let rotting = TimelineNotificationPolicy.rottingOwned(timelineItems)
        let ids = Set(rotting.map(\.id))
        let thresholds = Defaults[.freshnessThresholds]
        if Defaults[.notifyRotting] {
            for item in TimelineNotificationPolicy.newlyRotting(rotting, previousIDs: knownRotting, previousThresholds: previousThresholds, thresholds: thresholds) {
                sendPRNotification(title: "A pull request went quiet", pr: item.pull, category: "rotting")
            }
        }
        knownRotting = ids
        previousThresholds = thresholds
        guard Defaults[.morningSummary] else { return }
        let now = Date()
        guard let day = TimelineNotificationPolicy.summaryDay(now: now, calendar: .current, scheduledMinutes: Defaults[.morningSummaryMinutes], refreshMinutes: Defaults[.refreshRate], lastDay: Defaults[.lastMorningSummary]) else { return }
        let waiting = TimelineNotificationPolicy.waitingForReview(timelineItems).count
        guard waiting > 0 || !rotting.isEmpty else { return }
        sendTimelineNotification(title: "Your pull requests this morning", body: "\(waiting) waiting for your review · \(rotting.count) of yours rotting")
        Defaults[.lastMorningSummary] = day
    }

    private func reconcileSnoozes(_ edges: [Edge]) {
        let (snoozed, activity) = TimelineSnoozePolicy.reconcile(edges: edges, snoozed: Defaults[.snoozedPulls],
            activity: Defaults[.snoozeActivity], now: .now, wakeOnComment: Defaults[.wakeOnComment],
            username: session.cliConnection?.username ?? "")
        if Defaults[.snoozedPulls] != snoozed { Defaults[.snoozedPulls] = snoozed }
        if Defaults[.snoozeActivity] != activity { Defaults[.snoozeActivity] = activity }
    }

    private func finishFailedRefresh(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }
        if let cliError = error as? GitHubCLIError, case .accountChanged = cliError {
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
