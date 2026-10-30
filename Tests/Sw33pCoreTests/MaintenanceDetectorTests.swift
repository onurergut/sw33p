import XCTest
@testable import Sw33pCore

private struct ScriptedRunner: CommandRunner {
    let handler: @Sendable (URL, [String]) async throws -> CommandOutput

    func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        try await handler(executable, arguments)
    }
}

final class MaintenanceDetectorTests: XCTestCase {
    func testSimulatorDetectorFindsOnlyUnavailableDevices() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let lost = devices.appendingPathComponent("11111111-1111-1111-1111-111111111111")
        let live = devices.appendingPathComponent("22222222-2222-2222-2222-222222222222")
        try FileManager.default.createDirectory(at: lost, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: lost.appendingPathComponent("data"))

        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"11111111-1111-1111-1111-111111111111","name":"iPhone 15","state":"unavailable","isAvailable":false},
          {"udid":"22222222-2222-2222-2222-222222222222","name":"iPhone 15 Pro","state":"Booted","isAvailable":true}
        ]}}
        """
        let runner = ScriptedRunner { _, arguments in
            XCTAssertEqual(arguments, ["simctl", "list", "devices", "-j"])
            return CommandOutput(status: 0, stdout: json, stderr: "")
        }
        let detector = SimulatorDetector(
            devicesRoot: devices,
            runner: runner,
            xcrun: URL(fileURLWithPath: "/usr/bin/xcrun")
        )
        let context = ScanContext(
            root: home.url,
            knownLocations: KnownLocations(home: home.url),
            exclusions: []
        )

        let items = await detector.detect(context: context)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .simulators)
        XCTAssertEqual(items[0].url, lost)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.arguments, ["simctl", "delete", "11111111-1111-1111-1111-111111111111"])
    }

    func testSimulatorDetectorIgnoresFailedCommand() async throws {
        let home = try TempDir()
        let runner = ScriptedRunner { _, _ in
            CommandOutput(status: 1, stdout: "", stderr: "no xcode")
        }
        let detector = SimulatorDetector(
            devicesRoot: home.url,
            runner: runner,
            xcrun: URL(fileURLWithPath: "/usr/bin/xcrun")
        )
        let context = ScanContext(
            root: home.url,
            knownLocations: KnownLocations(home: home.url),
            exclusions: []
        )

        let items = await detector.detect(context: context)

        XCTAssertTrue(items.isEmpty)
    }

    func testHomebrewDetectorUsesReportedCacheDirectory() async throws {
        let home = try TempDir()
        let brew = try home.write("bin/brew")
        let cache = try home.mkdir("brew-cache")
        try home.write("brew-cache/old.tar.gz", bytes: 2048)
        let runner = ScriptedRunner { executable, arguments in
            XCTAssertEqual(executable, brew)
            XCTAssertEqual(arguments, ["--cache"])
            return CommandOutput(status: 0, stdout: cache.path + "\n", stderr: "")
        }
        let detector = HomebrewDetector(runner: runner, brewExecutable: brew)
        let context = ScanContext(
            root: home.url,
            knownLocations: KnownLocations(home: home.url),
            exclusions: []
        )

        let items = await detector.detect(context: context)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .homebrew)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.arguments, ["cleanup"])
        XCTAssertGreaterThan(items[0].allocatedBytes, 0)
    }

    func testHomebrewDetectorReturnsNothingWithoutBrew() async throws {
        let home = try TempDir()
        let detector = HomebrewDetector(
            runner: ScriptedRunner { _, _ in
                XCTFail("Should not run when brew is absent")
                return CommandOutput(status: 1, stdout: "", stderr: "")
            },
            brewExecutable: home.url.appendingPathComponent("bin/brew")
        )
        let context = ScanContext(
            root: home.url,
            knownLocations: KnownLocations(home: home.url),
            exclusions: []
        )

        let items = await detector.detect(context: context)

        XCTAssertTrue(items.isEmpty)
    }
}
