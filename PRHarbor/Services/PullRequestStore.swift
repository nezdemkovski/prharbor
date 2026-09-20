
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

@MainActor
final class PullRequestStore: ObservableObject {

    @Published var assignedPulls: [Edge] = []
    @Published var createdPulls: [Edge] = []
    @Published var reviewRequestedPulls: [Edge] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var minutesUntilRefresh: Int = 0

    @FromKeychain(.githubToken) private var githubToken

    private var countdownTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshRateObservation: Defaults.Observation?
    private var counterTypeObservation: Defaults.Observation?
    private var settingsObservations: [Defaults.Observation] = []
    private var hasLoadedOnce = false
    private var refreshGeneration = 0

    private var reviewRequestedTracker = PullRefreshTracker()
    private var assignedTracker = PullRefreshTracker()
    private var createdTracker = PullRefreshTracker()

    init() {
        startAutoRefresh()
        observeRefreshRate()
        observeCounterType()
        observeDataSettings()
    }

    var totalCount: Int {
        switch Defaults[.counterType] {
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
        !Defaults[.githubUsername].isEmpty && !githubToken.isEmpty
    }

    func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        assignedPulls = []
        createdPulls = []
        reviewRequestedPulls = []
        isLoading = false
        error = nil
        minutesUntilRefresh = 0
        hasLoadedOnce = false
        reviewRequestedTracker.reset()
        assignedTracker.reset()
        createdTracker.reset()
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = Double(Defaults[.refreshRate] * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
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
        counterTypeObservation = Defaults.observe(.counterType) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
                self?.refresh()
            }
        }
    }

    private func observeDataSettings() {
        func watch<T: Defaults.Serializable>(_ key: Defaults.Key<T>) {
            settingsObservations.append(
                Defaults.observe(key) { [weak self] change in
                    Task { @MainActor in
                        self?.refresh()
                    }
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
    }

    func refresh() {
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
        let username = Defaults[.githubUsername]
        let showAssigned = Defaults[.showAssigned]
        let showCreated = Defaults[.showCreated]
        let showRequested = Defaults[.showRequested]
        let counterType = Defaults[.counterType]
        let fetchAssigned = showAssigned
            || Defaults[.notifyAssigned]
            || counterType == .assigned
        let fetchCreated = showCreated
            || Defaults[.notifyCreated]
            || counterType == .created
        let fetchRequested = showRequested
            || Defaults[.notifyReviewRequested]
            || counterType == .reviewRequested
        let hideDrafts = Defaults[.hideDrafts]
        let client: GitHubClient

        do {
            client = try GitHubClient(
                token: githubToken,
                baseURL: Defaults[.githubApiBaseUrl],
                buildType: Defaults[.buildType]
            )
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let assigned = fetchAssigned
                    ? client.fetchPulls(filter: "assignee:\(username)")
                    : []
                async let created = fetchCreated
                    ? client.fetchPulls(filter: "author:\(username)")
                    : []
                async let requested = fetchRequested
                    ? client.fetchPulls(filter: "review-requested:\(username)")
                    : []

                var (a, c, r) = try await (assigned, created, requested)
                try Task.checkCancellation()

                if hideDrafts {
                    a = a.filter { !$0.node.isDraft }
                    c = c.filter { !$0.node.isDraft }
                    r = r.filter { !$0.node.isDraft }
                }

                self.finishRefresh(
                    generation: generation,
                    assigned: a,
                    created: c,
                    requested: r,
                    fetchedAssigned: fetchAssigned,
                    fetchedCreated: fetchCreated,
                    fetchedRequested: fetchRequested
                )
            } catch is CancellationError {
                self.finishCancelledRefresh(generation: generation)
            } catch {
                self.finishFailedRefresh(error, generation: generation)
            }
        }
    }

    func rebaseStack(_ stack: PullRequestStack) async throws -> StackRebaseResult {
        let client = try GitHubClient(
            token: githubToken,
            baseURL: Defaults[.githubApiBaseUrl],
            buildType: Defaults[.buildType]
        )
        let result = try await client.rebaseStack(stack)
        refresh()
        return result
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        minutesUntilRefresh = Defaults[.refreshRate]

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
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

        assignedPulls = assigned
        createdPulls = created
        reviewRequestedPulls = requested
        hasLoadedOnce = true

        startCountdown()
        prefetchAvatars(assigned + created + requested)
        isLoading = false
        refreshTask = nil
    }

    private func finishFailedRefresh(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }
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
