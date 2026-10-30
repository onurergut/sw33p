import XCTest
@testable import Sw33pCore

final class DirectorySizerTests: XCTestCase {
    func testCountsAllocatedBytesAndRegularFiles() throws {
        let dir = try TempDir()
        try dir.write("a.bin", bytes: 8192)
        try dir.write("sub/b.bin", bytes: 4096)

        let size = DirectorySizer().size(of: dir.url)

        XCTAssertEqual(size?.fileCount, 2)
        XCTAssertGreaterThanOrEqual(size?.allocatedBytes ?? 0, 12288)
    }

    func testHardLinksAreCountedOnce() throws {
        let dir = try TempDir()
        let original = try dir.write("a.bin", bytes: 8192)
        try dir.mkdir("sub")
        try FileManager.default.linkItem(
            at: original,
            to: dir.url.appendingPathComponent("sub/b.bin")
        )

        let size = DirectorySizer().size(of: dir.url)

        XCTAssertEqual(size?.fileCount, 1)
        XCTAssertGreaterThanOrEqual(size?.allocatedBytes ?? 0, 8192)
    }

    func testSymlinksAreNotFollowedOrCounted() throws {
        let dir = try TempDir()
        let target = try dir.write("target.bin", bytes: 4096)
        let folder = try dir.mkdir("folder")
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("link.bin"),
            withDestinationURL: target
        )

        let size = DirectorySizer().size(of: folder)

        XCTAssertEqual(size?.fileCount, 0)
        XCTAssertEqual(size?.allocatedBytes, 0)
    }

    func testCancellationReturnsNil() throws {
        let dir = try TempDir()
        try dir.write("a.bin", bytes: 4096)

        let size = DirectorySizer().size(of: dir.url, shouldCancel: { true })

        XCTAssertNil(size)
    }
}
