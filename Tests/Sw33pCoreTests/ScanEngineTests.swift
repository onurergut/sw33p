import XCTest
@testable import Sw33pCore

final class ScanEngineTests: XCTestCase {
    private func scan(
        root: URL,
        home: URL? = nil,
        exclusions: [URL] = [],
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) async throws -> (items: [JunkItem], notes: [ScanNote], issues: [ScanIssue], summary: ScanSummary) {
        let locations = KnownLocations(home: home ?? root)
        let configuration = ScanConfiguration(
            root: root,
            exclusions: exclusions,
            knownLocations: locations,
            rules: RuleCatalog.rules(knownLocations: locations),
            detectors: [],
            shouldCancel: shouldCancel,
            progressInterval: .zero
        )
        var items: [JunkItem] = []
        var notes: [ScanNote] = []
        var issues: [ScanIssue] = []
        var summary: ScanSummary?
        for try await event in ScanEngine(configuration: configuration).scan() {
            switch event {
            case .discovered(let item): items.append(item)
            case .note(let note): notes.append(note)
            case .issue(let issue): issues.append(issue)
            case .finished(let value): summary = value
            case .progress: break
            }
        }
        return (items, notes, issues, try XCTUnwrap(summary))
    }

    func testFindsNodeModulesWithProjectAndActivity() async throws {
        let temp = try TempDir()
        let old = Date(timeIntervalSinceNow: -120 * 86_400)
        try temp.write("app/package.json", modified: old)
        try temp.write("app/old.swift", modified: old)
        try temp.mkdir("app/node_modules")
        try temp.write("app/node_modules/new.js", bytes: 10, modified: Date())

        let result = try await scan(root: temp.url)

        let item = try XCTUnwrap(result.items.first { $0.category == .nodeModules })
        XCTAssertEqual(item.projectURL?.standardizedPath, temp.url.appendingPathComponent("app").standardizedPath)
        XCTAssertEqual(item.lastActivity.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 2)
        XCTAssertGreaterThan(item.allocatedBytes, 0)
        XCTAssertEqual(result.summary.itemCount, 1)
    }

    func testMissingMarkerIsNotListedAndIsReported() async throws {
        let temp = try TempDir()
        try temp.mkdir("app/node_modules")
        try temp.write("app/node_modules/file.js", bytes: 10)

        let result = try await scan(root: temp.url)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.notes.first?.count, 1)
        XCTAssertTrue(result.notes.first?.message.contains("package.json") == true)
    }

    func testSymlinkToJunkOutsideRootIsSkipped() async throws {
        let outside = try TempDir()
        try outside.write("node_modules/file.js", bytes: 10)
        let temp = try TempDir()
        try temp.write("app/package.json")
        try temp.symlink("app/node_modules", to: outside.url.appendingPathComponent("node_modules"))

        let result = try await scan(root: temp.url)

        XCTAssertTrue(result.items.isEmpty)
    }

    func testExcludedFolderIsPruned() async throws {
        let temp = try TempDir()
        try temp.write("excluded/app/package.json")
        try temp.mkdir("excluded/app/node_modules")
        try temp.write("excluded/app/node_modules/x.js", bytes: 10)
        try temp.write("included/app/package.json")
        try temp.mkdir("included/app/node_modules")
        try temp.write("included/app/node_modules/x.js", bytes: 10)
        let excluded = temp.url.appendingPathComponent("excluded")

        let result = try await scan(root: temp.url, exclusions: [excluded])

        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].url.path.contains("included"))
    }

    func testUnreadableFolderIsReportedAndScanContinues() async throws {
        let temp = try TempDir()
        let locked = try temp.mkdir("locked")
        try temp.write("app/package.json")
        try temp.mkdir("app/node_modules")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: locked.path
            )
        }

        let result = try await scan(root: temp.url)

        XCTAssertFalse(result.issues.isEmpty)
        XCTAssertEqual(result.items.count, 1)
    }

    func testKnownCacheIsFoundWithoutProject() async throws {
        let home = try TempDir()
        let cache = home.url.appendingPathComponent("Library/Caches/org.swift.swiftpm")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: cache.appendingPathComponent("data"))

        let result = try await scan(root: home.url, home: home.url)

        let item = try XCTUnwrap(result.items.first { $0.category == .swiftPM })
        XCTAssertNil(item.projectURL)
        XCTAssertEqual(item.validation, .knownRoot(cache))
    }

    func testPycacheAggregatesPerProject() async throws {
        let temp = try TempDir()
        try temp.write("py/pyproject.toml")
        try temp.write("py/a/__pycache__/a.pyc", bytes: 10)
        try temp.write("py/b/__pycache__/b.pyc", bytes: 10)

        let result = try await scan(root: temp.url)

        let pycache = result.items.filter { $0.ruleID == RuleID("python-pycache") }
        XCTAssertEqual(pycache.count, 1)
        XCTAssertEqual(pycache[0].urls.count, 2)
        XCTAssertEqual(pycache[0].projectURL?.lastPathComponent, "py")
    }

    func testPreCancelledScanFinishesWithoutItems() async throws {
        let temp = try TempDir()
        try temp.write("app/package.json")
        try temp.mkdir("app/node_modules")

        let result = try await scan(root: temp.url, shouldCancel: { true })

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.summary.cancelled)
    }

    func testMissingRootThrows() async {
        let missing = URL(fileURLWithPath: "/tmp/sw33p-missing-\(UUID().uuidString)")
        let locations = KnownLocations(home: missing)
        let configuration = ScanConfiguration(
            root: missing,
            exclusions: [],
            knownLocations: locations,
            rules: [],
            detectors: [],
            shouldCancel: { false },
            progressInterval: .zero
        )
        do {
            for try await _ in ScanEngine(configuration: configuration).scan() {}
            XCTFail("Expected rootNotFound")
        } catch {
            XCTAssertEqual(error as? ScanError, .rootNotFound(missing))
        }
    }
}
