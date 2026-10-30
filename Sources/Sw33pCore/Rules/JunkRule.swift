import Foundation

public struct JunkCandidate: Hashable, Sendable {
    public let ruleID: RuleID
    public let category: JunkCategory
    public let url: URL
    public let projectURL: URL?
    public let projectLabel: String?
    public let validation: ItemValidation
    public let warnings: [ItemWarning]
    public let aggregatesPerProject: Bool

    public init(
        ruleID: RuleID,
        category: JunkCategory,
        url: URL,
        projectURL: URL?,
        projectLabel: String? = nil,
        validation: ItemValidation,
        warnings: [ItemWarning] = [],
        aggregatesPerProject: Bool = false
    ) {
        self.ruleID = ruleID
        self.category = category
        self.url = url
        self.projectURL = projectURL
        self.projectLabel = projectLabel
        self.validation = validation
        self.warnings = warnings
        self.aggregatesPerProject = aggregatesPerProject
    }
}

public enum RuleMatch: Hashable, Sendable {
    case candidate(JunkCandidate)
    case note(ScanNote)
    case skip(ScanNote)
}

public protocol JunkRule: Sendable {
    var id: RuleID { get }
    var category: JunkCategory { get }
    func match(url: URL, name: String, context: ScanContext) -> RuleMatch?
}

public enum MarkerCheck {
    public static func file(_ url: URL) -> Bool {
        FileStatReader.stat(url)?.isRegularFile == true
    }

    public static func directory(_ url: URL) -> Bool {
        FileStatReader.stat(url)?.isDirectory == true
    }

    /// A directory that is not itself a symlink. Candidate roots must pass this
    /// check so a symlink can neither be removed as junk nor redirect marker
    /// validation outside the scanned tree.
    public static func realDirectory(_ url: URL) -> Bool {
        guard let stat = FileStatReader.stat(url) else { return false }
        return stat.isDirectory && !stat.isSymlink
    }
}
