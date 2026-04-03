
import Foundation
import Defaults

@MainActor
final class PullRequestStore: ObservableObject {

    @Published var assignedPulls: [Edge] = []
    @Published var createdPulls: [Edge] = []
    @Published var reviewRequestedPulls: [Edge] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var minutesUntilRefresh: Int = 0

    @FromKeychain(.githubToken) private var githubToken

    private let ghClient = GitHubClient()
    private var countdownTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshRateObservation: Defaults.Observation?
    private var counterTypeObservation: Defaults.Observation?
    private var settingsObservations: [Defaults.Observation] = []
    private var hasLoadedOnce = false
    private var refreshGeneration = 0

    private var knownReviewRequestedURLs: Set<String> = []
    private var knownAssignedURLs: Set<String> = []
    private var knownCreatedURLs: Set<String> = []

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
        knownReviewRequestedURLs = []
        knownAssignedURLs = []
        knownCreatedURLs = []
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
        CICheck.clearCache()
        isLoading = true
        error = nil
        let username = Defaults[.githubUsername]
        let showAssigned = Defaults[.showAssigned]
        let showCreated = Defaults[.showCreated]
        let showRequested = Defaults[.showRequested]
        let hideDrafts = Defaults[.hideDrafts]

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let assigned = showAssigned
                    ? self.ghClient.fetchPulls(filter: "assignee:\(username)")
                    : []
                async let created = showCreated
                    ? self.ghClient.fetchPulls(filter: "author:\(username)")
                    : []
                async let requested = showRequested
                    ? self.ghClient.fetchPulls(filter: "review-requested:\(username)")
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
                    requested: r
                )
            } catch is CancellationError {
                self.finishCancelledRefresh(generation: generation)
            } catch {
                self.finishFailedRefresh(error, generation: generation)
            }
        }
    }

    private func findNewPulls(in edges: [Edge], knownURLs: Set<String>) -> [Pull] {
        edges
            .filter { !knownURLs.contains($0.node.url.absoluteString) }
            .map { $0.node }
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
        requested: [Edge]
    ) {
        guard generation == refreshGeneration else { return }

        if hasLoadedOnce {
            let newRequested = findNewPulls(in: requested, knownURLs: knownReviewRequestedURLs)
            let newAssigned = findNewPulls(in: assigned, knownURLs: knownAssignedURLs)
            let newCreated = findNewPulls(in: created, knownURLs: knownCreatedURLs)

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

        knownAssignedURLs = Set(assigned.map { $0.node.url.absoluteString })
        knownCreatedURLs = Set(created.map { $0.node.url.absoluteString })
        knownReviewRequestedURLs = Set(requested.map { $0.node.url.absoluteString })

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
