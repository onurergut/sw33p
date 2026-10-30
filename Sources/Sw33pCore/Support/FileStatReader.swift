import Darwin
import Foundation

public struct FileStat: Sendable, Hashable {
    public let mode: mode_t
    public let modified: Date
    public let blocks: Int64
    public let device: UInt64
    public let inode: UInt64

    public var isDirectory: Bool { (mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) }
    public var isRegularFile: Bool { (mode & mode_t(S_IFMT)) == mode_t(S_IFREG) }
    public var isSymlink: Bool { (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) }
    public var allocatedBytes: Int64 { blocks * 512 }
}

public enum FileStatReader {
    public static func stat(_ url: URL) -> FileStat? {
        var info = Darwin.stat()
        let result = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return lstat(pointer, &info)
        }
        guard result == 0 else { return nil }
        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        let nanos = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileStat(
            mode: info.st_mode,
            modified: Date(timeIntervalSince1970: seconds + nanos),
            blocks: Int64(info.st_blocks),
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }
}
