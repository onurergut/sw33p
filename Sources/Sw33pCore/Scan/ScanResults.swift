import Foundation

public struct ScanResults: Hashable, Sendable {
    public var items: [JunkItem]

    public init(items: [JunkItem]) {
        self.items = items
    }

    public func filtered(age: AgeFilter, category: JunkCategory?, now: Date) -> [JunkItem] {
        let cutoff = age == .any ? nil : now.addingTimeInterval(-Double(age.rawValue) * 86_400)
        return items.filter { item in
            if let category, item.category != category { return false }
            if let cutoff, item.lastActivity > cutoff { return false }
            return true
        }
    }

    public func totalBytes(age: AgeFilter, category: JunkCategory?, now: Date) -> Int64 {
        filtered(age: age, category: category, now: now).reduce(0) { $0 + $1.allocatedBytes }
    }

    public func totalsByCategory(age: AgeFilter, now: Date) -> [JunkCategory: Int64] {
        var totals: [JunkCategory: Int64] = [:]
        for item in filtered(age: age, category: nil, now: now) {
            totals[item.category, default: 0] += item.allocatedBytes
        }
        return totals
    }
}
