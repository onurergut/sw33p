import Foundation
import XCTest
@testable import Sw33pApp
@testable import Sw33pCore

@MainActor
private final class ScanSource {
    private(set) var configurations: [ScanConfiguration] = []
    private(set) var continuations: [AsyncThrowingStream<ScanEvent, Error>.Continuation] = []
    var failure: ScanError?

    func provider(_ configuration: ScanConfiguration) -> AsyncThrowingStream<ScanEvent, Error> {
        configurations.append(configuration)
        if let failure {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: failure)
            }
        }
        let (stream, continuation) = AsyncThrowingStream<ScanEvent, Error>.makeStream()
        continuations.append(continuation)
        return stream
    }

    func send(_ event: ScanEvent, stream index: Int = 0) {
        continuations[index].yield(event)
    }

    func finish(stream index: Int = 0) {
        continuations[index].finish()
    }
}

@MainActor
private final class CleanupRecorder {
    private(set) var requests: [CleanupRequest] = []
    private let responder: @MainActor (CleanupRequest) -> CleanupResult

    init(
        responder: @escaping @MainActor (CleanupRequest) -> CleanupResult = { _ in
            cleanupResult()
        }
    ) {
        self.responder = responder
    }

    func handle(_ request: CleanupRequest) async -> CleanupResult {
        requests.append(request)
        return responder(request)
    }
}

private func cleanupResult(
    removed: Set<String> = [],
    failures: [CleanupFailure] = [],
    commandOutcomes: [CommandOutcome] = [],
    cancelled: Bool = false
) -> CleanupResult {
    CleanupResult(
        removedItemIDs: removed,
        removedURLs: [],
        failures: failures,
        commandOutcomes: commandOutcomes,
        attemptedBytes: 0,
        cancelled: cancelled
    )
}

private func makeItem(
    path: String,
    category: JunkCategory = .nodeModules,
    bytes: Int64 = 100,
    lastActivity: Date = Date(),
    removal: Removal = .filesystem
) -> JunkItem {
    JunkItem(
        ruleID: RuleID(category.rawValue),
        category: category,
        urls: [URL(fileURLWithPath: path)],
        projectURL: nil,
        projectLabel: nil,
        lastActivity: lastActivity,
        allocatedBytes: bytes,
        fileCount: 1,
        warnings: [],
        removal: removal
    )
}

@MainActor
final class AppModelTests: XCTestCase {
    private func makePreferences() -> (Preferences, UserDefaults, String) {
        let suite = "sw33p.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (Preferences(defaults: defaults), defaults, suite)
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), message)
    }

    func testAgeFilterAndSelectionTotals() {
        let old = Date(timeIntervalSinceNow: -100 * 86_400)
        let fresh = Date()
        let items = [
            makeItem(path: "/tmp/a", bytes: 100, lastActivity: old),
            makeItem(path: "/tmp/b", category: .rustTarget, bytes: 200, lastActivity: fresh),
        ]
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            results: ScanResults(items: items),
            preferences: preferences
        )
        model.ageFilter = .days90

        XCTAssertEqual(model.visibleItems.count, 1)
        model.selectedIDs = Set(model.visibleItems.map(\.id))
        XCTAssertEqual(model.selectedBytes, 100)
    }

    func testChangingAgePrunesHiddenSelection() {
        let old = Date(timeIntervalSinceNow: -100 * 86_400)
        let fresh = Date()
        let items = [
            makeItem(path: "/tmp/a", bytes: 100, lastActivity: old),
            makeItem(path: "/tmp/b", bytes: 200, lastActivity: fresh),
        ]
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            results: ScanResults(items: items),
            preferences: preferences
        )
        model.selectedIDs = Set(items.map(\.id))
        model.ageFilter = .days90

        XCTAssertEqual(model.selectedIDs.count, 1)
    }

    func testChangingCategoryPrunesHiddenSelection() {
        let items = [
            makeItem(path: "/tmp/a", category: .nodeModules),
            makeItem(path: "/tmp/b", category: .rustTarget),
        ]
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            results: ScanResults(items: items),
            preferences: preferences
        )
        model.selectedIDs = Set(items.map(\.id))
        model.selectedCategory = .nodeModules

        XCTAssertEqual(model.selectedIDs.count, 1)
    }

    func testExcludingChildProtectsParentCleanupItem() {
        let item = makeItem(path: "/tmp/sw33p-child-exclusion/node_modules")
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(results: ScanResults(items: [item]), preferences: preferences)
        model.selectedIDs = [item.id]

        model.addExclusion(item.url.appendingPathComponent("keep"))
        model.presentCleanupSummary()

        XCTAssertTrue(model.results.items.isEmpty)
        XCTAssertNil(model.pendingPlan)
    }

    func testAliasedUserExclusionIsHonoredAtCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw33p-exclusion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let item = makeItem(path: real.resolvingSymlinksInPath().appendingPathComponent("node_modules").path)
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(results: ScanResults(items: [item]), preferences: preferences)
        model.userExclusions = [alias]
        model.selectedIDs = [item.id]

        model.presentCleanupSummary()

        XCTAssertNil(model.pendingPlan)
    }

    func testAddingExclusionRemovesMatchingResultsAndSelection() {
        let project = URL(fileURLWithPath: "/tmp/sw33p-example/project", isDirectory: true)
        let item = makeItem(path: project.appendingPathComponent("node_modules").path)
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences
        )
        model.selectedIDs = [item.id]
        model.pendingPlan = CleanupPlan(items: [item], mode: .trash)

        model.addExclusion(project)

        XCTAssertTrue(model.results.items.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.pendingPlan)
        XCTAssertEqual(model.userExclusions, [project.standardizedFileURL])
        XCTAssertEqual(model.alert?.title, "sw33p")
        XCTAssertTrue(model.alert?.message.contains("Rescan") == true)
    }

    func testStartCancelKeepsPartialResultsAndCancelledState() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ScanSource()
        let model = AppModel(
            preferences: preferences,
            scanProvider: { source.provider($0) }
        )
        let item = makeItem(path: "/tmp/partial")

        model.startScan()
        source.send(.discovered(item))
        await waitUntil("partial result should arrive") {
            model.results.items.count == 1
        }

        model.cancelScan()

        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.results.items.count, 1)
        XCTAssertEqual(model.scanSummary?.cancelled, true)
        XCTAssertNil(model.alert)
        XCTAssertEqual(model.scanStatusMessage, "Scan cancelled — showing partial results")
    }

    func testStaleScanEventsAreIgnoredAfterRestart() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ScanSource()
        let model = AppModel(
            preferences: preferences,
            scanProvider: { source.provider($0) }
        )
        let first = makeItem(path: "/tmp/first")
        let stale = makeItem(path: "/tmp/stale")
        let second = makeItem(path: "/tmp/second")

        model.startScan()
        source.send(.discovered(first))
        await waitUntil("first result should arrive") {
            model.results.items.count == 1
        }

        model.cancelScan()
        model.startScan()
        source.send(.discovered(stale), stream: 0)
        source.send(.discovered(second), stream: 1)

        await waitUntil("only the new scan result should remain") {
            model.results.items.count == 1 && model.results.items.first?.id == second.id
        }
        XCTAssertFalse(model.results.items.contains { $0.id == stale.id })
        model.cancelScan()
    }

    func testCleanupUsesVisibleSelectionOnly() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let node = makeItem(path: "/tmp/node", category: .nodeModules)
        let rust = makeItem(path: "/tmp/rust", category: .rustTarget)
        let recorder = CleanupRecorder()
        let model = AppModel(
            results: ScanResults(items: [node, rust]),
            preferences: preferences,
            cleanupProvider: { await recorder.handle($0) }
        )

        model.selectedCategory = .nodeModules
        model.selectedIDs = [node.id, rust.id]
        model.presentCleanupSummary()
        XCTAssertEqual(model.pendingPlan?.items.map(\.id), [node.id])

        await model.confirmCleanup(mode: .trash)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].plan.items.map(\.id), [node.id])
        XCTAssertEqual(recorder.requests[0].plan.mode, .trash)
    }

    func testCleanupRoutesTrashAndPermanentModes() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = makeItem(path: "/tmp/item")
        let recorder = CleanupRecorder()
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences,
            cleanupProvider: { await recorder.handle($0) }
        )
        model.selectedIDs = [item.id]

        model.presentCleanupSummary()
        await model.confirmCleanup(mode: .trash)
        model.presentCleanupSummary()
        await model.confirmCleanup(mode: .permanent)

        XCTAssertEqual(recorder.requests.map(\.plan.mode), [.trash, .permanent])
    }

    func testExcludedItemCannotBeCleanedFromEarlierPlan() async {
        let excluded = URL(fileURLWithPath: "/tmp/sw33p-excluded", isDirectory: true)
        let item = makeItem(path: excluded.appendingPathComponent("node_modules").path)
        let recorder = CleanupRecorder()
        let source = ScanSource()
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            preferences: preferences,
            scanProvider: { source.provider($0) },
            cleanupProvider: { await recorder.handle($0) }
        )

        model.startScan()
        source.send(.discovered(item))
        await waitUntil("excluded item should be discovered") {
            model.results.items.count == 1
        }
        model.selectedIDs = [item.id]
        model.pendingPlan = CleanupPlan(items: [item], mode: .trash)

        model.addExclusion(excluded)

        XCTAssertTrue(model.results.items.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.pendingPlan)
        XCTAssertFalse(model.isScanning)

        // Simulate a stale plan that predates the exclusion.
        model.selectedIDs = [item.id]
        model.pendingPlan = CleanupPlan(items: [item], mode: .trash)
        await model.confirmCleanup(mode: .trash)

        XCTAssertEqual(recorder.requests.count, 0)
        XCTAssertEqual(model.alert?.title, "sw33p")
        XCTAssertTrue(model.alert?.message.contains("excluded") == true)
    }

    func testDefaultExclusionBlocksFilesystemCleanup() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let item = makeItem(path: home.appendingPathComponent(".Trash/stale").path)
        let recorder = CleanupRecorder()
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences,
            cleanupProvider: { await recorder.handle($0) }
        )
        model.selectedIDs = [item.id]
        model.pendingPlan = CleanupPlan(items: [item], mode: .trash)

        await model.confirmCleanup(mode: .trash)

        XCTAssertEqual(recorder.requests.count, 0)
        XCTAssertEqual(model.alert?.title, "sw33p")
        XCTAssertTrue(model.alert?.message.contains("excluded") == true)
    }

    func testCleanupFailuresSurfacePathAndReason() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = makeItem(path: "/tmp/cannot-delete")
        let failure = CleanupFailure(
            itemID: item.id,
            url: item.url,
            message: "Permission denied"
        )
        let recorder = CleanupRecorder { _ in
            cleanupResult(failures: [failure])
        }
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences,
            cleanupProvider: { await recorder.handle($0) }
        )
        model.selectedIDs = [item.id]
        model.presentCleanupSummary()

        await model.confirmCleanup(mode: .trash)

        let message = model.alert?.message ?? ""
        XCTAssertEqual(model.alert?.title, "Cleanup")
        XCTAssertTrue(message.contains("1 item could not be removed"))
        XCTAssertTrue(message.contains(item.url.path))
        XCTAssertTrue(message.contains("Permission denied"))
    }

    func testCleanupSurfacesCommandOutcomesAndTruncatesFailureDetail() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let brew = MaintenanceAction(
            executable: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            arguments: ["cleanup"],
            summary: "brew cleanup"
        )
        let simctl = MaintenanceAction(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "delete", "ABC"],
            summary: "xcrun simctl delete ABC"
        )
        let item = makeItem(
            path: "/Users/test/Library/Developer/CoreSimulator/Devices/ABC",
            category: .simulators,
            removal: .managed(simctl)
        )
        let longOutput = "failure " + String(repeating: "x", count: 500)
        let recorder = CleanupRecorder { _ in
            cleanupResult(commandOutcomes: [
                CommandOutcome(action: brew, status: 0, output: "clean"),
                CommandOutcome(action: simctl, status: 3, output: longOutput),
            ])
        }
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences,
            cleanupProvider: { await recorder.handle($0) }
        )
        model.selectedIDs = [item.id]
        model.presentCleanupSummary()

        await model.confirmCleanup(mode: .trash)

        let message = model.alert?.message ?? ""
        XCTAssertTrue(message.contains("brew cleanup: succeeded"))
        XCTAssertTrue(message.contains("xcrun simctl delete ABC: failed (status 3)"))
        XCTAssertTrue(message.contains("failure"))
        XCTAssertFalse(message.contains(String(repeating: "x", count: 300)))
    }

    func testScanErrorUsesScanErrorAlert() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ScanSource()
        source.failure = .rootNotFound(URL(fileURLWithPath: "/tmp/missing"))
        let model = AppModel(
            preferences: preferences,
            scanProvider: { source.provider($0) }
        )

        model.startScan()
        await waitUntil("scan error alert should appear") {
            model.alert != nil
        }

        XCTAssertEqual(model.alert, .scanError("That folder no longer exists."))
        XCTAssertFalse(model.isScanning)
        XCTAssertNil(model.scanStatusMessage)
    }

    func testScanConfigurationUsesRawRootAndRootChangesAreIgnoredWhileScanning() async throws {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw33p-symlink-\(UUID().uuidString)", isDirectory: true)
        let target = base.appendingPathComponent("target", isDirectory: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: base) }

        let source = ScanSource()
        let model = AppModel(
            preferences: preferences,
            scanProvider: { source.provider($0) }
        )
        model.setScanRoot(link)
        model.startScan()

        XCTAssertEqual(source.configurations.first?.root, link)
        let other = URL(fileURLWithPath: "/tmp/other-root", isDirectory: true)
        model.setScanRoot(other)
        XCTAssertEqual(model.scanRoot, link)
        model.cancelScan()
    }

    func testCleanupCancellationUsesStoredTask() async {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = makeItem(path: "/tmp/cancel-cleanup")
        let provider: CleanupProvider = { request in
            while !request.shouldCancel() {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            return cleanupResult(cancelled: true)
        }
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences,
            cleanupProvider: provider
        )
        model.selectedIDs = [item.id]
        model.presentCleanupSummary()

        let confirmation = Task { await model.confirmCleanup(mode: .trash) }
        await waitUntil("cleanup should be running") {
            model.isCleaning
        }
        model.cancelCleanup()
        await confirmation.value

        XCTAssertFalse(model.isCleaning)
        XCTAssertTrue(model.alert?.message.contains("Cleanup was cancelled") == true)
    }

    func testStartScanIsRefusedWhileCleaning() {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: preferences)
        model.isCleaning = true

        model.startScan()

        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.alert?.title, "sw33p")
        XCTAssertTrue(model.alert?.message.contains("cleanup") == true)
    }

    func testChangingRootClearsTransientState() {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = makeItem(path: "/tmp/a")
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: preferences
        )
        model.selectedIDs = [item.id]
        model.notes = [ScanNote(message: "note", count: 1)]
        model.issues = [ScanIssue(url: item.url, message: "issue")]
        model.pendingPlan = CleanupPlan(items: [item], mode: .trash)
        model.scanSummary = ScanSummary(
            itemCount: 1,
            totalBytes: 100,
            directoriesVisited: 1,
            unreadableCount: 0,
            cancelled: false,
            elapsed: 1
        )

        model.setScanRoot(URL(fileURLWithPath: "/tmp/new-root", isDirectory: true))

        XCTAssertTrue(model.results.items.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertTrue(model.issues.isEmpty)
        XCTAssertNil(model.pendingPlan)
        XCTAssertNil(model.scanSummary)
    }

    func testNotesAndIssuesArePresentedWithoutHidingThem() {
        let (preferences, defaults, suite) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: preferences)
        model.notes = [
            ScanNote(
                ruleID: RuleID("node-modules"),
                message: "node_modules without package.json was left alone",
                count: 3
            ),
            ScanNote(
                ruleID: RuleID("python"),
                message: ".venv without pyvenv.cfg was left alone",
                count: 1
            ),
        ]
        model.issues = [
            ScanIssue(url: URL(fileURLWithPath: "/tmp/a"), message: "Could not read this folder."),
            ScanIssue(url: URL(fileURLWithPath: "/tmp/b"), message: "Could not read this folder."),
        ]

        XCTAssertEqual(model.noteSummaries, [
            "3 node_modules folders were left alone (no package.json)",
            "1 .venv folder was left alone (no pyvenv.cfg)",
        ])
        XCTAssertEqual(
            model.issueSummary,
            "2 folders could not be read — Full Disk Access may help"
        )
        XCTAssertTrue(model.hasStatusDetails)
    }

    func testFormattingBytesAndPluralization() {
        XCTAssertEqual(Formatting.size(0), "0 bytes")
        XCTAssertEqual(Formatting.size(1), "1 byte")
        XCTAssertEqual(Formatting.size(1023), "1023 bytes")
        XCTAssertEqual(Formatting.size(1024), "1 KB")
        XCTAssertEqual(Formatting.items(1), "1 item")
        XCTAssertEqual(Formatting.items(2), "2 items")
        XCTAssertEqual(Formatting.tasks(1), "1 maintenance task")
        XCTAssertEqual(Formatting.tasks(2), "2 maintenance tasks")
    }
}
