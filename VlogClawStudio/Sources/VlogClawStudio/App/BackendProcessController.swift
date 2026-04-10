import Foundation

@MainActor
final class BackendProcessController {
    struct Snapshot: Sendable {
        var state: BackendRuntimeState = .idle
        var binaryPath = ""
        var port = 8080
        var logTail = ""
        var pid: Int32?
        var lastError: String?
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?
    private(set) var snapshot = Snapshot()
    private let environment: [String: String]
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
        let configuredBinary = environment["VLOGCLAW_BACKEND_BINARY"] ?? Self.defaultBackendBinaryPath(environment: environment, fileManager: fileManager)
        snapshot.binaryPath = Self.normalizedBackendBinaryPath(
            configuredBinary,
            environment: environment,
            fileManager: fileManager
        )
        if let portString = environment["SERVER_PORT"], let port = Int(portString) {
            snapshot.port = port
        }
    }

    func startIfPossible(onUpdate: @escaping @Sendable (Snapshot) -> Void) {
        guard process == nil else {
            onUpdate(snapshot)
            return
        }

        let binary = Self.normalizedBackendBinaryPath(
            snapshot.binaryPath,
            environment: environment,
            fileManager: fileManager
        )
        snapshot.binaryPath = binary
        guard !binary.isEmpty else {
            snapshot.state = .idle
            snapshot.lastError = "未配置 Go backend 可执行文件路径。"
            onUpdate(snapshot)
            return
        }

        guard fileManager.isExecutableFile(atPath: binary) else {
            snapshot.state = .idle
            snapshot.lastError = "backend binary 不存在或不可执行：\(binary)。先执行 ./VlogClawStudio/scripts/build-backend.sh"
            onUpdate(snapshot)
            return
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let repoRoot = Self.repoRootPath(environment: environment, fileManager: fileManager)

        process.executableURL = URL(fileURLWithPath: binary)
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = resolvedEnvironment()

        process.terminationHandler = Self.makeTerminationHandler(owner: self, onUpdate: onUpdate)

        snapshot.state = .launching
        snapshot.lastError = nil
        onUpdate(snapshot)

        do {
            try process.run()
            self.process = process
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            self.snapshot.state = .running
            self.snapshot.pid = process.processIdentifier
            self.snapshot.lastError = nil
            attachReader(to: stdout.fileHandleForReading, isError: false, onUpdate: onUpdate)
            attachReader(to: stderr.fileHandleForReading, isError: true, onUpdate: onUpdate)
            onUpdate(snapshot)
        } catch {
            snapshot.state = .failed
            snapshot.lastError = error.localizedDescription
            onUpdate(snapshot)
        }
    }

    func stop(onUpdate: @escaping @Sendable (Snapshot) -> Void) {
        process?.terminate()
        stopReaders()
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        snapshot.state = .stopped
        snapshot.pid = nil
        onUpdate(snapshot)
    }

    func updateBinaryPath(_ path: String) {
        snapshot.binaryPath = Self.normalizedBackendBinaryPath(
            path,
            environment: environment,
            fileManager: fileManager
        )
    }

    private func resolvedEnvironment() -> [String: String] {
        var env = environment
        env["SERVER_PORT"] = "\(snapshot.port)"
        var repoRoot = Self.repoRootPath(environment: environment, fileManager: fileManager)
        // If binary path is known, try resolving repo root from it (more reliable in sandboxed App context)
        if let binaryRoot = Self.searchUpwardForRepoRoot(startingAt: snapshot.binaryPath, fileManager: fileManager) {
            repoRoot = binaryRoot
        }
        env["VLOGCLAW_REPO_ROOT"] = env["VLOGCLAW_REPO_ROOT"] ?? repoRoot
        env["WDA_XCODE_WORKSPACE_PATH"] = env["WDA_XCODE_WORKSPACE_PATH"] ?? URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("VlogClawAgent/VlogClawAgent.xcworkspace").path
        if env["SIB_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let sibPath = Self.defaultSIBPath(
               backendBinaryPath: snapshot.binaryPath,
               environment: environment,
               fileManager: fileManager
           ) {
            env["SIB_PATH"] = sibPath
        }
        return env
    }

    private func attachReader(to handle: FileHandle, isError: Bool, onUpdate: @escaping @Sendable (Snapshot) -> Void) {
        let source = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler(handler: Self.makeReadEventHandler(handle: handle, isError: isError, owner: self, onUpdate: onUpdate))
        source.setCancelHandler(handler: Self.makeReadCancelHandler(handle: handle))
        source.resume()

        if isError {
            stderrSource = source
        } else {
            stdoutSource = source
        }
    }

    private func appendLog(_ string: String, markAsError: Bool) {
        let prefix = markAsError ? "[stderr] " : ""
        let incoming = (prefix + string).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        let joined = [snapshot.logTail, incoming]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let lines = joined.split(separator: "\n", omittingEmptySubsequences: false)
        snapshot.logTail = lines.suffix(18).joined(separator: "\n")
    }

    private func stopReaders() {
        stdoutSource?.cancel()
        stderrSource?.cancel()
        stdoutSource = nil
        stderrSource = nil
    }

    private nonisolated static func makeTerminationHandler(
        owner: BackendProcessController,
        onUpdate: @escaping @Sendable (Snapshot) -> Void
    ) -> @Sendable (Process) -> Void {
        { [weak owner] process in
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                owner.stopReaders()
                owner.process = nil
                owner.stdoutPipe = nil
                owner.stderrPipe = nil
                if process.terminationStatus == 0 {
                    owner.snapshot.state = .stopped
                } else {
                    owner.snapshot.state = .failed
                    owner.snapshot.lastError = "backend exited with status \(process.terminationStatus)"
                }
                owner.snapshot.pid = nil
                onUpdate(owner.snapshot)
            }
        }
    }

    private nonisolated static func makeReadEventHandler(
        handle: FileHandle,
        isError: Bool,
        owner: BackendProcessController,
        onUpdate: @escaping @Sendable (Snapshot) -> Void
    ) -> @Sendable () -> Void {
        { [weak owner] in
            let data = handle.availableData
            guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                owner.appendLog(string, markAsError: isError)
                onUpdate(owner.snapshot)
            }
        }
    }

    private nonisolated static func makeReadCancelHandler(handle: FileHandle) -> @Sendable () -> Void {
        {
            try? handle.close()
        }
    }

    private static func defaultBackendBinaryPath(environment: [String: String], fileManager: FileManager) -> String {
        let explicit = ProcessInfo.processInfo.environment["VLOGCLAW_BACKEND_BINARY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            return explicit
        }

        if let bundled = bundledBackendBinaryPath(fileManager: fileManager) {
            return bundled
        }

        let root = repoRootPath(environment: environment, fileManager: fileManager)
        let candidates = [
            "\(root)/backend/bin/vlogclaw",
            "\(root)/backend/bin/vlogclawd",
            "\(root)/backend/build/vlogclaw",
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? candidates[0]
    }

    private static func normalizedBackendBinaryPath(
        _ rawPath: String,
        environment: [String: String],
        fileManager: FileManager
    ) -> String {
        guard let normalized = normalize(rawPath) else {
            return defaultBackendBinaryPath(environment: environment, fileManager: fileManager)
        }

        for candidate in backendBinaryCandidates(from: normalized, environment: environment, fileManager: fileManager) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return normalized
    }

    private static func backendBinaryCandidates(
        from path: String,
        environment: [String: String],
        fileManager: FileManager
    ) -> [String] {
        var candidates: [String] = []

        func append(_ candidate: String?) {
            guard let candidate = normalize(candidate), !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        append(path)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            append(URL(fileURLWithPath: path).appendingPathComponent("vlogclaw").path)
            append(URL(fileURLWithPath: path).appendingPathComponent("bin/vlogclaw").path)
            append(URL(fileURLWithPath: path).appendingPathComponent("backend/bin/vlogclaw").path)
        }

        let repoRoot = repoRootPath(environment: environment, fileManager: fileManager)
        append("\(repoRoot)/backend/bin/vlogclaw")

        return candidates
    }

    private static func bundledBackendBinaryPath(fileManager: FileManager) -> String? {
        let candidates: [String?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Backend/vlogclaw").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Backend/vlogclaw").path,
        ]
        return candidates
            .compactMap(normalize)
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private static func defaultSIBPath(
        backendBinaryPath: String,
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        let backendBinary = normalizedBackendBinaryPath(
            backendBinaryPath,
            environment: environment,
            fileManager: fileManager
        )
        let repoRoot = repoRootPath(environment: environment, fileManager: fileManager)
        let candidates = [
            URL(fileURLWithPath: backendBinary).deletingLastPathComponent().appendingPathComponent("plugins/sonic-ios-bridge").path,
            Bundle.main.resourceURL?.appendingPathComponent("Backend/plugins/sonic-ios-bridge").path ?? "",
            "\(repoRoot)/backend/bin/plugins/sonic-ios-bridge",
        ]

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private static func repoRootPath(environment: [String: String], fileManager: FileManager) -> String {
        let candidates: [String?] = [
            environment["VLOGCLAW_REPO_ROOT"],
            Bundle.main.object(forInfoDictionaryKey: "VlogClawRepoRoot") as? String,
            fileManager.currentDirectoryPath,
            Bundle.main.bundleURL.path,
            Bundle.main.bundleURL.deletingLastPathComponent().path,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path,
        ]

        for candidate in candidates.compactMap({ normalize($0) }) {
            if let discovered = searchUpwardForRepoRoot(startingAt: candidate, fileManager: fileManager) {
                return discovered
            }
        }
        return normalize(fileManager.currentDirectoryPath) ?? fileManager.currentDirectoryPath
    }

    private static func searchUpwardForRepoRoot(startingAt path: String, fileManager: FileManager) -> String? {
        var url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        while true {
            if fileManager.fileExists(atPath: url.appendingPathComponent("backend/go.mod").path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return nil
            }
            url = parent
        }
    }

    private static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
