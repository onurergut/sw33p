import Foundation
import XCTest
@testable import Sw33pCore

final class ScanEngineTests: XCTestCase {
    private func collect(
        _ engine: ScanEngine
    ) async throws -> (items: [JunkItem], notes: [ScanNote], issues: [ScanIssue], summary: ScanSummary) {
        var items: [JunkItem] = []
        var notes: [ScanNote] = []
        var issues: [ScanIssue] = []
        var summary: ScanSummary?
        for try await event in engine.scan() {
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
        return try await collect(ScanEngine(configuration: configuration))
    }

    private func configuration(
        root: URL,
        rules: [any JunkRule] = [],
        detectors: [any MaintenanceDetector] = [],
        exclusions: [URL] = [],
        home: URL? = nil,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) -> ScanConfiguration {
        ScanConfiguration(
            root: root,
            exclusions: exclusions,
            knownLocations: KnownLocations(home: home ?? root),
            rules: rules,
            detectors: detectors,
            shouldCancel: shouldCancel,
            progressInterval: .zero
        )
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

    func testSymlinkedCacheCannotTurnOrdinaryFolderIntoCleanupTarget() async throws {
        let temp = try TempDir()
        let protected = try temp.mkdir("important")
        try temp.write("important/notes.txt", bytes: 10)
        try temp.symlink(".npm/_cacache", to: protected)

        let result = try await scan(root: temp.url)

        XCTAssertFalse(result.items.contains { $0.url.path == protected.path })
    }

    func testGradleGlobalCacheIsListed() async throws {
        let temp = try TempDir()
        let cache = try temp.mkdir(".gradle/caches")
        try temp.write(".gradle/caches/modules/data.bin", bytes: 4096)

        let result = try await scan(root: temp.url)

        let item = try XCTUnwrap(result.items.first { $0.ruleID == RuleID("gradle-cache") })
        XCTAssertEqual(item.url.path, cache.path)
        XCTAssertEqual(item.category, .gradleAndroid)
        XCTAssertGreaterThan(item.allocatedBytes, 0)
    }

    func testCandidateContainingExcludedFolderIsNotListed() async throws {
        let temp = try TempDir()
        try temp.write("app/package.json")
        let protected = try temp.mkdir("app/node_modules/keep")
        try temp.write("app/node_modules/keep/private.txt", bytes: 10)

        let result = try await scan(root: temp.url, exclusions: [protected])

        XCTAssertTrue(result.items.isEmpty)
    }

    func testManagedDetectorCannotReturnItemsOutsideScanRoot() async throws {
        let temp = try TempDir()
        let selectedRoot = try temp.mkdir("project")
        let outside = try temp.mkdir("global-cache")
        let item = JunkItem(
            ruleID: RuleID("stub-detector"), category: .homebrew,
            urls: [outside], projectURL: nil, projectLabel: nil,
            lastActivity: Date(), allocatedBytes: 1, fileCount: 1,
            warnings: [], removal: .managed(MaintenanceAction(
                executable: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [], summary: "test"
            ))
        )
        let result = try await collect(ScanEngine(configuration: configuration(
            root: selectedRoot, detectors: [StubDetector(item: item)], home: temp.url
        )))

        XCTAssertTrue(result.items.isEmpty)
    }

    func testAnyPhotosLibraryDirectoryIsPruned() async throws {
        let temp = try TempDir()
        try temp.write("Pictures/Trip.photoslibrary/project/package.json")
        try temp.mkdir("Pictures/Trip.photoslibrary/project/node_modules")
        try temp.write("Pictures/Trip.photoslibrary/project/node_modules/x.js", bytes: 10)

        let result = try await scan(root: temp.url)

        XCTAssertTrue(result.items.isEmpty)
    }

    func testAppAndFrameworkBundleContentsAreNotScanned() async throws {
        let temp = try TempDir()
        for bundle in ["Applications/Editor.app/Contents/Resources/app",
                       "Tools/Kit.framework/Resources/app",
                       "Tools/Extension.APPEX/Contents/app"] {
            try temp.write("\(bundle)/package.json")
            try temp.write("\(bundle)/node_modules/x.js", bytes: 10)
        }

        let result = try await scan(root: temp.url)

        XCTAssertTrue(result.items.isEmpty, result.items.map(\.url.path).description)
    }

    func testEditorExtensionsAndToolInstallsInHiddenHomeFoldersAreNotListed() async throws {
        let home = try TempDir()
        try home.write(".vscode/extensions/prettier/package.json")
        try home.write(".vscode/extensions/prettier/node_modules/x.js", bytes: 10)
        try home.write(".config/opencode/package.json")
        try home.write(".config/opencode/node_modules/x.js", bytes: 10)
        try home.write(".local/lib/tool/__pycache__/a.pyc", bytes: 10)
        try home.write(".cache/opencode/package.json")
        try home.write(".cache/opencode/node_modules/x.js", bytes: 10)
        try home.write("code/app/package.json")
        try home.write("code/app/node_modules/x.js", bytes: 10)

        let result = try await scan(root: home.url, home: home.url)

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), ["node_modules"])
        XCTAssertEqual(result.items.first?.projectURL?.lastPathComponent, "app")
    }

    func testHiddenHomeFolderSelectedAsRootIsScanned() async throws {
        let home = try TempDir()
        try home.write(".config/tool/package.json")
        try home.write(".config/tool/node_modules/x.js", bytes: 10)

        let result = try await scan(root: home.url.appendingPathComponent(".config"), home: home.url)

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.category, .nodeModules)
    }

    func testNpxCacheIsListedAsOneCacheItem() async throws {
        let home = try TempDir()
        try home.write(".npm/_npx/1a2b/package.json")
        try home.write(".npm/_npx/1a2b/node_modules/x.js", bytes: 10)

        let result = try await scan(root: home.url, home: home.url)

        XCTAssertEqual(result.items.count, 1)
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.category, .npmCaches)
        XCTAssertEqual(item.url.lastPathComponent, "_npx")
    }

    func testCanonicalRootHonorsAliasedExclusionAndFindsAliasedKnownCache() async throws {
        let temp = try TempDir()
        let real = try temp.mkdir("real")
        try temp.mkdir("real/sub")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("alias"),
            withDestinationURL: real
        )

        let locations = KnownLocations(home: real.appendingPathComponent("sub"))
        let cache = locations.swiftPM
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: cache.appendingPathComponent("data"))

        try temp.write("real/sub/excluded/app/package.json")
        try temp.mkdir("real/sub/excluded/app/node_modules")
        try temp.write("real/sub/excluded/app/node_modules/x.js", bytes: 10)
        try temp.write("real/sub/included/app/package.json")
        try temp.mkdir("real/sub/included/app/node_modules")
        try temp.write("real/sub/included/app/node_modules/x.js", bytes: 10)

        let scanRoot = temp.url.appendingPathComponent("alias/sub")
        let aliasExclusion = temp.url.appendingPathComponent("alias/sub/excluded")

        let result = try await scan(root: scanRoot, home: scanRoot, exclusions: [aliasExclusion])

        XCTAssertFalse(result.items.contains { $0.url.path.contains("/excluded/") })
        let nodeModules = result.items.filter { $0.category == .nodeModules }
        XCTAssertEqual(nodeModules.count, 1)
        XCTAssertTrue(nodeModules[0].url.path.contains("/included/"))
        let cacheItem = try XCTUnwrap(result.items.first { $0.category == .swiftPM })
        XCTAssertEqual(cacheItem.validation, .knownRoot(cache))
        XCTAssertNil(cacheItem.projectURL)
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

    func testUnreadableDirectoryInsideCandidateIsReportedAndUndercountVisible() async throws {
        let temp = try TempDir()
        try temp.write("app/package.json")
        try temp.write("app/node_modules/ok.js", bytes: 10)
        let locked = try temp.mkdir("app/node_modules/locked")
        try temp.write("app/node_modules/locked/hidden.js", bytes: 4096)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path
            )
        }

        let result = try await scan(root: temp.url)

        let item = try XCTUnwrap(result.items.first { $0.category == .nodeModules })
        XCTAssertEqual(item.fileCount, 1, "Files in the unreadable subtree cannot be counted")
        XCTAssertEqual(
            result.issues.filter { $0.url.standardizedPath == locked.standardizedPath }.count,
            1
        )
        XCTAssertGreaterThanOrEqual(result.summary.unreadableCount, 1)
    }

    func testKnownCacheIsFoundWithoutProject() async throws {
        let home = try TempDir()
        let locations = KnownLocations(home: home.url)
        let cache = locations.swiftPM
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

    func testPycacheWithoutProjectGroupsUnderPackageSourceRoot() async throws {
        let temp = try TempDir()
        try temp.write("work/libs/fontTools/__init__.py")
        try temp.write("work/libs/fontTools/__pycache__/a.pyc", bytes: 10)
        try temp.write("work/libs/fontTools/pens/__init__.py")
        try temp.write("work/libs/fontTools/pens/__pycache__/b.pyc", bytes: 10)
        try temp.write("work/libs/fontTools/pens/deep/__init__.py")
        try temp.write("work/libs/fontTools/pens/deep/__pycache__/c.pyc", bytes: 10)
        try temp.write("work/scripts/__pycache__/d.pyc", bytes: 10)

        let result = try await scan(root: temp.url)

        let pycache = result.items.filter { $0.ruleID == RuleID("python-pycache") }
        XCTAssertEqual(
            Set(pycache.map { "\($0.projectURL?.lastPathComponent ?? "-"):\($0.urls.count)" }),
            ["libs:3", "scripts:1"]
        )
    }

    func testNestedProjectActivityAttribution() async throws {
        let temp = try TempDir()
        let repoDate = Date(timeIntervalSinceNow: -100 * 86_400)
        let nestedDate = Date(timeIntervalSinceNow: -50 * 86_400)
        let siblingDate = Date(timeIntervalSinceNow: -10 * 86_400)

        try temp.write("repo/package.json", modified: repoDate)
        try temp.write("repo/packages/a/package.json", modified: nestedDate)
        try temp.write("repo/packages/b/index.js", modified: siblingDate)
        try temp.mkdir("repo/node_modules")
        try temp.write("repo/node_modules/new.js", bytes: 10, modified: Date())
        try temp.mkdir("repo/packages/a/node_modules")
        try temp.write("repo/packages/a/node_modules/new.js", bytes: 10, modified: Date())

        let result = try await scan(root: temp.url)

        let nodeModules = result.items.filter { $0.category == .nodeModules }
        XCTAssertEqual(nodeModules.count, 2)
        let repoItem = try XCTUnwrap(nodeModules.first {
            $0.projectURL?.lastPathComponent == "repo"
        })
        let nestedItem = try XCTUnwrap(nodeModules.first {
            $0.projectURL?.lastPathComponent == "a"
        })
        XCTAssertEqual(repoItem.lastActivity.timeIntervalSince1970, siblingDate.timeIntervalSince1970, accuracy: 2)
        XCTAssertEqual(nestedItem.lastActivity.timeIntervalSince1970, nestedDate.timeIntervalSince1970, accuracy: 2)
    }

    func testPreCancelledScanFinishesWithoutItems() async throws {
        let temp = try TempDir()
        try temp.write("app/package.json")
        try temp.mkdir("app/node_modules")

        let result = try await scan(root: temp.url, shouldCancel: { true })

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.summary.cancelled)
    }

    func testMidWalkCancellationKeepsSummaryConsistent() async throws {
        let temp = try TempDir()
        try temp.write("app/package.json")
        try temp.mkdir("app/node_modules")
        try temp.write("app/node_modules/x.js", bytes: 10)
        try temp.mkdir("tail")

        let signal = EmitSignal()
        var engine = ScanEngine(configuration: configuration(
            root: temp.url,
            rules: RuleCatalog.rules(knownLocations: KnownLocations(home: temp.url)),
            shouldCancel: { signal.isSet() }
        ))
        engine.eventObserver = { event in
            if case .discovered = event { signal.set() }
        }

        let result = try await collect(engine)

        XCTAssertTrue(result.summary.cancelled)
        XCTAssertGreaterThan(result.items.count, 0)
        XCTAssertEqual(result.items.count, result.summary.itemCount)
        XCTAssertEqual(
            result.items.reduce(Int64(0)) { $0 + $1.allocatedBytes },
            result.summary.totalBytes
        )
    }

    func testDetectorIntegration() async throws {
        let temp = try TempDir()
        let item = JunkItem(
            ruleID: RuleID("stub-detector"),
            category: .swiftPM,
            urls: [temp.url],
            projectURL: nil,
            projectLabel: "Stub",
            lastActivity: Date(),
            allocatedBytes: 123,
            fileCount: 1,
            warnings: [],
            removal: .filesystem
        )
        let result = try await collect(ScanEngine(configuration: configuration(
            root: temp.url,
            detectors: [StubDetector(item: item)]
        )))

        XCTAssertEqual(result.items, [item])
        XCTAssertEqual(result.summary.itemCount, 1)
        XCTAssertEqual(result.summary.totalBytes, 123)
    }

    func testConsumerCancellationStopsWalkEvenWhenCancelClosureReturnsFalse() async throws {
        let temp = try TempDir()
        for index in 0..<60 {
            try temp.mkdir("d\(index)")
        }

        let probe = DetectorProbe()
        let configuration = configuration(
            root: temp.url,
            rules: [SlowRule()],
            detectors: [ProbeDetector(probe: probe)],
            shouldCancel: { false }
        )
        let stream = ScanEngine(configuration: configuration).scan()
        let consumer = Task {
            for try await _ in stream {}
        }

        try await Task.sleep(for: .milliseconds(30))
        consumer.cancel()
        _ = try? await consumer.value
        try await Task.sleep(for: .milliseconds(500))

        let wasCalled = await probe.wasCalled()
        XCTAssertFalse(wasCalled, "Cancelling the consumer must stop the scan task")
    }

    func testMissingRootThrows() async {
        let missing = URL(fileURLWithPath: "/tmp/sw33p-missing-\(UUID().uuidString)")
        let configuration = configuration(root: missing)

        do {
            for try await _ in ScanEngine(configuration: configuration).scan() {}
            XCTFail("Expected rootNotFound")
        } catch {
            XCTAssertEqual(error as? ScanError, .rootNotFound(missing))
        }
    }

    func testRootIsNotDirectoryThrows() async throws {
        let temp = try TempDir()
        let file = try temp.write("file.txt")
        let configuration = configuration(root: file)

        do {
            for try await _ in ScanEngine(configuration: configuration).scan() {}
            XCTFail("Expected rootIsNotDirectory")
        } catch {
            XCTAssertEqual(error as? ScanError, .rootIsNotDirectory(file))
        }
    }

    func testRootSymlinkThrows() async throws {
        let temp = try TempDir()
        let real = try temp.mkdir("real")
        try temp.write("real/inside.txt")
        let alias = try temp.symlink("alias", to: real)
        let configuration = configuration(root: alias)

        do {
            for try await _ in ScanEngine(configuration: configuration).scan() {}
            XCTFail("Expected rootIsSymlink")
        } catch {
            XCTAssertEqual(error as? ScanError, .rootIsSymlink(alias))
        }
    }

    func testScanningTwoThousandDirectoriesIsFast() async throws {
        let temp = try TempDir()
        for index in 0..<2000 {
            try FileManager.default.createDirectory(
                at: temp.url.appendingPathComponent("d\(index)", isDirectory: true),
                withIntermediateDirectories: false
            )
        }

        let started = Date()
        let result = try await scan(root: temp.url)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertLessThan(elapsed, 5, "2000-directory scan took \(elapsed)s")
        print(String(format: "ScanEngine 2000-directory scan: %.3fs", elapsed))
    }
}

private final class EmitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func isSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct SlowRule: JunkRule {
    let id = RuleID("slow")
    let category: JunkCategory = .nodeModules

    func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        Thread.sleep(forTimeInterval: 0.002)
        return nil
    }
}

private actor DetectorProbe {
    private var called = false

    func markCalled() {
        called = true
    }

    func wasCalled() -> Bool {
        called
    }
}

private struct ProbeDetector: MaintenanceDetector {
    let probe: DetectorProbe

    func detect(context: ScanContext) async -> [JunkItem] {
        await probe.markCalled()
        return []
    }
}

private struct StubDetector: MaintenanceDetector {
    let item: JunkItem

    func detect(context: ScanContext) async -> [JunkItem] {
        [item]
    }
}
