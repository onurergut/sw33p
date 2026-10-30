import Foundation

public struct KnownLocations: Sendable {
    public let home: URL
    private let depths: [URL: Int]

    public init(home: URL) {
        self.home = home.standardizedFileURL
        let home = self.home
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        let xcode = developer.appendingPathComponent("Xcode", isDirectory: true)

        var values: [(URL, Int)] = [
            (caches.appendingPathComponent("org.swift.swiftpm", isDirectory: true), 0),
            (caches.appendingPathComponent("CocoaPods", isDirectory: true), 0),
            (caches.appendingPathComponent("Yarn", isDirectory: true), 0),
            (caches.appendingPathComponent("pnpm", isDirectory: true), 0),
            (home.appendingPathComponent(".cache/yarn", isDirectory: true), 0),
            (home.appendingPathComponent(".npm/_cacache", isDirectory: true), 0),
            (home.appendingPathComponent("Library/pnpm/store", isDirectory: true), 0),
            (home.appendingPathComponent(".pnpm-store", isDirectory: true), 0),
            (xcode.appendingPathComponent("DerivedData", isDirectory: true), 1),
            (xcode.appendingPathComponent("Archives", isDirectory: true), 2),
        ]
        for name in ["iOS", "watchOS", "tvOS", "xrOS"] {
            values.append((xcode.appendingPathComponent("\(name) DeviceSupport", isDirectory: true), 1))
        }
        depths = Dictionary(uniqueKeysWithValues: values)
    }

    public var allRoots: [URL] { depths.keys.sorted { $0.path < $1.path } }

    public var swiftPM: URL { home.appendingPathComponent("Library/Caches/org.swift.swiftpm") }
    public var cocoaPods: URL { home.appendingPathComponent("Library/Caches/CocoaPods") }
    public var xcodeDerivedData: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData") }
    public var xcodeArchives: URL { home.appendingPathComponent("Library/Developer/Xcode/Archives") }
    public var xcodeDeviceSupport: [URL] {
        ["iOS", "watchOS", "tvOS", "xrOS"].map {
            home.appendingPathComponent("Library/Developer/Xcode/\($0) DeviceSupport")
        }
    }
    public var npmCacheRoots: [URL] {
        [
            home.appendingPathComponent(".npm/_cacache"),
            home.appendingPathComponent("Library/Caches/Yarn"),
            home.appendingPathComponent(".cache/yarn"),
            home.appendingPathComponent("Library/pnpm/store"),
            home.appendingPathComponent(".pnpm-store"),
            home.appendingPathComponent("Library/Caches/pnpm"),
        ]
    }

    public func contains(_ url: URL) -> Bool {
        allRoots.contains { url.isDescendant(of: $0) }
    }

    public func isKnownRoot(_ url: URL) -> Bool {
        depths.keys.contains { $0.standardizedPath == url.standardizedPath }
    }

    public func maxDepth(forRoot url: URL) -> Int? {
        depths.first { $0.key.standardizedPath == url.standardizedPath }?.value
    }

    public func shouldDescend(into url: URL) -> Bool {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        guard url.isDescendant(of: library) else { return true }
        if let root = depths.keys.first(where: { url.standardizedPath == $0.standardizedPath }) {
            return (depths[root] ?? 0) > 0
        }
        if let root = depths.keys.first(where: { url.isDescendant(of: $0) }) {
            let depth = relativeDepth(of: url, below: root)
            return depth < (depths[root] ?? 0)
        }
        return allRoots.contains { $0.isDescendant(of: url) }
    }

    private func relativeDepth(of url: URL, below root: URL) -> Int {
        let rootCount = root.standardizedFileURL.pathComponents.count
        return max(0, url.standardizedFileURL.pathComponents.count - rootCount)
    }
}
