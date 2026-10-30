import Foundation

public struct ScanConfiguration: Sendable {
    public let root: URL
    public let exclusions: [URL]
    public let knownLocations: KnownLocations
    public let rules: [any JunkRule]
    public let detectors: [any MaintenanceDetector]
    public let shouldCancel: @Sendable () -> Bool
    public let progressInterval: Duration

    public init(
        root: URL,
        exclusions: [URL],
        knownLocations: KnownLocations,
        rules: [any JunkRule],
        detectors: [any MaintenanceDetector],
        shouldCancel: @escaping @Sendable () -> Bool,
        progressInterval: Duration = .milliseconds(100)
    ) {
        self.root = root
        self.exclusions = exclusions
        self.knownLocations = knownLocations
        self.rules = rules
        self.detectors = detectors
        self.shouldCancel = shouldCancel
        self.progressInterval = progressInterval
    }
}
