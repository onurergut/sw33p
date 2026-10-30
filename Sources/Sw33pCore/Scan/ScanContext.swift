import Foundation

public struct ScanContext: Sendable {
    public let root: URL
    public let knownLocations: KnownLocations
    public let exclusions: [URL]

    public init(root: URL, knownLocations: KnownLocations, exclusions: [URL]) {
        self.root = root.standardizedFileURL
        self.knownLocations = knownLocations
        self.exclusions = exclusions.map(\.standardizedFileURL)
    }

    public func isExcluded(_ url: URL) -> Bool {
        exclusions.contains { url.isDescendant(of: $0) }
    }

    public func nearestProject(above url: URL) -> URL? {
        var current = url.standardizedFileURL
        let root = self.root
        while true {
            if ProjectMarkers.isProject(current) { return current }
            if current == root { return nil }
            let parent = current.deletingLastPathComponent()
            if parent == current || !parent.isDescendant(of: root) { return nil }
            current = parent
        }
    }
}
