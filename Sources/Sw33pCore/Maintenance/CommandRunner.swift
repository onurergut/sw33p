import Darwin
import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandOutput
}

public enum CommandRunnerError: Error, Hashable, Sendable {
    case timedOut(executable: URL)
}

public struct ProcessCommandRunner: CommandRunner {
    private let timeout: Duration
    private let terminationGrace: Duration

    public init(timeout: Duration = .seconds(120), terminationGrace: Duration = .seconds(2)) {
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    public func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        let handle = ProcessHandle(executable: executable, arguments: arguments)
        let grace = terminationGrace
        return try await withThrowingTaskGroup(of: CommandOutput.self) { group in
            group.addTask {
                try await Self.execute(handle, terminationGrace: grace)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandRunnerError.timedOut(executable: executable)
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
        let stdout = await handle.stdoutData()
        let stderr = await handle.stderrData()
        try Task.checkCancellation()
        return CommandOutput(
            status: handle.terminationStatus,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self)
        )
    }
}

/// Wraps `Process` and its pipes for safe cross-thread start/terminate calls.
private final class ProcessHandle: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lock = NSLock()
    private var stdoutTask: Task<Data, Never>?
    private var stderrTask: Task<Data, Never>?

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        try process.run()
        stdoutTask = Task.detached(priority: .utility) { [self] in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        stderrTask = Task.detached(priority: .utility) { [self] in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
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

    func stdoutData() async -> Data {
        let task = lock.withLock { stdoutTask }
        return await task?.value ?? Data()
    }

    func stderrData() async -> Data {
        let task = lock.withLock { stderrTask }
        return await task?.value ?? Data()
    }
}
