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

    func testAllocatedBytesIgnoreSparseLogicalSize() throws {
        let dir = try TempDir()
        let url = try dir.write("sparse.bin", bytes: 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 10 * 1024 * 1024)
        try handle.close()

        let size = DirectorySizer().size(of: dir.url)

        XCTAssertEqual(size?.fileCount, 1)
        XCTAssertLessThan(size?.allocatedBytes ?? .max, 5 * 1024 * 1024)
    }

    func testDirectorySymlinksAreNotFollowed() throws {
        let dir = try TempDir()
        let outside = try TempDir()
        try outside.write("big.bin", bytes: 8192)
        let folder = try dir.mkdir("folder")
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("link"),
            withDestinationURL: outside.url
        )

        let size = DirectorySizer().size(of: folder)

        XCTAssertEqual(size?.fileCount, 0)
        XCTAssertEqual(size?.allocatedBytes, 0)
    }

    func testSelfReferentialSymlinkLoopTerminates() throws {
        let dir = try TempDir()
        let loop = dir.url.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)

        let size = DirectorySizer().size(of: dir.url)

        XCTAssertEqual(size?.fileCount, 0)
        XCTAssertEqual(size?.allocatedBytes, 0)
    }

    func testSymlinkRootReportsZero() throws {
        let dir = try TempDir()
        try dir.write("target/inside.bin", bytes: 4096)
        let target = dir.url.appendingPathComponent("target", isDirectory: true)
        let link = dir.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let size = DirectorySizer().size(of: link)

        XCTAssertEqual(size?.fileCount, 0)
        XCTAssertEqual(size?.allocatedBytes, 0)
    }

    func testUnreadableSubdirectoryIsReported() throws {
        let dir = try TempDir()
        let locked = try dir.mkdir("locked")
        try dir.write("locked/inside.bin", bytes: 4096)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path
            )
        }

        let size = DirectorySizer().size(of: dir.url)

        XCTAssertGreaterThanOrEqual(size?.unreadableCount ?? 0, 1)
    }
}
