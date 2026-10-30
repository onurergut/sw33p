import Foundation

public struct DirectorySize: Hashable, Sendable {
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let unreadableCount: Int

    public init(allocatedBytes: Int64, fileCount: Int, unreadableCount: Int = 0) {
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.unreadableCount = unreadableCount
    }
}

public struct DirectorySizer: Sendable {
    public init() {}

    public func size(
        of url: URL,
        shouldCancel: @Sendable () -> Bool = { Task.isCancelled }
    ) -> DirectorySize? {
        guard let root = FileStatReader.stat(url), root.isDirectory, !root.isSymlink else {
            return DirectorySize(allocatedBytes: 0, fileCount: 0)
        }
        var seen = Set<FileIdentity>()
        var bytes: Int64 = 0
        var count = 0
        var unreadable = 0
        var stack = [url]

        while let directory = stack.popLast() {
            if shouldCancel() { return nil }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                unreadable += 1
                continue
            }
            for name in names {
                let child = directory.appendingPathComponent(name)
                guard let stat = FileStatReader.stat(child) else { continue }
                if stat.isSymlink { continue }
                if stat.isDirectory {
                    stack.append(child)
                    continue
                }
                guard stat.isRegularFile else { continue }
                let identity = FileIdentity(device: stat.device, inode: stat.inode)
                if seen.insert(identity).inserted {
                    bytes += stat.allocatedBytes
                    count += 1
                }
            }
        }
        return DirectorySize(allocatedBytes: bytes, fileCount: count, unreadableCount: unreadable)
    }

    private struct FileIdentity: Hashable {
        let device: UInt64
        let inode: UInt64
    }
}
