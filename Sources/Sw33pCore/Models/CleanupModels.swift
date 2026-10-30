import Foundation

public enum CleanupMode: Hashable, Sendable {
    case trash
    case permanent
}

public struct CleanupBreakdownEntry: Identifiable, Hashable, Sendable {
    public let category: JunkCategory
    public let bytes: Int64
    public let count: Int
    public var id: JunkCategory { category }
}

public struct CleanupPlan: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let items: [JunkItem]
    public let mode: CleanupMode

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
    public var itemCount: Int { items.count }

    public var breakdown: [CleanupBreakdownEntry] {
        var bytes: [JunkCategory: Int64] = [:]
        var counts: [JunkCategory: Int] = [:]
        for item in items {
            bytes[item.category, default: 0] += item.allocatedBytes
            counts[item.category, default: 0] += 1
        }
        return JunkCategory.allCases.compactMap { category in
            guard let value = bytes[category] else { return nil }
            return CleanupBreakdownEntry(
                category: category,
                bytes: value,
                count: counts[category] ?? 0
            )
        }
    }

    public init(items: [JunkItem], mode: CleanupMode) {
        self.id = UUID()
        self.items = items
        self.mode = mode
    }
}

public struct CleanupFailure: Hashable, Sendable, Identifiable {
    public let itemID: String
    public let url: URL
    public let message: String
    public var id: String { "\(itemID)|\(url.path)" }

    public init(itemID: String, url: URL, message: String) {
        self.itemID = itemID
        self.url = url
        self.message = message
    }
}

public struct CommandOutcome: Hashable, Sendable {
    public let action: MaintenanceAction
    public let status: Int32
    public let output: String

    public init(action: MaintenanceAction, status: Int32, output: String) {
        self.action = action
        self.status = status
        self.output = output
    }
}

public struct CleanupResult: Hashable, Sendable {
    public let removedItemIDs: Set<String>
    public let removedURLs: [URL]
    public let failures: [CleanupFailure]
    public let commandOutcomes: [CommandOutcome]
    public let attemptedBytes: Int64
    public let cancelled: Bool

    public init(
        removedItemIDs: Set<String>,
        removedURLs: [URL],
        failures: [CleanupFailure],
        commandOutcomes: [CommandOutcome],
        attemptedBytes: Int64,
        cancelled: Bool
    ) {
        self.removedItemIDs = removedItemIDs
        self.removedURLs = removedURLs
        self.failures = failures
        self.commandOutcomes = commandOutcomes
        self.attemptedBytes = attemptedBytes
        self.cancelled = cancelled
    }
}
