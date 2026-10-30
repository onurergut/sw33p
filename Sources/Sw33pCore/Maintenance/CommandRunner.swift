import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandOutput
}

public enum CommandRunnerError: Error, Hashable, Sendable {
    case timedOut(executable: URL)
}

public struct ProcessCommandRunner: CommandRunner {
    private let timeout: Duration

    public init(timeout: Duration = .seconds(120)) {
        self.timeout = timeout
    }

    public func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        let handle = ProcessHandle(executable: executable, arguments: arguments)
        return try await withThrowingTaskGroup(of: CommandOutput.self) { group in
            group.addTask {
                try await Self.execute(handle)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandRunnerError.timedOut(executable: executable)
            }
            defer { group.cancelAll() }
            guard let output = try await group.next() else {
                throw CancellationError()
            }
            return output
        }
    }

    private static func execute(_ handle: ProcessHandle) async throws -> CommandOutput {
        try await withTaskCancellationHandler {
            defer { handle.terminate() }
            try Task.checkCancellation()
            try handle.start()
            if Task.isCancelled {
                handle.terminate()
            }
            while handle.isRunning {
                try await Task.sleep(for: .milliseconds(20))
            }
            let stdout = await handle.stdoutData()
            let stderr = await handle.stderrData()
            try Task.checkCancellation()
            return CommandOutput(
                status: handle.terminationStatus,
                stdout: String(decoding: stdout, as: UTF8.self),
                stderr: String(decoding: stderr, as: UTF8.self)
            )
        } onCancel: {
            handle.terminate()
        }
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
