import Foundation

final class TempDir {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw33p-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let resolved = base.resolvingSymlinksInPath().standardizedFileURL
        url = URL(fileURLWithPath: resolved.path, isDirectory: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func mkdir(_ path: String) throws -> URL {
        let target = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    @discardableResult
    func write(_ path: String, bytes: Int = 0, modified: Date? = nil) throws -> URL {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x61, count: bytes).write(to: target)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified],
                ofItemAtPath: target.path
            )
        }
        return target
    }

    @discardableResult
    func symlink(_ path: String, to destination: URL) throws -> URL {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: destination)
        return target
    }
}
