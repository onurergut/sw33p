import XCTest
@testable import Sw33pCore

final class KnownLocationsTests: XCTestCase {
    func testKnownCacheRootIsRecognizedAndOutsideIsNot() throws {
        let home = try TempDir().url
        let locations = KnownLocations(home: home)
        let swiftPM = home.appendingPathComponent("Library/Caches/org.swift.swiftpm")
        let other = home.appendingPathComponent("Library/Caches/com.example.other")

        XCTAssertTrue(locations.contains(swiftPM))
        XCTAssertTrue(locations.isKnownRoot(swiftPM))
        XCTAssertFalse(locations.contains(other))
    }

    func testContainsIsComponentBasedNotStringPrefix() throws {
        let home = try TempDir().url
        let locations = KnownLocations(home: home)
        let tricky = home.appendingPathComponent("Library/Caches/CocoaPodsExtra")

        XCTAssertFalse(locations.contains(tricky))
    }

    func testDepthLimitsKeepXcodeSubtreeShallow() throws {
        let home = try TempDir().url
        let locations = KnownLocations(home: home)
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let project = derived.appendingPathComponent("App-hash")
        let deep = project.appendingPathComponent("Build")

        XCTAssertTrue(locations.shouldDescend(into: derived))
        XCTAssertFalse(locations.shouldDescend(into: project))
        XCTAssertFalse(locations.shouldDescend(into: deep))
    }
}
