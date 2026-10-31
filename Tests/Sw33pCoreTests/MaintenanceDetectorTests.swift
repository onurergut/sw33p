import XCTest
@testable import Sw33pCore

private struct ScriptedRunner: CommandRunner {
    let handler: @Sendable (URL, [String]) async throws -> CommandOutput

    func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        try await handler(executable, arguments)
    }
}

final class MaintenanceDetectorTests: XCTestCase {
    private let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
    private let unavailableUDID = "11111111-1111-1111-1111-111111111111"
    private let secondUDID = "22222222-2222-2222-2222-222222222222"

    private func context(for home: TempDir) -> ScanContext {
        ScanContext(
            root: home.url,
            knownLocations: KnownLocations(home: home.url),
            exclusions: []
        )
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    func testSimulatorDetectorDoesNotInspectDevicesOutsideSelectedRoot() async throws {
        let home = try TempDir()
        let selected = try home.mkdir("project")
        let detector = SimulatorDetector(
            devicesRoot: home.url.appendingPathComponent("Devices"),
            runner: ScriptedRunner { _, _ in
                XCTFail("Out-of-scope simulators must not be inspected")
                return CommandOutput(status: 0, stdout: "", stderr: "")
            }
        )
        let scope = ScanContext(root: selected, knownLocations: KnownLocations(home: home.url), exclusions: [])

        let items = await detector.detect(context: scope)

        XCTAssertTrue(items.isEmpty)
    }

    func testHomebrewCacheOutsideSelectedRootIsNotListed() async throws {
        let home = try TempDir()
        let selected = try home.mkdir("project")
        let cache = try home.mkdir("cache")
        let brew = try home.write("bin/brew")
        try makeExecutable(brew)
        let detector = HomebrewDetector(
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: cache.path, stderr: "")
            }, brewExecutable: brew
        )
        let scope = ScanContext(root: selected, knownLocations: KnownLocations(home: home.url), exclusions: [])

        let items = await detector.detect(context: scope)

        XCTAssertTrue(items.isEmpty)
    }

    func testSimulatorDetectorFindsOnlyUnavailableDevices() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let lost = devices.appendingPathComponent(unavailableUDID)
        let live = devices.appendingPathComponent(secondUDID)
        try FileManager.default.createDirectory(at: lost, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: lost.appendingPathComponent("data"))

        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"\(unavailableUDID)","name":"iPhone 15","state":"unavailable","isAvailable":false},
          {"udid":"\(secondUDID)","name":"iPhone 15 Pro","state":"Booted","isAvailable":true}
        ]}}
        """
        let runner = ScriptedRunner { _, arguments in
            XCTAssertEqual(arguments, ["simctl", "list", "devices", "-j"])
            return CommandOutput(status: 0, stdout: json, stderr: "")
        }
        let detector = SimulatorDetector(devicesRoot: devices, runner: runner, xcrun: xcrun)

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .simulators)
        XCTAssertEqual(items[0].url, lost)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.executable, xcrun)
        XCTAssertEqual(action.arguments, ["simctl", "delete", unavailableUDID])
    }

    func testSimulatorDetectorSelectsRealWorldUnavailableShape() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Devices")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"\(unavailableUDID)","name":"iPhone 15","state":"Shutdown","isAvailable":false}
        ]}}
        """
        let detector = SimulatorDetector(
            devicesRoot: devices,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: json, stderr: "")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 1)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.executable, xcrun)
        XCTAssertEqual(action.arguments, ["simctl", "delete", unavailableUDID])
    }

    func testSimulatorDetectorPrefersIsAvailableOverState() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Devices")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"\(unavailableUDID)","name":"Available","state":"unavailable","isAvailable":true}
        ]}}
        """
        let detector = SimulatorDetector(
            devicesRoot: devices,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: json, stderr: "")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
    }

    func testSimulatorDetectorSkipsMalformedEntriesWithoutDroppingValidOnes() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Devices")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"\(unavailableUDID)","name":"iPhone A","state":"Shutdown","isAvailable":false},
          {"udid":"\(secondUDID)"},
          "not an object",
          {"udid":42,"name":"Bad","state":"Shutdown","isAvailable":false},
          {"udid":"33333333-3333-3333-3333-333333333333","name":"iPhone C","state":"unavailable"},
          {"udid":"44444444-4444-4444-4444-444444444444","name":"iPhone D","state":"unavailable","isAvailable":true},
          {"udid":"55555555-5555-5555-5555-555555555555","name":"iPhone E","state":"Booted","isAvailable":true}
        ]}}
        """
        let detector = SimulatorDetector(
            devicesRoot: devices,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: json, stderr: "")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(
            items.compactMap(\.projectLabel).sorted(),
            ["iPhone A (iOS 17 0)", "iPhone C (iOS 17 0)"]
        )
    }

    func testSimulatorDetectorRejectsInvalidUDIDsAndDeduplicates() async throws {
        let home = try TempDir()
        let devices = home.url.appendingPathComponent("Devices")
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"\(unavailableUDID)","name":"iPhone A","state":"Shutdown","isAvailable":false},
          {"udid":"\(unavailableUDID)","name":"Duplicate","state":"Shutdown","isAvailable":false},
          {"udid":"not-a-udid","name":"Bad","state":"Shutdown","isAvailable":false},
          {"udid":"\(unavailableUDID)\\n","name":"Newline","state":"Shutdown","isAvailable":false},
          {"udid":"\(secondUDID)","name":"iPhone B","state":"Shutdown","isAvailable":false}
        ]}}
        """
        let detector = SimulatorDetector(
            devicesRoot: devices,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: json, stderr: "")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 2)
        let actions = items.compactMap { item -> [String]? in
            guard case .managed(let action) = item.removal else { return nil }
            return action.arguments
        }
        XCTAssertEqual(actions.filter { $0 == ["simctl", "delete", unavailableUDID] }.count, 1)
        XCTAssertEqual(actions.filter { $0 == ["simctl", "delete", secondUDID] }.count, 1)
        XCTAssertFalse(items.contains { $0.projectLabel == "Duplicate (iOS 17 0)" })
    }

    func testSimulatorDetectorIgnoresFailedCommand() async throws {
        let home = try TempDir()
        let detector = SimulatorDetector(
            devicesRoot: home.url,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 1, stdout: "", stderr: "no xcode")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
    }

    func testSimulatorDetectorIgnoresMalformedJSON() async throws {
        let home = try TempDir()
        let detector = SimulatorDetector(
            devicesRoot: home.url,
            runner: ScriptedRunner { _, _ in
                CommandOutput(status: 0, stdout: "{not json", stderr: "")
            },
            xcrun: xcrun
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
    }

    func testHomebrewDetectorUsesReportedCacheDirectory() async throws {
        let home = try TempDir()
        let brew = try home.write("bin/brew")
        try makeExecutable(brew)
        let cache = try home.mkdir("brew-cache")
        try home.write("brew-cache/old.tar.gz", bytes: 2048)
        let runner = ScriptedRunner { executable, arguments in
            XCTAssertEqual(executable, brew)
            XCTAssertEqual(arguments, ["--cache"])
            return CommandOutput(status: 0, stdout: cache.path + "\n", stderr: "")
        }
        let detector = HomebrewDetector(runner: runner, brewExecutable: brew)

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .homebrew)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.executable, brew)
        XCTAssertEqual(action.arguments, ["cleanup"])
        XCTAssertGreaterThan(items[0].allocatedBytes, 0)
        XCTAssertEqual(items[0].warnings.first?.code, "homebrew")
        XCTAssertEqual(
            items[0].warnings.first?.message,
            "brew cleanup removes old downloads and outdated versions."
        )
    }

    func testHomebrewDetectorDiscoversSecondCandidateAndSkipsBanner() async throws {
        let home = try TempDir()
        let first = try home.write("first/brew")
        let second = try home.write("second/brew")
        try makeExecutable(second)
        let cache = try home.mkdir("brew-cache")
        try home.write("brew-cache/old.tar.gz", bytes: 2048)
        let runner = ScriptedRunner { executable, arguments in
            XCTAssertEqual(executable, second)
            XCTAssertEqual(arguments, ["--cache"])
            return CommandOutput(
                status: 0,
                stdout: "Warning: unrelated banner\n\n\(cache.path)\n",
                stderr: ""
            )
        }
        let detector = HomebrewDetector(
            runner: runner,
            brewCandidates: [first, second]
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url.path, cache.path)
        guard case .managed(let action) = items[0].removal else {
            return XCTFail("Expected managed action")
        }
        XCTAssertEqual(action.executable, second)
        XCTAssertEqual(action.arguments, ["cleanup"])
    }

    func testHomebrewDetectorReturnsNothingWhenNoCandidatesExist() async throws {
        let home = try TempDir()
        let detector = HomebrewDetector(
            runner: ScriptedRunner { _, _ in
                XCTFail("Should not run without candidates")
                return CommandOutput(status: 1, stdout: "", stderr: "")
            },
            brewCandidates: []
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
    }

    func testHomebrewDetectorRejectsNonExecutableExplicitBrew() async throws {
        let home = try TempDir()
        let brew = try home.write("bin/brew")
        let detector = HomebrewDetector(
            runner: ScriptedRunner { _, _ in
                XCTFail("Should not run a non-executable brew")
                return CommandOutput(status: 1, stdout: "", stderr: "")
            },
            brewExecutable: brew
        )

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
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

        let items = await detector.detect(context: context(for: home))

        XCTAssertTrue(items.isEmpty)
    }
}
