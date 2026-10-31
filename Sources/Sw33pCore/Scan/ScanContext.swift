import Foundation

public struct ScanContext: Sendable {
    public let root: URL
    public let knownLocations: KnownLocations
    public let exclusions: [URL]

    private let exclusionComponents: [[String]]

    public init(root: URL, knownLocations: KnownLocations, exclusions: [URL]) {
        let canonicalRoot = root.canonicalScanURL
        let canonicalExclusions = exclusions.map(\.canonicalScanURL)
        self.root = canonicalRoot
        self.knownLocations = knownLocations
        self.exclusions = canonicalExclusions
        self.exclusionComponents = canonicalExclusions.map(\.pathComponents)
    }

    public func isExcluded(_ url: URL) -> Bool {
        isExcluded(components: url.canonicalScanURL.pathComponents)
    }

    func isExcluded(components: [String]) -> Bool {
        exclusionComponents.contains { exclusion in
            components.count >= exclusion.count
                && components.prefix(exclusion.count).elementsEqual(exclusion)
        }
    }

    /// Protect an excluded folder even when cleanup would remove its parent.
    public func overlapsExclusion(_ url: URL) -> Bool {
        let components = url.canonicalScanURL.pathComponents
        return exclusionComponents.contains { exclusion in
            (components.count >= exclusion.count
                && components.prefix(exclusion.count).elementsEqual(exclusion))
                || (exclusion.count >= components.count
                    && exclusion.prefix(components.count).elementsEqual(components))
        }
    }

    public func nearestProject(above url: URL) -> URL? {
        var current = url.standardizedFileURL
        let root = self.root
        while true {
            if ProjectMarkers.isProject(current) { return current }
            if current.standardizedPath == root.standardizedPath { return nil }
            let parent = current.deletingLastPathComponent()
            if parent == current || !parent.isDescendant(of: root) { return nil }
            current = parent
        }
    }
}
