import XCTest
@testable import Sw33pApp
@testable import Sw33pCore

@MainActor
final class AppModelTests: XCTestCase {
    func testAgeFilterAndSelectionTotals() {
        let old = Date(timeIntervalSinceNow: -100 * 86_400)
        let fresh = Date()
        let items = [
            JunkItem(
                ruleID: RuleID("a"), category: .nodeModules,
                urls: [URL(fileURLWithPath: "/tmp/a")], projectURL: nil,
                projectLabel: nil, lastActivity: old, allocatedBytes: 100,
                fileCount: 1, warnings: [], removal: .filesystem
            ),
            JunkItem(
                ruleID: RuleID("b"), category: .rustTarget,
                urls: [URL(fileURLWithPath: "/tmp/b")], projectURL: nil,
                projectLabel: nil, lastActivity: fresh, allocatedBytes: 200,
                fileCount: 1, warnings: [], removal: .filesystem
            ),
        ]
        let model = AppModel(
            results: ScanResults(items: items),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
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
            JunkItem(
                ruleID: RuleID("a"), category: .nodeModules,
                urls: [URL(fileURLWithPath: "/tmp/a")], projectURL: nil,
                projectLabel: nil, lastActivity: old, allocatedBytes: 100,
                fileCount: 1, warnings: [], removal: .filesystem
            ),
            JunkItem(
                ruleID: RuleID("b"), category: .nodeModules,
                urls: [URL(fileURLWithPath: "/tmp/b")], projectURL: nil,
                projectLabel: nil, lastActivity: fresh, allocatedBytes: 200,
                fileCount: 1, warnings: [], removal: .filesystem
            ),
        ]
        let model = AppModel(
            results: ScanResults(items: items),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
        model.selectedIDs = Set(items.map(\.id))
        model.ageFilter = .days90

        XCTAssertEqual(model.selectedIDs.count, 1)
    }

    func testAddingExclusionRemovesMatchingResultsAndSelection() {
        let project = URL(fileURLWithPath: "/tmp/sw33p-example/project", isDirectory: true)
        let item = JunkItem(
            ruleID: RuleID("a"), category: .nodeModules,
            urls: [project.appendingPathComponent("node_modules")], projectURL: project,
            projectLabel: "project", lastActivity: Date(), allocatedBytes: 100,
            fileCount: 1, warnings: [], removal: .filesystem
        )
        let model = AppModel(
            results: ScanResults(items: [item]),
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
        model.selectedIDs = [item.id]

        model.addExclusion(project)

        XCTAssertTrue(model.results.items.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.userExclusions, [project.standardizedFileURL])
    }

    func testNotesAndIssuesArePresentedWithoutHidingThem() {
        let model = AppModel(
            preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
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
}
