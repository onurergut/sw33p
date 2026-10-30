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
        JunkItem(
            ruleID: RuleID("test"),
            category: .nodeModules,
            urls: [url],
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
            .outsideRoot(candidate)
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
}
