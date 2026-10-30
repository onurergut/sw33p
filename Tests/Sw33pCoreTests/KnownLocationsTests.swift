import XCTest
@testable import Sw33pCore

final class KnownLocationsTests: XCTestCase {
    func testKnownCacheRootIsRecognizedAndOutsideIsNot() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let swiftPM = home.appendingPathComponent("Library/Caches/org.swift.swiftpm")
        let other = home.appendingPathComponent("Library/Caches/com.example.other")

        XCTAssertTrue(locations.contains(swiftPM))
        XCTAssertTrue(locations.isKnownRoot(swiftPM))
        XCTAssertFalse(locations.contains(other))
    }

    func testContainsIsComponentBasedNotStringPrefix() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let tricky = home.appendingPathComponent("Library/Caches/CocoaPodsExtra")

        XCTAssertFalse(locations.contains(tricky))
    }

    func testDepthLimitsKeepXcodeSubtreeShallow() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let project = derived.appendingPathComponent("App-hash")
        let deep = project.appendingPathComponent("Build")

        XCTAssertTrue(locations.shouldDescend(into: derived))
        XCTAssertFalse(locations.shouldDescend(into: project))
        XCTAssertFalse(locations.shouldDescend(into: deep))
    }

    func testDepthZeroRootsOutsideLibraryAreNotDescendedInto() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)

        for path in [".npm/_cacache", ".cache/yarn", ".pnpm-store"] {
            let root = home.appendingPathComponent(path)
            XCTAssertFalse(locations.shouldDescend(into: root), path)
            XCTAssertFalse(
                locations.shouldDescend(into: root.appendingPathComponent("inside")),
                path
            )
        }
    }

    func testArchivesDepthAllowsTwoLevels() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let archives = home.appendingPathComponent("Library/Developer/Xcode/Archives")
        let dated = archives.appendingPathComponent("2024-01-01")

        XCTAssertTrue(locations.shouldDescend(into: archives))
        XCTAssertTrue(locations.shouldDescend(into: dated))
        XCTAssertFalse(locations.shouldDescend(into: dated.appendingPathComponent("MyApp.xcarchive")))
    }

    func testDeviceSupportDepthAllowsOneLevel() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let support = home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")

        XCTAssertTrue(locations.shouldDescend(into: support))
        XCTAssertFalse(locations.shouldDescend(into: support.appendingPathComponent("17.0")))
        XCTAssertEqual(locations.xcodeDeviceSupport.count, 5)
        XCTAssertTrue(
            locations.xcodeDeviceSupport.contains {
                $0.path.hasSuffix("visionOS DeviceSupport")
            }
        )
    }

    func testAncestorOfKnownRootIsDescendedInto() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)

        XCTAssertTrue(locations.shouldDescend(into: home.appendingPathComponent("Library/Developer")))
        XCTAssertTrue(locations.shouldDescend(into: home.appendingPathComponent("Library/Developer/Xcode")))
        XCTAssertTrue(locations.shouldDescend(into: home.appendingPathComponent("Library/Caches")))
        XCTAssertTrue(locations.shouldDescend(into: home.appendingPathComponent(".npm")))
    }

    func testUnrelatedLibraryAndOutsidePaths() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)

        XCTAssertFalse(locations.shouldDescend(into: home.appendingPathComponent("Library/Application Support")))
        XCTAssertTrue(locations.shouldDescend(into: home.appendingPathComponent("Documents")))
    }

    func testEveryExposedRootIsConsistent() throws {
        let temp = try TempDir()
        let home = temp.url
        let locations = KnownLocations(home: home)
        let roots =
            locations.allRoots
            + [locations.swiftPM, locations.cocoaPods, locations.xcodeDerivedData, locations.xcodeArchives]
            + locations.xcodeDeviceSupport
            + locations.npmCacheRoots

        XCTAssertFalse(roots.isEmpty)
        for root in roots {
            XCTAssertTrue(locations.contains(root), root.path)
            XCTAssertTrue(locations.isKnownRoot(root), root.path)
            XCTAssertNotNil(locations.maxDepth(forRoot: root), root.path)
        }
    }
}
