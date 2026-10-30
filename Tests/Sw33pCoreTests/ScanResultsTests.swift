import XCTest
@testable import Sw33pCore

final class ScanResultsTests: XCTestCase {
    private func item(
        _ path: String,
        category: JunkCategory,
        daysAgo: Int,
        bytes: Int64
    ) -> JunkItem {
        JunkItem(
            ruleID: RuleID("test"),
            category: category,
            urls: [URL(fileURLWithPath: path)],
            projectURL: URL(fileURLWithPath: path).deletingLastPathComponent(),
            projectLabel: nil,
            lastActivity: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400),
            allocatedBytes: bytes,
            fileCount: 1,
            warnings: [],
            removal: .filesystem
        )
    }

    func testAgeFilterDayBoundaries() {
        let results = ScanResults(items: [
            item("/a/fresh", category: .nodeModules, daysAgo: 10, bytes: 10),
            item("/a/old", category: .nodeModules, daysAgo: 100, bytes: 20),
        ])

        let visible = results.filtered(age: .days90, category: nil, now: Date())
        XCTAssertEqual(visible.map(\.allocatedBytes), [20])
    }

    func testTotalsRespectCategoryAndAge() {
        let results = ScanResults(items: [
            item("/a/x", category: .nodeModules, daysAgo: 100, bytes: 20),
            item("/a/y", category: .rustTarget, daysAgo: 100, bytes: 30),
            item("/a/z", category: .nodeModules, daysAgo: 1, bytes: 40),
        ])

        XCTAssertEqual(results.totalBytes(age: .days90, category: .nodeModules, now: Date()), 20)
        XCTAssertEqual(results.totalBytes(age: .any, category: nil, now: Date()), 90)
    }
}
