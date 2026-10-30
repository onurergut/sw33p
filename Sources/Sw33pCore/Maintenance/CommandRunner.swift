import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandOutput
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandOutput(
                status: process.terminationStatus,
                stdout: String(decoding: data, as: UTF8.self),
                stderr: ""
            )
        }.value
    }
}
