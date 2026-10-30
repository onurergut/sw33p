import Darwin
import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandOutput
}

public enum CommandRunnerError: Error, Hashable, Sendable, LocalizedError {
    case timedOut(executable: URL, after: Duration)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let executable, let after):
            let components = after.components
            let seconds = Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
            return "\(executable.lastPathComponent) timed out after \(String(format: "%.2f", seconds)) seconds"
        }
    }
}

public struct ProcessCommandRunner: CommandRunner {
    private let timeout: Duration
    private let terminationGrace: Duration
    private let outputDirectory: URL

    public init(timeout: Duration = .seconds(120), terminationGrace: Duration = .seconds(2)) {
        self.init(
            timeout: timeout,
            terminationGrace: terminationGrace,
            outputDirectory: FileManager.default.temporaryDirectory
        )
    }

    init(timeout: Duration, terminationGrace: Duration, outputDirectory: URL) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.outputDirectory = outputDirectory
    }

    public func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        let handle = try ProcessHandle(
            executable: executable,
            arguments: arguments,
            outputDirectory: outputDirectory
        )
        let grace = terminationGrace
        return try await withThrowingTaskGroup(of: CommandOutput.self) { group in
            group.addTask {
                try await Self.execute(handle, terminationGrace: grace)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandRunnerError.timedOut(executable: executable, after: timeout)
            }
            do {
                guard let output = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return output
            } catch {
                group.cancelAll()
                // Wait for the command task's SIGTERM-to-SIGKILL escalation so
                // the runner never reports completion while the child lingers.
                _ = try? await group.next()
                throw error
            }
        }
    }

    private static func execute(
        _ handle: ProcessHandle,
        terminationGrace: Duration
    ) async throws -> CommandOutput {
        defer { handle.removeTemporaryFiles() }
        try Task.checkCancellation()
        try handle.start()
        do {
            while handle.isRunning {
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch {
            await handle.terminateAndWait(grace: terminationGrace)
            throw error
        }
        let output = handle.outputData()
        try Task.checkCancellation()
        return CommandOutput(
            status: handle.terminationStatus,
            stdout: String(decoding: output.stdout, as: UTF8.self),
            stderr: String(decoding: output.stderr, as: UTF8.self)
        )
    }
}

private enum ProcessHandleError: Error {
    case outputFileUnavailable
}

/// Wraps `Process` and its output files for safe cross-thread control.
private final class ProcessHandle: @unchecked Sendable {
    private let process = Process()
    private let outputDirectory: URL
    private let stdoutURL: URL
    private let stderrURL: URL
    private let lock = NSLock()
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var outputHandlesClosed = false

    init(executable: URL, arguments: [String], outputDirectory: URL) throws {
        let directory = outputDirectory.appendingPathComponent(
            "sw33p-command-\(UUID().uuidString)",
            isDirectory: true
        )
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: stderrURL.path, contents: nil),
              let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
              let stderrHandle = try? FileHandle(forWritingTo: stderrURL)
        else {
            try? fileManager.removeItem(at: directory)
            throw ProcessHandleError.outputFileUnavailable
        }

        self.outputDirectory = directory
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle

        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = environment
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        try process.run()
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }

    /// Sends SIGTERM, then SIGKILL after the grace period. Runs detached so
    /// the wait still happens when the calling task is cancelled.
    func terminateAndWait(grace: Duration) async {
        terminate()
        await Task.detached(priority: .utility) { [self] in
            let graceDeadline = ContinuousClock.now + grace
            while isRunning, ContinuousClock.now < graceDeadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if isRunning {
                forceKill()
            }
            let killDeadline = ContinuousClock.now + .seconds(2)
            while isRunning, ContinuousClock.now < killDeadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }.value
    }

    /// Closes our write ends, then reads the files. Descendants that inherited
    /// the write ends cannot block a file read the way they block a pipe EOF.
    func outputData() -> (stdout: Data, stderr: Data) {
        closeOutputHandles()
        let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
        return (stdout, stderr)
    }

    func removeTemporaryFiles() {
        closeOutputHandles()
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    private func closeOutputHandles() {
        lock.lock()
        defer { lock.unlock() }
        guard !outputHandlesClosed else { return }
        outputHandlesClosed = true
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func forceKill() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process.isRunning
    }

    var terminationStatus: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return process.terminationStatus
    }
}
