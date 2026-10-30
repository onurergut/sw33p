import Foundation

public struct CleanupPlanner: Sendable {
    public init() {}

    public func plan(items: [JunkItem], mode: CleanupMode) -> CleanupPlan {
        CleanupPlan(items: items, mode: mode)
    }
}
