import Foundation
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
        _ = try temp.mkdir("app")
        let real = try temp.write("real-package.json")
        try temp.symlink("app/package.json", to: real)
        let junk = try temp.mkdir("app/node_modules")

        let result = NodeModulesRule().match(
            url: junk, name: "node_modules", context: context(root: temp.url)
        )

        guard case .skip? = result else {
            return XCTFail("A symlinked marker must not validate")
        }
    }

    func testSymlinkedNodeModulesIsNotCandidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("app")
        try temp.write("app/package.json")
        let real = try temp.mkdir("real-node-modules")
        let junk = try temp.symlink("app/node_modules", to: real)

        let result = NodeModulesRule().match(
            url: junk, name: "node_modules", context: context(root: temp.url)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked node_modules must not be a candidate")
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

    func testRustTargetWithoutCargoTomlIsNotCandidate() throws {
        let temp = try TempDir()
        let target = try temp.mkdir("rust-app/target")

        XCTAssertNil(RustTargetRule().match(
            url: target, name: "target", context: context(root: temp.url)
        ))
    }

    func testSymlinkedCargoTomlDoesNotValidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("rust-app")
        let target = try temp.mkdir("rust-app/target")
        let real = try temp.write("real-Cargo.toml")
        try temp.symlink("rust-app/Cargo.toml", to: real)

        XCTAssertNil(RustTargetRule().match(
            url: target, name: "target", context: context(root: temp.url)
        ))
    }

    func testSymlinkedRustTargetIsNotCandidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("rust-app")
        try temp.write("rust-app/Cargo.toml")
        let real = try temp.mkdir("real-target")
        let target = try temp.symlink("rust-app/target", to: real)

        let result = RustTargetRule().match(
            url: target, name: "target", context: context(root: temp.url)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked target must not be a candidate")
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

    func testSymlinkedPyvenvConfigDoesNotValidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("py")
        let venv = try temp.mkdir("py/.venv")
        let real = try temp.write("real-pyvenv.cfg")
        try temp.symlink("py/.venv/pyvenv.cfg", to: real)

        guard case .skip? = PythonArtifactsRule().match(
            url: venv, name: ".venv", context: context(root: temp.url)
        ) else {
            return XCTFail("A symlinked pyvenv.cfg must not validate")
        }
    }

    func testSymlinkedVenvIsNotCandidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("py")
        let real = try temp.mkdir("real-venv")
        try temp.write("real-venv/pyvenv.cfg")
        let venv = try temp.symlink("py/.venv", to: real)

        let result = PythonArtifactsRule().match(
            url: venv, name: ".venv", context: context(root: temp.url)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked .venv must not be a candidate")
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

    func testSymlinkedPycacheIsNotCandidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("py")
        try temp.write("py/pyproject.toml")
        let real = try temp.mkdir("real-pycache")
        let cache = try temp.symlink("py/src/__pycache__", to: real)

        let result = PythonArtifactsRule().match(
            url: cache, name: "__pycache__", context: context(root: temp.url)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked __pycache__ must not be a candidate")
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

    func testGradleBuildWithoutGradleFileIsNotCandidate() throws {
        let temp = try TempDir()
        let build = try temp.mkdir("android/app/build")

        XCTAssertNil(GradleAndroidRule().match(
            url: build, name: "build", context: context(root: temp.url)
        ))
    }

    func testSymlinkedGradleFileDoesNotValidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("android/app")
        let build = try temp.mkdir("android/app/build")
        let real = try temp.write("real-build.gradle")
        try temp.symlink("android/app/build.gradle", to: real)

        XCTAssertNil(GradleAndroidRule().match(
            url: build, name: "build", context: context(root: temp.url)
        ))
    }

    func testSymlinkedGradleBuildIsNotCandidate() throws {
        let temp = try TempDir()
        _ = try temp.mkdir("android/app")
        try temp.write("android/app/build.gradle")
        let real = try temp.mkdir("real-build")
        let build = try temp.symlink("android/app/build", to: real)

        let result = GradleAndroidRule().match(
            url: build, name: "build", context: context(root: temp.url)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked build directory must not be a candidate")
    }

    func testDerivedDataChildRequiresInfoPlist() throws {
        let temp = try TempDir()
        let home = temp.url
        let root = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-hash")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info = root.appendingPathComponent("info.plist")
        let rule = XcodeDerivedDataRule(knownLocations: KnownLocations(home: home))

        XCTAssertNil(rule.match(url: root, name: "App-hash", context: context(root: home, home: home)))
        try Data().write(to: info)
        guard case .candidate(let candidate)? = rule.match(
            url: root, name: "App-hash", context: context(root: home, home: home)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.validation, .marker(info))
    }

    func testSymlinkedDerivedDataIsNotCandidate() throws {
        let temp = try TempDir()
        let home = temp.url
        let rule = XcodeDerivedDataRule(knownLocations: KnownLocations(home: home))
        let real = try temp.mkdir("real-derived-data")
        try temp.write("real-derived-data/info.plist")
        let url = try temp.symlink(
            "Library/Developer/Xcode/DerivedData/App-hash",
            to: real
        )

        XCTAssertNil(rule.match(
            url: url, name: "App-hash", context: context(root: home, home: home)
        ))
    }

    func testXcodeArchiveRequiresExpectedDepthAndInfoPlist() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let rule = XcodeArchivesRule(knownLocations: locations)
        let archive = try temp.mkdir("Library/Developer/Xcode/Archives/2024-01-01/App.xcarchive")
        let info = archive.appendingPathComponent("Info.plist")

        XCTAssertNil(rule.match(
            url: archive, name: "App.xcarchive", context: context(root: home, home: home)
        ), "Missing Info.plist must not validate")

        try Data().write(to: info)
        guard case .candidate(let candidate)? = rule.match(
            url: archive, name: "App.xcarchive", context: context(root: home, home: home)
        ) else {
            return XCTFail("Expected candidate")
        }
        XCTAssertEqual(candidate.validation, .marker(info))
        XCTAssertEqual(candidate.projectLabel, "App")
    }

    func testXcodeArchiveRejectsWrongDepth() throws {
        let temp = try TempDir()
        let home = temp.url
        let rule = XcodeArchivesRule(knownLocations: KnownLocations(home: home))
        let shallow = try temp.mkdir("Library/Developer/Xcode/Archives/App.xcarchive")
        try temp.write("Library/Developer/Xcode/Archives/App.xcarchive/Info.plist")
        let deep = try temp.mkdir("Library/Developer/Xcode/Archives/2024-01-01/nested/App.xcarchive")
        try temp.write("Library/Developer/Xcode/Archives/2024-01-01/nested/App.xcarchive/Info.plist")

        XCTAssertNil(rule.match(
            url: shallow, name: "App.xcarchive", context: context(root: home, home: home)
        ))
        XCTAssertNil(rule.match(
            url: deep, name: "App.xcarchive", context: context(root: home, home: home)
        ))
    }

    func testSymlinkedXcodeArchiveIsNotCandidate() throws {
        let temp = try TempDir()
        let home = temp.url
        let rule = XcodeArchivesRule(knownLocations: KnownLocations(home: home))
        let real = try temp.mkdir("Library/Developer/Xcode/Archives/real/App.xcarchive")
        try temp.write("Library/Developer/Xcode/Archives/real/App.xcarchive/Info.plist")
        let archive = try temp.symlink(
            "Library/Developer/Xcode/Archives/2024-01-01/App.xcarchive",
            to: real
        )

        let result = rule.match(
            url: archive, name: "App.xcarchive", context: context(root: home, home: home)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked .xcarchive must not be a candidate")
    }

    func testDeviceSupportAcceptsVersionShapedNames() throws {
        let temp = try TempDir()
        let home = temp.url
        let base = "Library/Developer/Xcode/iOS DeviceSupport"
        let locations = KnownLocations(home: home)
        let rule = XcodeDeviceSupportRule(knownLocations: locations)
        let expectedRoot = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!

        for name in ["17.0", "17.0 (21A328)", "26.0.1"] {
            let url = try temp.mkdir("\(base)/\(name)")
            guard case .candidate(let candidate)? = rule.match(
                url: url, name: name, context: context(root: home, home: home)
            ) else {
                XCTFail("Expected \(name) to be a candidate")
                continue
            }
            XCTAssertEqual(candidate.projectLabel, "iOS DeviceSupport")
            XCTAssertEqual(candidate.validation, .versionedKnownRoot(expectedRoot))
        }
    }

    func testDeviceSupportRejectsNonVersionShapedNames() throws {
        let temp = try TempDir()
        let home = temp.url
        let base = "Library/Developer/Xcode/iOS DeviceSupport"
        let rule = XcodeDeviceSupportRule(knownLocations: KnownLocations(home: home))

        for name in ["notes.1", "abc.1", ".1", "1.", "cache.2024"] {
            let url = try temp.mkdir("\(base)/\(name)")
            XCTAssertNil(rule.match(
                url: url, name: name, context: context(root: home, home: home)
            ), "\(name) must not match")
        }
    }

    func testDeviceSupportRejectsWrongParentAndFile() throws {
        let temp = try TempDir()
        let home = temp.url
        let rule = XcodeDeviceSupportRule(knownLocations: KnownLocations(home: home))
        let wrongParent = try temp.mkdir("Library/Developer/Xcode/Other/17.0")
        let nested = try temp.mkdir("Library/Developer/Xcode/iOS DeviceSupport/17.0/17.1")
        let file = try temp.write("Library/Developer/Xcode/iOS DeviceSupport/26.0")

        XCTAssertNil(rule.match(
            url: wrongParent, name: "17.0", context: context(root: home, home: home)
        ))
        XCTAssertNil(rule.match(
            url: nested, name: "17.1", context: context(root: home, home: home)
        ))
        XCTAssertNil(rule.match(
            url: file, name: "26.0", context: context(root: home, home: home)
        ))
    }

    func testSymlinkedDeviceSupportIsNotCandidate() throws {
        let temp = try TempDir()
        let home = temp.url
        let rule = XcodeDeviceSupportRule(knownLocations: KnownLocations(home: home))
        let real = try temp.mkdir("real-device-support")
        let url = try temp.symlink(
            "Library/Developer/Xcode/iOS DeviceSupport/17.0",
            to: real
        )

        let result = rule.match(
            url: url, name: "17.0", context: context(root: home, home: home)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked DeviceSupport directory must not be a candidate")
    }

    func testCacheRuleMatchesOnlyKnownRoot() throws {
        let temp = try TempDir()
        let home = temp.url
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
        XCTAssertEqual(candidate.projectLabel, JunkCategory.swiftPM.title)
        XCTAssertNil(rule.match(
            url: home.appendingPathComponent("Library/Caches/CocoaPods"),
            name: "CocoaPods",
            context: context(root: home, home: home)
        ))
    }

    func testSymlinkedCacheRootIsNotCandidate() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let rule = CacheRootRule(
            id: RuleID("swiftpm"),
            category: .swiftPM,
            roots: [locations.swiftPM]
        )
        let real = try temp.mkdir("real-cache")
        try temp.symlink("Library/Caches/org.swift.swiftpm", to: real)

        let result = rule.match(
            url: locations.swiftPM, name: "org.swift.swiftpm", context: context(root: home, home: home)
        )

        guard case .candidate? = result else { return }
        XCTFail("A symlinked known cache root must not be a candidate")
    }

    func testRuleCatalogHasUniqueIDsAndExpectedCategories() throws {
        let temp = try TempDir()
        let rules = RuleCatalog.rules(knownLocations: KnownLocations(home: temp.url))
        let expected: [String: JunkCategory] = [
            "node-modules": .nodeModules,
            "rust-target": .rustTarget,
            "gradle-build": .gradleAndroid,
            "gradle-cache": .gradleAndroid,
            "python": .pythonArtifacts,
            "xcode-derived-data": .xcodeDerivedData,
            "xcode-archives": .xcodeArchives,
            "xcode-device-support": .xcodeDeviceSupport,
            "swiftpm-cache": .swiftPM,
            "cocoapods-cache": .cocoapods,
            "npm-caches": .npmCaches,
        ]

        XCTAssertEqual(rules.count, expected.count)
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
        for rule in rules {
            XCTAssertEqual(
                Optional(rule.category),
                expected[rule.id.rawValue],
                "Unexpected category for \(rule.id.rawValue)"
            )
        }
    }
}
