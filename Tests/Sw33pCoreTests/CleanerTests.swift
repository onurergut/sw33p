import Foundation
import XCTest
@testable import Sw33pCore

private final class FakeTrash: TrashClient, @unchecked Sendable {
    var trashed: [URL] = []
    var failure: Error?

    func trash(_ url: URL) throws {
        if let failure { throw failure }
        trashed.append(url)
        try FileManager.default.removeItem(at: url)
    }
}

private struct StubRunner: CommandRunner {
    let status: Int32
    let output: String

    func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        CommandOutput(status: status, stdout: output, stderr: "")
    }
}

final class CleanerTests: XCTestCase {
    private func makeItem(
        url: URL,
        validation: ItemValidation,
        removal: Removal = .filesystem
    ) -> JunkItem {
        JunkItem(
            ruleID: RuleID("test"),
            category: .nodeModules,
            urls: [url],
            projectURL: url.deletingLastPathComponent(),
            projectLabel: nil,
            lastActivity: Date(),
            allocatedBytes: 100,
            fileCount: 1,
            warnings: [],
            removal: removal,
            validation: validation
        )
    }

    func testTrashIsTheDefaultPath() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: ""),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(trash.trashed, [junk])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.removedURLs, [junk])
    }

    func testPermanentModeUsesRemover() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: ""),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .permanent
        )

        _ = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
    }

    func testStaleMarkerIsNotRemoved() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        try FileManager.default.removeItem(at: marker)
        let trash = FakeTrash()
        let cleaner = Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: ""),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.failures.count, 1)
    }

    func testFilesystemItemWithoutValidationIsRefused() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let trash = FakeTrash()
        let cleaner = Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: ""),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .none)],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.failures.count, 1)
    }

    func testManagedActionRunsCommandAndSkipsFilesystemChecks() async throws {
        let temp = try TempDir()
        let action = MaintenanceAction(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "delete", "UDID"],
            summary: "xcrun simctl delete UDID"
        )
        let cleaner = Cleaner(
            trash: FakeTrash(),
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: "ok"),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: temp.url, validation: .none, removal: .managed(action))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(result.commandOutcomes.count, 1)
        XCTAssertEqual(result.commandOutcomes[0].status, 0)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testFailedManagedCommandIsReported() async throws {
        let temp = try TempDir()
        let action = MaintenanceAction(
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: [],
            summary: "false"
        )
        let cleaner = Cleaner(
            trash: FakeTrash(),
            remover: FileManagerRemover(),
            runner: StubRunner(status: 1, output: "boom"),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: temp.url, validation: .none, removal: .managed(action))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(result.commandOutcomes.count, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.removedItemIDs.isEmpty)
    }

    func testCancellationStopsBeforeRemoval() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: StubRunner(status: 0, output: ""),
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { true })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertTrue(result.cancelled)
    }
}
