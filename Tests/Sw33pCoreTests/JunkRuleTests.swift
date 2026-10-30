import XCTest
@testable import Sw33pCore

final class JunkRuleTests: XCTestCase {
    private func context(root: URL, home: URL? = nil) -> ScanContext {
        ScanContext(
            root: root,
            knownLocations: KnownLocations(home: home ?? root),
            exclusions: []
        )
    }

    func testNodeModulesRequiresPackageJSON() throws {
        let temp = try TempDir()
        let project = try temp.mkdir("app")
        let junk = try temp.mkdir("app/node_modules")
        let rule = NodeModulesRule()

        guard case .skip? = rule.match(url: junk, name: "node_modules", context: context(root: temp.url)) else {
            return XCTFail("Expected skip without package.json")
        }

        try temp.write("app/package.json")
        guard case .candidate(let candidate)? = rule.match(
            url: junk, name: "node_modules", context: context(root: temp.url)
        ) else {
            return XCTFail("Expected candidate with package.json")
        }
        XCTAssertEqual(candidate.projectURL, project)
        XCTAssertEqual(
            candidate.validation,
            .marker(project.appendingPathComponent("package.json"))
        )
    }

    func testSymlinkedMarkerDoesNotValidate() throws {
        let temp = try TempDir()
        let project = try temp.mkdir("app")
        let real = try temp.write("real-package.json")
        try temp.symlink("app/package.json", to: real)
        let junk = try temp.mkdir("app/node_modules")

        let result = NodeModulesRule().match(
            url: junk, name: "node_modules", context: context(root: temp.url)
        )

        guard case .skip? = result else {
            return XCTFail("A symlinked marker must not validate")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
    }

    func testRustTargetRequiresCargoToml() throws {
        let temp = try TempDir()
        let project = try temp.mkdir("rust-app")
        let junk = try temp.mkdir("rust-app/target")
        try temp.write("rust-app/Cargo.toml")

        guard case .candidate(let candidate)? = RustTargetRule().match(
            url: junk, name: "target", context: context(root: temp.url)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.projectURL, project)
    }

    func testPythonVenvRequiresPyvenvConfig() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("py")
        let venv = try temp.mkdir("py/.venv")
        let rule = PythonArtifactsRule()

        guard case .skip? = rule.match(url: venv, name: ".venv", context: context(root: temp.url)) else {
            return XCTFail("Expected skip without pyvenv.cfg")
        }
        try temp.write("py/.venv/pyvenv.cfg")
        guard case .candidate(let candidate)? = rule.match(
            url: venv, name: ".venv", context: context(root: temp.url)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.projectURL, venv.deletingLastPathComponent())
    }

    func testPycacheAggregatesUnderNearestProject() throws {
        let temp = try TempDir()
        let project = try temp.mkdir("py")
        try temp.write("py/pyproject.toml")
        let cache = try temp.mkdir("py/src/__pycache__")

        guard case .candidate(let candidate)? = PythonArtifactsRule().match(
            url: cache, name: "__pycache__", context: context(root: temp.url)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.projectURL, project)
        XCTAssertTrue(candidate.aggregatesPerProject)
        XCTAssertEqual(candidate.validation, .pythonCache)
    }

    func testGradleBuildRequiresGradleFile() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("android")
        let build = try temp.mkdir("android/app/build")
        try temp.write("android/app/build.gradle.kts")

        guard case .candidate(let candidate)? = GradleAndroidRule().match(
            url: build, name: "build", context: context(root: temp.url)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.projectURL, build.deletingLastPathComponent())
    }

    func testDerivedDataChildRequiresInfoPlist() throws {
        let home = try TempDir().url
        let root = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-hash")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rule = XcodeDerivedDataRule(knownLocations: KnownLocations(home: home))

        XCTAssertNil(rule.match(url: root, name: "App-hash", context: context(root: home, home: home)))
        try Data().write(to: root.appendingPathComponent("info.plist"))
        guard case .candidate? = rule.match(
            url: root, name: "App-hash", context: context(root: home, home: home)
        ) else {
            return XCTFail("Expected candidate")
        }
    }

    func testCacheRuleMatchesOnlyKnownRoot() throws {
        let home = try TempDir().url
        let locations = KnownLocations(home: home)
        let rule = CacheRootRule(
            id: RuleID("swiftpm"),
            category: .swiftPM,
            roots: [locations.swiftPM]
        )
        let cache = locations.swiftPM
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        guard case .candidate(let candidate)? = rule.match(
            url: cache, name: "org.swift.swiftpm", context: context(root: home, home: home)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.projectURL, nil)
        XCTAssertEqual(candidate.validation, .knownRoot(cache))
        XCTAssertNil(rule.match(
            url: home.appendingPathComponent("Library/Caches/CocoaPods"),
            name: "CocoaPods",
            context: context(root: home, home: home)
        ))
    }
}
