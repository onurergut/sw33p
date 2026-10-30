import Foundation

public struct XcodeDerivedDataRule: JunkRule {
    public let id = RuleID("xcode-derived-data")
    public let category: JunkCategory = .xcodeDerivedData
    private let root: URL

    public init(knownLocations: KnownLocations) {
        root = knownLocations.xcodeDerivedData
    }

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        let parent = url.deletingLastPathComponent()
        guard parent.standardizedPath == root.standardizedPath,
              MarkerCheck.realDirectory(url) else {
            return nil
        }
        let info = url.appendingPathComponent("info.plist")
        guard MarkerCheck.file(info) else { return nil }

        var label: String?
        if let dictionary = NSDictionary(contentsOf: info),
           let workspace = dictionary["WorkspacePath"] as? String {
            label = (workspace as NSString).lastPathComponent
        }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: nil,
            projectLabel: label ?? "Xcode DerivedData",
            validation: .marker(info)
        ))
    }
}

public struct XcodeArchivesRule: JunkRule {
    public let id = RuleID("xcode-archives")
    public let category: JunkCategory = .xcodeArchives
    private let root: URL
    private let warning = ItemWarning(
        code: "archives",
        message: "Archives are needed to symbolicate crash logs. They cannot be rebuilt from source."
    )

    public init(knownLocations: KnownLocations) {
        root = knownLocations.xcodeArchives
    }

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        let parent = url.deletingLastPathComponent()
        guard url.pathExtension == "xcarchive",
              MarkerCheck.realDirectory(url),
              parent.deletingLastPathComponent().standardizedPath == root.standardizedPath else {
            return nil
        }
        let info = url.appendingPathComponent("Info.plist")
        guard MarkerCheck.file(info) else { return nil }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: nil,
            projectLabel: url.deletingPathExtension().lastPathComponent,
            validation: .marker(info),
            warnings: [warning]
        ))
    }
}

public struct XcodeDeviceSupportRule: JunkRule {
    public let id = RuleID("xcode-device-support")
    public let category: JunkCategory = .xcodeDeviceSupport
    private let roots: [URL]
    private let warning = ItemWarning(
        code: "device-support",
        message: "Debugging on this OS version will re-download the symbols."
    )

    public init(knownLocations: KnownLocations) {
        roots = knownLocations.xcodeDeviceSupport
    }

    /// Shared with cleanup-time revalidation so the accepted shape cannot drift.
    public static func isVersionDirectoryName(_ name: String) -> Bool {
        name.range(
            of: #"^[0-9]+(\.[0-9]+)*( \([^)]*\))?$"#,
            options: .regularExpression
        ) != nil
    }

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        let parent = url.deletingLastPathComponent()
        guard let root = roots.first(where: { $0.standardizedPath == parent.standardizedPath }),
              MarkerCheck.realDirectory(url),
              Self.isVersionDirectoryName(name) else {
            return nil
        }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: nil,
            projectLabel: root.lastPathComponent,
            validation: .versionedKnownRoot(root),
            warnings: [warning]
        ))
    }
}
