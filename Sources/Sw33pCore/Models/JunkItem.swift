import Foundation

public struct ItemWarning: Hashable, Sendable, Identifiable {
    public let code: String
    public let message: String
    public var id: String { code }

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct MaintenanceAction: Hashable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let summary: String

    public init(executable: URL, arguments: [String], summary: String) {
        self.executable = executable
        self.arguments = arguments
        self.summary = summary
    }
}

public enum Removal: Hashable, Sendable {
    case filesystem
    case managed(MaintenanceAction)
}

public enum ItemValidation: Hashable, Sendable {
    case marker(URL)
    case knownRoot(URL)
    case pythonCache
    case none
}

public struct JunkItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let ruleID: RuleID
    public let category: JunkCategory
    public let urls: [URL]
    public let projectURL: URL?
    public let projectLabel: String?
    public let lastActivity: Date
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let warnings: [ItemWarning]
    public let removal: Removal
    public let validation: ItemValidation

    public var url: URL { urls[0] }
    public var isManaged: Bool {
        if case .managed = removal { return true }
        return false
    }

    public init(
        ruleID: RuleID,
        category: JunkCategory,
        urls: [URL],
        projectURL: URL?,
        projectLabel: String?,
        lastActivity: Date,
        allocatedBytes: Int64,
        fileCount: Int,
        warnings: [ItemWarning],
        removal: Removal,
        validation: ItemValidation = .none
    ) {
        precondition(!urls.isEmpty, "JunkItem needs at least one URL")
        self.ruleID = ruleID
        self.category = category
        self.urls = urls
        self.projectURL = projectURL
        self.projectLabel = projectLabel
        self.lastActivity = lastActivity
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.warnings = warnings
        self.removal = removal
        self.validation = validation
        self.id = ([ruleID.rawValue] + urls.map(\.path)).joined(separator: "|")
    }
}
