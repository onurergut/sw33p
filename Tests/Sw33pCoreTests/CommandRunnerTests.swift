import Foundation
import XCTest
@testable import Sw33pCore

final class CommandRunnerTests: XCTestCase {
    func testNonZeroStatusAndStderrAreReturned() async throws {
        let output = try await ProcessCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops >&2; exit 7"]
        )

        XCTAssertEqual(output.status, 7)
        XCTAssertEqual(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "oops")
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await ProcessCommandRunner().run(
                executable: URL(fileURLWithPath: "/definitely/not/a/real/sw33p-binary"),
                arguments: []
            )
            XCTFail("Expected missing executable to throw")
        } catch {
            // Expected.
        }
    }

    func testLargeStdoutDoesNotDeadlock() async throws {
        let output = try await ProcessCommandRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/yes | /usr/bin/head -c 1048576"]
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout.utf8.count, 1_048_576)
    }

    func testTimeoutTerminatesHungProcess() async throws {
        let runner = ProcessCommandRunner(timeout: .milliseconds(100))
        let started = ContinuousClock.now

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
            XCTFail("Expected the command to time out")
        } catch let error as CommandRunnerError {
            guard case .timedOut = error else {
                return XCTFail("Unexpected runner error: \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("timed out after"))
        }

        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    func testTimeoutEscalatesWhenTERMIsIgnored() async throws {
        let runner = ProcessCommandRunner(
            timeout: .milliseconds(100),
            terminationGrace: .milliseconds(100)
        )
        let started = ContinuousClock.now

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; while :; do sleep 0.1; done"]
            )
            XCTFail("Expected the command to time out")
        } catch let error as CommandRunnerError {
            guard case .timedOut = error else {
                return XCTFail("Unexpected runner error: \(error)")
            }
        }

        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    func testDescendantHoldingOutputDoesNotBlockReturn() async throws {
        let runner = ProcessCommandRunner(
            timeout: .milliseconds(200),
            terminationGrace: .milliseconds(100)
        )
        let started = ContinuousClock.now

        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo ready; /bin/sleep 2 & exit 0"]
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(
            output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "ready"
        )
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }

    func testTemporaryOutputFilesAreRemoved() async throws {
        let temporary = try TempDir()
        let runner = ProcessCommandRunner(
            timeout: .seconds(5),
            terminationGrace: .milliseconds(100),
            outputDirectory: temporary.url
        )

        _ = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"]
        )

        let remaining = try FileManager.default.contentsOfDirectory(atPath: temporary.url.path)
        XCTAssertTrue(remaining.isEmpty, "Unexpected temporary files: \(remaining)")
    }

    func testSubprocessEnvironmentDisablesHomebrewAnalyticsAndAutoUpdate() async throws {
        let output = try await ProcessCommandRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: []
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(output.stdout.contains("HOMEBREW_NO_ANALYTICS=1"))
        XCTAssertTrue(output.stdout.contains("HOMEBREW_NO_AUTO_UPDATE=1"))
    }

    func testOutputErrorsHaveReadableDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/sw33p-missing-output")
        XCTAssertEqual(
            ProcessHandleError.outputReadFailed(url).localizedDescription,
            "Could not read command output from /tmp/sw33p-missing-output."
        )
        XCTAssertEqual(
            ProcessHandleError.outputFileUnavailable.localizedDescription,
            "Could not create temporary output files for the command."
        )
    }

    func testCancellationTerminatesHungProcess() async throws {
        let runner = ProcessCommandRunner(timeout: .seconds(30))
        let task = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let started = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw")
        } catch {
            // Expected.
        }

        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }
}
