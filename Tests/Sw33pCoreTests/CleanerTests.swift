import Foundation
import XCTest
@testable import Sw33pCore

private enum FakeTrashError: Error {
    case refused
}

private final class FakeTrash: TrashClient, @unchecked Sendable {
    var trashed: [URL] = []
    var failOn: URL?

    func trash(_ url: URL) throws {
        if let failOn, failOn.standardizedFileURL.path == url.standardizedFileURL.path {
            throw FakeTrashError.refused
        }
        trashed.append(url)
        try FileManager.default.removeItem(at: url)
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
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
        makeItem(urls: [url], validation: validation, removal: removal)
    }

    private func makeItem(
        urls: [URL],
        validation: ItemValidation,
        removal: Removal = .filesystem
    ) -> JunkItem {
        JunkItem(
            ruleID: RuleID("test"),
            category: .nodeModules,
            urls: urls,
            projectURL: urls[0].deletingLastPathComponent(),
            projectLabel: nil,
            lastActivity: Date(),
            allocatedBytes: 100,
            fileCount: 1,
            warnings: [],
            removal: removal,
            validation: validation
        )
    }

    private func makeCleaner(
        temp: TempDir,
        trash: FakeTrash,
        runner: any CommandRunner = StubRunner(status: 0, output: "")
    ) -> Cleaner {
        Cleaner(
            trash: trash,
            remover: FileManagerRemover(),
            runner: runner,
            validator: CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        )
    }

    func testTrashIsTheDefaultPath() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let item = makeItem(url: junk, validation: .marker(marker))
        let plan = CleanupPlan(items: [item], mode: .trash)

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(trash.trashed, [junk])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.removedURLs, [junk])
        XCTAssertEqual(result.removedItemIDs, Set([item.id]))
        XCTAssertEqual(result.attemptedBytes, 100)
        XCTAssertFalse(result.cancelled)
    }

    func testPermanentModeUsesRemover() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
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
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, marker)
    }

    func testFilesystemItemWithoutValidationIsRefused() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .none)],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, junk)
    }

    func testManagedActionRunsCommandAndSkipsFilesystemChecks() async throws {
        let temp = try TempDir()
        let action = MaintenanceAction(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "delete", "UDID"],
            summary: "xcrun simctl delete UDID"
        )
        let cleaner = makeCleaner(
            temp: temp,
            trash: FakeTrash(),
            runner: StubRunner(status: 0, output: "ok")
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
        let cleaner = makeCleaner(
            temp: temp,
            trash: FakeTrash(),
            runner: StubRunner(status: 1, output: "boom")
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

    func testMultiURLValidationFailureReportsSecondURL() async throws {
        let temp = try TempDir()
        let first = try temp.mkdir("a/__pycache__")
        let second = temp.url.appendingPathComponent("b/__pycache__")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let plan = CleanupPlan(
            items: [makeItem(urls: [first, second], validation: .pythonCache)],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, second)
    }

    func testMultiURLPartialFailureKeepsSuccessfulRemovalOnly() async throws {
        let temp = try TempDir()
        let first = try temp.mkdir("a/__pycache__")
        let second = try temp.mkdir("b/__pycache__")
        let trash = FakeTrash()
        trash.failOn = second
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let item = makeItem(urls: [first, second], validation: .pythonCache)
        let plan = CleanupPlan(items: [item], mode: .trash)

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(trash.trashed, [first])
        XCTAssertEqual(result.removedURLs, [first])
        XCTAssertTrue(result.removedItemIDs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testAggregatedPythonCachesSucceedTogether() async throws {
        let temp = try TempDir()
        let first = try temp.mkdir("a/__pycache__")
        let second = try temp.mkdir("b/__pycache__")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let item = makeItem(urls: [first, second], validation: .pythonCache)
        let plan = CleanupPlan(items: [item], mode: .trash)

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(trash.trashed, [first, second])
        XCTAssertEqual(result.removedURLs, [first, second])
        XCTAssertEqual(result.removedItemIDs, Set([item.id]))
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.attemptedBytes, 100)
    }

    func testFailureOfFirstItemDoesNotBlockSecond() async throws {
        let temp = try TempDir()
        let badJunk = try temp.mkdir("bad/node_modules")
        let badMarker = try temp.write("bad/package.json")
        try FileManager.default.removeItem(at: badMarker)
        let goodJunk = try temp.mkdir("good/node_modules")
        let goodMarker = try temp.write("good/package.json")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let badItem = makeItem(url: badJunk, validation: .marker(badMarker))
        let goodItem = makeItem(url: goodJunk, validation: .marker(goodMarker))
        let plan = CleanupPlan(items: [badItem, goodItem], mode: .trash)

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, badMarker)
        XCTAssertEqual(result.removedURLs, [goodJunk])
        XCTAssertEqual(result.removedItemIDs, Set([goodItem.id]))
        XCTAssertEqual(result.attemptedBytes, 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: badJunk.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: goodJunk.path))
    }

    func testCancellationStopsBeforeRemoval() async throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { true })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.attemptedBytes, 0)
    }

    func testCancellationAfterFirstItemLeavesSecondUntouched() async throws {
        let temp = try TempDir()
        let firstJunk = try temp.mkdir("first/node_modules")
        let firstMarker = try temp.write("first/package.json")
        let secondJunk = try temp.mkdir("second/node_modules")
        let secondMarker = try temp.write("second/package.json")
        let trash = FakeTrash()
        let cleaner = makeCleaner(temp: temp, trash: trash)
        let firstItem = makeItem(url: firstJunk, validation: .marker(firstMarker))
        let secondItem = makeItem(url: secondJunk, validation: .marker(secondMarker))
        let plan = CleanupPlan(items: [firstItem, secondItem], mode: .trash)
        let counter = CallCounter()

        // Checks happen before item one, before its URL, then before item two.
        let result = await cleaner.cleanup(
            plan,
            scanRoot: temp.url,
            shouldCancel: { counter.next() >= 3 }
        )

        XCTAssertEqual(trash.trashed, [firstJunk])
        XCTAssertEqual(result.removedItemIDs, Set([firstItem.id]))
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.attemptedBytes, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstJunk.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondJunk.path))
    }

    func testAncestorSwapBetweenInspectAndDeleteRefusesDeletion() async throws {
        let temp = try TempDir()
        let app = try temp.mkdir("app")
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let moved = temp.url.appendingPathComponent("app-moved")
        let trash = FakeTrash()
        var cleaner = makeCleaner(temp: temp, trash: trash)
        cleaner.beforeDeletion = { _ in
            try? FileManager.default.moveItem(at: app, to: moved)
            try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(
                at: app.appendingPathComponent("node_modules"),
                withIntermediateDirectories: true
            )
        }
        let plan = CleanupPlan(
            items: [makeItem(url: junk, validation: .marker(marker))],
            mode: .trash
        )

        let result = await cleaner.cleanup(plan, scanRoot: temp.url, shouldCancel: { false })

        XCTAssertTrue(trash.trashed.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, junk)
        XCTAssertTrue(result.failures.first?.message.contains("changed") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: junk.path))
    }
}
