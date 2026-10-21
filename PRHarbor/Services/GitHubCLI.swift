import Combine
import Defaults
import Foundation

nonisolated struct GitHubCLIConnection: Codable, Defaults.Serializable, Equatable, Sendable {
    let executablePath: String
    let username: String
    let apiBaseURL: String
}

nonisolated enum GitHubCLIError: LocalizedError {
    case notInstalled, signInRequired, accountChanged, requestFailed, timedOut, unsupportedHost
    var errorDescription: String? {
        switch self {
        case .notInstalled: "GitHub CLI was not found. Install gh, run gh auth login in Terminal, then try again."
        case .signInRequired: "GitHub CLI is not signed in. Run gh auth login in Terminal, then reconnect here."
        case .accountChanged: "The active GitHub CLI account changed. Reconnect in Settings → Account to use it."
        case .requestFailed: "GitHub CLI could not complete the request. Check gh auth status in Terminal and try again."
        case .timedOut: "GitHub CLI took too long to respond. Please try again."
        case .unsupportedHost: "Use https://api.github.com or your GitHub Enterprise URL ending in /api/v3."
        }
    }
}

nonisolated struct GitHubCLI: GitHubAPITransport {
    let executableURL: URL
    let hostname: String
    var timeout: TimeInterval = 60

    init(executablePath: String, apiBaseURL: String, timeout: TimeInterval = 60) throws {
        guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw GitHubCLIError.notInstalled
        }
        guard let url = URL(string: apiBaseURL), url.scheme == "https", let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw GitHubCLIError.unsupportedHost
        }
        if apiBaseURL == "https://api.github.com" {
            hostname = "github.com"
        } else {
            guard url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v3",
                  url.port == nil else { throw GitHubCLIError.unsupportedHost }
            hostname = host
        }
        executableURL = URL(fileURLWithPath: executablePath)
        self.timeout = timeout
    }

    static func findExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/opt/local/bin/gh"]
            + (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { "\($0)/gh" }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GitHubCLIError.notInstalled
        }
        return path
    }

    func api(_ endpoint: String, body: Data? = nil) async throws -> Data {
        var arguments = ["api", endpoint, "--hostname", hostname, "--method", body == nil ? "GET" : "POST"]
        if body != nil { arguments += ["--input", "-"] }
        var environment = ProcessInfo.processInfo.environment
        // Use gh's saved account, not an unrelated token inherited from a development shell.
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GH_DEBUG"] {
            environment.removeValue(forKey: key)
        }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_PAGER"] = ""
        let execution = GitHubCLIExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let data = try await execution.run(executable: executableURL, arguments: arguments,
                                               input: body, environment: environment, timeout: timeout)
            try Task.checkCancellation()
            return data
        } onCancel: {
            execution.stop(timedOut: false)
        }
    }
}

// Each request owns one child process. The lock synchronizes launch, cancellation and timeout.
private nonisolated final class GitHubCLIExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    private var finished = false

    func stop(timedOut: Bool) {
        lock.withLock {
            guard !finished else { return }
            self.timedOut = self.timedOut || timedOut
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    func run(executable: URL, arguments: [String], input: Data?, environment: [String: String], timeout: TimeInterval) async throws -> Data {
        let stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        // Exit and both end-of-file events complete the request. They arrive from system
        // dispatch sources, so no thread waits for gh.
        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in completion.leave() }
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            do { try process.run() } catch { throw GitHubCLIError.notInstalled }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        // Drain both streams while gh runs: a full pipe must never block a large PR response.
        let output = CLIStreamReader(), errors = CLIStreamReader()
        output.start(stdout.fileHandleForReading, group: completion)
        errors.start(stderr.fileHandleForReading, group: completion)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
            } catch {
                self?.stop(timedOut: false)
            }
            try? stdin.fileHandleForWriting.close()
        }
        await withCheckedContinuation { continuation in
            completion.notify(queue: .global()) { continuation.resume() }
        }
        let termination = lock.withLock { () -> (Bool, Bool, Int32) in
            finished = true
            return (cancelled, timedOut, process.terminationStatus)
        }
        if termination.1 { throw GitHubCLIError.timedOut }
        if termination.0 { throw CancellationError() }
        if termination.2 == 4 { throw GitHubCLIError.signInRequired }
        let data = output.result
        if termination.2 != 0 {
            // gh reports GraphQL errors with exit code 1. Let the client interpret the JSON
            // so schema fallbacks and mutation failures behave exactly as with URLSession.
            if arguments.count > 1, arguments[1] == "graphql",
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
                return data
            }
            throw GitHubCLIError.requestFailed
        }
        return data
    }
}

// Collects one pipe until end of file. Each handle delivers its callbacks serially.
private nonisolated final class CLIStreamReader: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var ended = false

    func start(_ handle: FileHandle, group: DispatchGroup) {
        group.enter()
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            let reachedEnd = lock.withLock { () -> Bool in
                guard !ended else { return false }
                if chunk.isEmpty { ended = true } else { data.append(chunk) }
                return ended
            }
            guard reachedEnd else { return }
            handle.readabilityHandler = nil
            try? handle.close()
            group.leave()
        }
    }

    var result: Data { lock.withLock { data } }
}

@MainActor
final class GitHubCLIConnector: ObservableObject {
    @Published private(set) var isConnecting = false
    @Published private(set) var error: String?
    @Published private(set) var successfulConnections = 0
    private var task: Task<Void, Never>?
    private var generation = 0

    func connect() {
        cancel()
        let epoch = generation
        let sessionEpoch = GitHubSession.shared.generation
        let baseURL = Defaults[.githubApiBaseUrl]
        isConnecting = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let path = try GitHubCLI.findExecutable()
                let cli = try GitHubCLI(executablePath: path, apiBaseURL: baseURL)
                let user = try await GitHubClient(baseURL: baseURL, buildType: .none, transport: cli).fetchUser()
                try Task.checkCancellation()
                guard generation == epoch, GitHubSession.shared.generation == sessionEpoch,
                      Defaults[.githubApiBaseUrl] == baseURL, !user.login.isEmpty else { throw CancellationError() }
                GitHubSession.shared.useCLI(.init(executablePath: path, username: user.login, apiBaseURL: baseURL))
                successfulConnections += 1
                isConnecting = false
                task = nil
            } catch is CancellationError {
                if generation == epoch { isConnecting = false; task = nil }
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isConnecting = false
                task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isConnecting = false
    }
}
