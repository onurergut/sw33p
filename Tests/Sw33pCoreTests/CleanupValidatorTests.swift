import Foundation
import XCTest
@testable import Sw33pCore

final class CleanupValidatorTests: XCTestCase {
    private func item(
        url: URL,
        validation: ItemValidation,
        removal: Removal = .filesystem,
        projectURL: URL? = nil
    ) -> JunkItem {
        item(urls: [url], validation: validation, removal: removal, projectURL: projectURL)
    }

    private func item(
        urls: [URL],
        validation: ItemValidation,
        removal: Removal = .filesystem,
        projectURL: URL? = nil
    ) -> JunkItem {
        JunkItem(
            ruleID: RuleID("test"),
            category: .nodeModules,
            urls: urls,
            projectURL: projectURL,
            projectLabel: nil,
            lastActivity: Date(),
            allocatedBytes: 1,
            fileCount: 1,
            warnings: [],
            removal: removal,
            validation: validation
        )
    }

    func testMarkerMustStillExist() throws {
        let temp = try TempDir()
        let project = try temp.mkdir("app")
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertNil(validator.validate(
            item: item(url: junk, validation: .marker(marker)),
            scanRoot: temp.url
        ))

        try FileManager.default.removeItem(at: marker)
        XCTAssertEqual(
            validator.validate(item: item(url: junk, validation: .marker(marker)), scanRoot: temp.url),
            .markerMissing(marker)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
    }

    func testSymlinkedCandidateIsRefused() throws {
        let temp = try TempDir()
        let target = try temp.mkdir("real")
        try temp.symlink("link", to: target)
        let marker = try temp.write("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        let link = temp.url.appendingPathComponent("link")

        XCTAssertEqual(
            validator.validate(item: item(url: link, validation: .marker(marker)), scanRoot: temp.url),
            .symlink(link)
        )
    }

    func testSymlinkedAncestorInsidePathIsRefused() throws {
        let temp = try TempDir()
        let real = try temp.mkdir("real")
        _ = try temp.mkdir("real/sub")
        try temp.write("package.json")
        let link = try temp.symlink("link", to: real)
        let candidate = link.appendingPathComponent("sub")
        let marker = temp.url.appendingPathComponent("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .marker(marker)),
                scanRoot: temp.url
            ),
            .symlink(candidate.standardizedFileURL)
        )
    }

    func testSymlinkedMarkerIsNotRegular() throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let real = try temp.write("real-package.json")
        let marker = try temp.symlink("app/package.json", to: real)
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: junk, validation: .marker(marker)), scanRoot: temp.url),
            .markerNotRegular(marker)
        )
    }

    func testMarkerOutsideScanRootIsRefused() throws {
        let temp = try TempDir()
        let outside = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try outside.write("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: junk, validation: .marker(marker)), scanRoot: temp.url),
            .markerOutsideRoot(marker)
        )
    }

    func testMarkerWithSymlinkedAncestorIsRefused() throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let real = try temp.mkdir("real")
        try temp.write("real/package.json")
        let link = try temp.symlink("link", to: real)
        let marker = link.appendingPathComponent("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: junk, validation: .marker(marker)), scanRoot: temp.url),
            .markerSymlink(marker.standardizedFileURL)
        )
    }

    func testOutsideRootIsRefused() throws {
        let temp = try TempDir()
        let outside = try TempDir()
        let target = try outside.mkdir("node_modules")
        let marker = try temp.write("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: target, validation: .marker(marker)), scanRoot: temp.url),
            .outsideRoot(target)
        )
    }

    func testScanRootItselfIsRefused() throws {
        let temp = try TempDir()
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: temp.url, validation: .pythonCache), scanRoot: temp.url),
            .outsideRoot(temp.url)
        )
    }

    func testDotDotThroughSymlinkEscapeIsRefused() throws {
        let temp = try TempDir()
        let outside = try TempDir()
        _ = try outside.mkdir("sub")
        let escapedTarget = try outside.mkdir("target")
        try temp.symlink("link", to: outside.url.appendingPathComponent("sub"))
        let candidate = temp.url.appendingPathComponent("link/../target")
        let marker = try temp.write("package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertTrue(FileManager.default.fileExists(atPath: escapedTarget.path))
        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .marker(marker)),
                scanRoot: temp.url
            ),
            .invalidPath(candidate)
        )
    }

    func testUnknownKnownRootIsRefused() throws {
        let temp = try TempDir()
        let root = try temp.mkdir("not-a-cache")
        let child = try temp.mkdir("not-a-cache/child")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: child, validation: .knownRoot(root)), scanRoot: temp.url),
            .unknownRoot(root)
        )
    }

    func testKnownRootMustEqualCandidate() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = locations.swiftPM
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let child = try temp.mkdir("Library/Caches/org.swift.swiftpm/child")
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertNil(validator.validate(
            item: item(url: root, validation: .knownRoot(root)),
            scanRoot: temp.url
        ))
        XCTAssertEqual(
            validator.validate(item: item(url: child, validation: .knownRoot(root)), scanRoot: temp.url),
            .unknownRoot(root)
        )
    }

    func testKnownRootRefusesXcodeRoots() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let deviceSupport = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!
        let roots = [locations.xcodeDerivedData, locations.xcodeArchives, deviceSupport]
        let validator = CleanupValidator(knownLocations: locations)

        for root in roots {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            XCTAssertTrue(locations.isKnownRoot(root), root.path)
            XCTAssertEqual(
                validator.validate(item: item(url: root, validation: .knownRoot(root)), scanRoot: temp.url),
                .unknownRoot(root.standardizedFileURL),
                root.path
            )
        }
    }

    func testVersionedKnownRootAcceptsVersionDirectory() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!
        let candidate = try temp.mkdir("Library/Developer/Xcode/iOS DeviceSupport/17.0")
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertNil(validator.validate(
            item: item(url: candidate, validation: .versionedKnownRoot(root)),
            scanRoot: temp.url
        ))
    }

    func testVersionedKnownRootRejectsUnknownRoot() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = try temp.mkdir("Library/Developer/Xcode/Other")
        let candidate = try temp.mkdir("Library/Developer/Xcode/Other/17.0")
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .versionedKnownRoot(root)),
                scanRoot: temp.url
            ),
            .unknownRoot(root.standardizedFileURL)
        )
    }

    func testVersionedKnownRootRejectsNonVersionName() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!
        let candidate = try temp.mkdir("Library/Developer/Xcode/iOS DeviceSupport/notes.1")
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .versionedKnownRoot(root)),
                scanRoot: temp.url
            ),
            .notVersionDirectory(candidate)
        )
    }

    func testVersionedKnownRootRejectsWrongParent() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!
        let candidate = try temp.mkdir("Library/Developer/Xcode/iOS DeviceSupport/17.0/17.1")
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .versionedKnownRoot(root)),
                scanRoot: temp.url
            ),
            .notDirectChild(candidate)
        )
    }

    func testVersionedKnownRootRejectsSymlinkedCandidate() throws {
        let temp = try TempDir()
        let locations = KnownLocations(home: temp.url)
        let root = locations.xcodeDeviceSupport.first {
            $0.lastPathComponent == "iOS DeviceSupport"
        }!
        let real = try temp.mkdir("real-device-support")
        let candidate = try temp.symlink(
            "Library/Developer/Xcode/iOS DeviceSupport/17.0",
            to: real
        )
        let validator = CleanupValidator(knownLocations: locations)

        XCTAssertEqual(
            validator.validate(
                item: item(url: candidate, validation: .versionedKnownRoot(root)),
                scanRoot: temp.url
            ),
            .symlink(candidate.standardizedFileURL)
        )
    }

    func testNoneValidationIsRefusedForFilesystemItems() throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertEqual(
            validator.validate(item: item(url: junk, validation: .none), scanRoot: temp.url),
            .noValidation(junk)
        )
    }

    func testNoneValidationIsAllowedForManagedItems() throws {
        let temp = try TempDir()
        let action = MaintenanceAction(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            summary: "true"
        )
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertNil(validator.validate(
            item: item(url: temp.url, validation: .none, removal: .managed(action)),
            scanRoot: temp.url
        ))
    }

    func testPythonCacheRequiresDirectoryName() throws {
        let temp = try TempDir()
        let cache = try temp.mkdir("py/src/__pycache__")
        let other = try temp.mkdir("py/src/cache")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        XCTAssertNil(validator.validate(
            item: item(url: cache, validation: .pythonCache),
            scanRoot: temp.url
        ))
        XCTAssertEqual(
            validator.validate(item: item(url: other, validation: .pythonCache), scanRoot: temp.url),
            .notPythonCache(other)
        )
    }

    func testErrorExposesFailingURLForMultiURLItem() throws {
        let temp = try TempDir()
        let first = try temp.mkdir("a/__pycache__")
        let second = temp.url.appendingPathComponent("b/__pycache__")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))

        let error = validator.validate(
            item: item(urls: [first, second], validation: .pythonCache),
            scanRoot: temp.url
        )

        XCTAssertEqual(error, .missing(second))
        XCTAssertEqual(error?.url, second)
    }

    func testReceiptDetectsAncestorSwap() throws {
        let temp = try TempDir()
        let app = try temp.mkdir("app")
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        let receipt = try validator.inspect(
            item: item(url: junk, validation: .marker(marker)),
            scanRoot: temp.url
        ).get()

        XCTAssertTrue(validator.receiptIsCurrent(receipt))

        try FileManager.default.moveItem(
            at: app,
            to: temp.url.appendingPathComponent("app-moved")
        )
        XCTAssertFalse(validator.receiptIsCurrent(receipt))
    }

    func testReceiptDetectsRemovedMarker() throws {
        let temp = try TempDir()
        let junk = try temp.mkdir("app/node_modules")
        let marker = try temp.write("app/package.json")
        let validator = CleanupValidator(knownLocations: KnownLocations(home: temp.url))
        let receipt = try validator.inspect(
            item: item(url: junk, validation: .marker(marker)),
            scanRoot: temp.url
        ).get()

        XCTAssertTrue(validator.receiptIsCurrent(receipt))
        try FileManager.default.removeItem(at: marker)
        XCTAssertFalse(validator.receiptIsCurrent(receipt))
    }
}
