import Foundation

public protocol TrashClient: Sendable {
    func trash(_ url: URL) throws
}

public struct FileManagerTrashClient: TrashClient {
    public init() {}

    public func trash(_ url: URL) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }
}

public protocol FileRemover: Sendable {
    func remove(_ url: URL) throws
}

public struct FileManagerRemover: FileRemover {
    public init() {}

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
