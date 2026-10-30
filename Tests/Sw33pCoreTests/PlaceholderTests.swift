import XCTest
@testable import Sw33pCore

final class PlaceholderTests: XCTestCase {
    func testCoreBuilds() {
        XCTAssertEqual(Sw33pVersion.current, "0.1.0")
    }
}
