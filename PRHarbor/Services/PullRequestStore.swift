
import Foundation
import Defaults

@MainActor
class PullRequestStore: ObservableObject {

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
    private var refreshRateObservation: Defaults.Observation?
    private var counterTypeObservation: Defaults.Observation?
    private var settingsObservations: [Defaults.Observation] = []
    private var hasLoadedOnce = false

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
        assignedPulls = []
        createdPulls = []
        reviewRequestedPulls = []
        error = nil
        minutesUntilRefresh = 0
        hasLoadedOnce = false
        knownReviewRequestedURLs = []
        knownAssignedURLs = []
        knownCreatedURLs = []
        countdownTimer?.invalidate()
    }
    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = Double(Defaults[.refreshRate] * 60)
        refreshTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
        refreshTimer?.fire()
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
        guard isConfigured else { return }

        CICheck.clearCache()
        isLoading = true
        error = nil
        let username = Defaults[.githubUsername]

        Task {
            do {
                async let assigned = Defaults[.showAssigned]
                    ? ghClient.fetchPulls(filter: "assignee:\(username)")
                    : []
                async let created = Defaults[.showCreated]
                    ? ghClient.fetchPulls(filter: "author:\(username)")
                    : []
                async let requested = Defaults[.showRequested]
                    ? ghClient.fetchPulls(filter: "review-requested:\(username)")
                    : []

                var (a, c, r) = try await (assigned, created, requested)

                if Defaults[.hideDrafts] {
                    a = a.filter { !$0.node.isDraft }
                    c = c.filter { !$0.node.isDraft }
                    r = r.filter { !$0.node.isDraft }
                }

                if hasLoadedOnce {
                    let newRequested = findNewPulls(in: r, knownURLs: knownReviewRequestedURLs)
                    let newAssigned = findNewPulls(in: a, knownURLs: knownAssignedURLs)
                    let newCreated = findNewPulls(in: c, knownURLs: knownCreatedURLs)

                    sendPRNotifications(
                        newReviewRequested: newRequested,
                        newAssigned: newAssigned,
                        newCreated: newCreated
                    )
                }

                assignedPulls = a
                createdPulls = c
                reviewRequestedPulls = r
                hasLoadedOnce = true

                knownAssignedURLs = Set(a.map { $0.node.url.absoluteString })
                knownCreatedURLs = Set(c.map { $0.node.url.absoluteString })
                knownReviewRequestedURLs = Set(r.map { $0.node.url.absoluteString })

                startCountdown()
                prefetchAvatars(a + c + r)
            } catch {
                self.error = error.localizedDescription
            }

            isLoading = false
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
}
