import Foundation

public struct ScanNote: Hashable, Sendable, Identifiable {
    public let ruleID: RuleID?
    public let message: String
    public let count: Int
    public var id: String { "\(ruleID?.rawValue ?? "note")|\(message)" }

    public init(ruleID: RuleID? = nil, message: String, count: Int) {
        self.ruleID = ruleID
        self.message = message
        self.count = count
    }
}

public struct ScanIssue: Hashable, Sendable, Identifiable {
    public let url: URL
    public let message: String
    public var id: String { "\(url.path)|\(message)" }

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct ScanProgress: Hashable, Sendable {
    public var directoriesVisited: Int
    public var bytesFound: Int64
    public var itemsFound: Int
    public var currentPath: String?

    public static let zero = ScanProgress(
        directoriesVisited: 0,
        bytesFound: 0,
        itemsFound: 0,
        currentPath: nil
    )

    public init(directoriesVisited: Int, bytesFound: Int64, itemsFound: Int, currentPath: String?) {
        self.directoriesVisited = directoriesVisited
        self.bytesFound = bytesFound
        self.itemsFound = itemsFound
        self.currentPath = currentPath
    }
}

public struct ScanSummary: Hashable, Sendable {
    public let itemCount: Int
    public let totalBytes: Int64
    public let directoriesVisited: Int
    public let unreadableCount: Int
    public let cancelled: Bool
    public let elapsed: TimeInterval

    public init(
        itemCount: Int,
        totalBytes: Int64,
        directoriesVisited: Int,
        unreadableCount: Int,
        cancelled: Bool,
        elapsed: TimeInterval
    ) {
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.directoriesVisited = directoriesVisited
        self.unreadableCount = unreadableCount
        self.cancelled = cancelled
        self.elapsed = elapsed
    }
}

public enum ScanEvent: Sendable {
    case discovered(JunkItem)
    case progress(ScanProgress)
    case issue(ScanIssue)
    case note(ScanNote)
    case finished(ScanSummary)
}

public enum ScanError: Error, Sendable, Equatable {
    case rootNotFound(URL)
    case rootIsNotDirectory(URL)
    case rootIsSymlink(URL)
}
