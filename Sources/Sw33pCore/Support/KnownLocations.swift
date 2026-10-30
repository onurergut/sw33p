import Foundation

public struct KnownLocations: Sendable {
    public let home: URL
    private let depths: [URL: Int]

    private static let deviceSupportPlatforms = ["iOS", "watchOS", "tvOS", "xrOS", "visionOS"]

    private static let relativeDepths: [String: Int] = {
        var values: [String: Int] = [
            "Library/Caches/org.swift.swiftpm": 0,
            "Library/Caches/CocoaPods": 0,
            "Library/Caches/Yarn": 0,
            "Library/Caches/pnpm": 0,
            ".cache/yarn": 0,
            ".npm/_cacache": 0,
            "Library/pnpm/store": 0,
            ".pnpm-store": 0,
            "Library/Developer/Xcode/DerivedData": 1,
            "Library/Developer/Xcode/Archives": 2,
        ]
        for name in deviceSupportPlatforms {
            values["Library/Developer/Xcode/\(name) DeviceSupport"] = 1
        }
        return values
    }()

    public init(home: URL) {
        self.home = home.standardizedFileURL
        var values: [URL: Int] = [:]
        for (path, depth) in Self.relativeDepths {
            values[self.home.appendingPathComponent(path)] = depth
        }
        depths = values
    }

    private func root(_ relativePath: String) -> URL {
        home.appendingPathComponent(relativePath)
    }

    public var allRoots: [URL] { depths.keys.sorted { $0.path < $1.path } }

    public var swiftPM: URL { root("Library/Caches/org.swift.swiftpm") }
    public var cocoaPods: URL { root("Library/Caches/CocoaPods") }
    public var xcodeDerivedData: URL { root("Library/Developer/Xcode/DerivedData") }
    public var xcodeArchives: URL { root("Library/Developer/Xcode/Archives") }
    public var xcodeDeviceSupport: [URL] {
        Self.deviceSupportPlatforms.map {
            root("Library/Developer/Xcode/\($0) DeviceSupport")
        }
    }
    public var npmCacheRoots: [URL] {
        [
            ".npm/_cacache",
            "Library/Caches/Yarn",
            ".cache/yarn",
            "Library/pnpm/store",
            ".pnpm-store",
            "Library/Caches/pnpm",
        ].map(root)
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
        if let root = depths.keys.first(where: { url.standardizedPath == $0.standardizedPath }) {
            return (depths[root] ?? 0) > 0
        }
        if let root = depths.keys.first(where: { url.isDescendant(of: $0) }) {
            let depth = relativeDepth(of: url, below: root)
            return depth < (depths[root] ?? 0)
        }
        if allRoots.contains(where: { $0.isDescendant(of: url) }) {
            return true
        }
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return !url.isDescendant(of: library)
    }

    private func relativeDepth(of url: URL, below root: URL) -> Int {
        let rootCount = root.standardizedFileURL.pathComponents.count
        return max(0, url.standardizedFileURL.pathComponents.count - rootCount)
    }
}
