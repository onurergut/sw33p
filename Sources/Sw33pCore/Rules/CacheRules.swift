import Foundation

public struct CacheRootRule: JunkRule {
    public let id: RuleID
    public let category: JunkCategory
    private let roots: [URL]

    public init(id: RuleID, category: JunkCategory, roots: [URL]) {
        self.id = id
        self.category = category
        self.roots = roots
    }

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        guard MarkerCheck.realDirectory(url),
              let root = roots.first(where: { $0.standardizedPath == url.standardizedPath }) else {
            return nil
        }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: nil,
            projectLabel: category.title,
            validation: .knownRoot(root)
        ))
    }
}
