import Foundation

public struct KnownLocations: Sendable {
    public let home: URL

    private let roots: [Root]
    private let rootURLs: [URL]
    private let urlsByRelativePath: [String: URL]
    private let depthByPath: [String: Int]
    private let libraryComponents: [String]

    private struct Root: Sendable {
        let url: URL
        let components: [String]
        let depth: Int
    }

    private static let deviceSupportPlatforms = ["iOS", "watchOS", "tvOS", "xrOS", "visionOS"]

    private static let relativeDepths: [(path: String, depth: Int)] = [
        ("Library/Caches/org.swift.swiftpm", 0),
        ("Library/Caches/CocoaPods", 0),
        ("Library/Caches/Yarn", 0),
        ("Library/Caches/pnpm", 0),
        (".cache/yarn", 0),
        (".npm/_cacache", 0),
        ("Library/pnpm/store", 0),
        (".pnpm-store", 0),
        ("Library/Developer/Xcode/DerivedData", 1),
        ("Library/Developer/Xcode/Archives", 2),
    ]

    public init(home: URL) {
        let canonicalHome = home.canonicalScanURL
        self.home = canonicalHome

        var roots: [Root] = []
        var urlsByRelativePath: [String: URL] = [:]
        var depths: [String: Int] = [:]

        func add(root relativePath: String, depth: Int) {
            let url = canonicalHome.appendingPathComponent(relativePath).canonicalScanURL
            urlsByRelativePath[relativePath] = url
            let path = url.path
            guard depths[path] == nil else { return }
            depths[path] = depth
            roots.append(Root(url: url, components: url.pathComponents, depth: depth))
        }

        for entry in Self.relativeDepths {
            add(root: entry.path, depth: entry.depth)
        }
        for platform in Self.deviceSupportPlatforms {
            add(root: "Library/Developer/Xcode/\(platform) DeviceSupport", depth: 1)
        }

        self.roots = roots
        self.rootURLs = roots.map(\.url).sorted { $0.path < $1.path }
        self.urlsByRelativePath = urlsByRelativePath
        self.depthByPath = depths
        self.libraryComponents = canonicalHome.appendingPathComponent("Library").pathComponents
    }

    public var allRoots: [URL] { rootURLs }

    public var swiftPM: URL { url("Library/Caches/org.swift.swiftpm") }
    public var cocoaPods: URL { url("Library/Caches/CocoaPods") }
    public var xcodeDerivedData: URL { url("Library/Developer/Xcode/DerivedData") }
    public var xcodeArchives: URL { url("Library/Developer/Xcode/Archives") }
    public var xcodeDeviceSupport: [URL] {
        Self.deviceSupportPlatforms.map {
            url("Library/Developer/Xcode/\($0) DeviceSupport")
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
        ].map(url)
    }

    private func url(_ relativePath: String) -> URL {
        urlsByRelativePath[relativePath]
            ?? home.appendingPathComponent(relativePath).canonicalScanURL
    }

    public func contains(_ url: URL) -> Bool {
        let components = url.canonicalScanURL.pathComponents
        return roots.contains { Self.hasPrefix(components, $0.components) }
    }

    public func isKnownRoot(_ url: URL) -> Bool {
        depthByPath[url.canonicalScanURL.path] != nil
    }

    public func maxDepth(forRoot url: URL) -> Int? {
        depthByPath[url.canonicalScanURL.path]
    }

    public func shouldDescend(into url: URL) -> Bool {
        shouldDescend(components: url.canonicalScanURL.pathComponents)
    }

    func shouldDescend(components: [String]) -> Bool {
        for root in roots where components == root.components {
            return root.depth > 0
        }
        for root in roots where Self.hasPrefix(components, root.components) {
            let relativeDepth = components.count - root.components.count
            return relativeDepth < root.depth
        }
        for root in roots where Self.hasPrefix(root.components, components) {
            return true
        }
        if Self.hasPrefix(components, libraryComponents) {
            return false
        }
        return true
    }

    private static func hasPrefix(_ components: [String], _ prefix: [String]) -> Bool {
        components.count >= prefix.count && components.prefix(prefix.count).elementsEqual(prefix)
    }
}
