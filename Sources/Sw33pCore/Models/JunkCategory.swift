import Foundation

public enum CategoryGroup: String, CaseIterable, Sendable, Hashable {
    case projectArtifacts
    case xcode
    case caches
}

public enum JunkCategory: String, CaseIterable, Sendable, Hashable, Codable {
    case nodeModules
    case rustTarget
    case pythonArtifacts
    case gradleAndroid
    case xcodeDerivedData
    case xcodeArchives
    case xcodeDeviceSupport
    case simulators
    case swiftPM
    case cocoapods
    case npmCaches
    case homebrew

    public var title: String {
        switch self {
        case .nodeModules: "node_modules"
        case .rustTarget: "Rust target"
        case .pythonArtifacts: "Python"
        case .gradleAndroid: "Gradle / Android"
        case .xcodeDerivedData: "DerivedData"
        case .xcodeArchives: "Archives"
        case .xcodeDeviceSupport: "DeviceSupport"
        case .simulators: "Unavailable simulators"
        case .swiftPM: "SwiftPM cache"
        case .cocoapods: "CocoaPods cache"
        case .npmCaches: "npm / yarn / pnpm"
        case .homebrew: "Homebrew"
        }
    }

    public var group: CategoryGroup {
        switch self {
        case .nodeModules, .rustTarget, .pythonArtifacts, .gradleAndroid:
            .projectArtifacts
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport, .simulators:
            .xcode
        case .swiftPM, .cocoapods, .npmCaches, .homebrew:
            .caches
        }
    }

    public var systemImage: String {
        switch self {
        case .nodeModules: "shippingbox"
        case .rustTarget: "gearshape.2"
        case .pythonArtifacts: "chevron.left.forwardslash.chevron.right"
        case .gradleAndroid: "hammer"
        case .xcodeDerivedData: "hammer.circle"
        case .xcodeArchives: "archivebox"
        case .xcodeDeviceSupport: "iphone"
        case .simulators: "simcard"
        case .swiftPM: "swift"
        case .cocoapods: "leaf"
        case .npmCaches: "tray.full"
        case .homebrew: "mug"
        }
    }
}

public struct RuleID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum AgeFilter: Int, CaseIterable, Sendable, Identifiable {
    case any = 0
    case days30 = 30
    case days90 = 90
    case days180 = 180
    case days365 = 365

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .any: "Any age"
        case .days30: "30+ days"
        case .days90: "90+ days"
        case .days180: "180+ days"
        case .days365: "365+ days"
        }
    }
}
