import Foundation

public enum RuleCatalog {
    public static func rules(knownLocations: KnownLocations) -> [any JunkRule] {
        [
            NodeModulesRule(),
            RustTargetRule(),
            GradleAndroidRule(),
            PythonArtifactsRule(),
            XcodeDerivedDataRule(knownLocations: knownLocations),
            XcodeArchivesRule(knownLocations: knownLocations),
            XcodeDeviceSupportRule(knownLocations: knownLocations),
            CacheRootRule(
                id: RuleID("swiftpm-cache"),
                category: .swiftPM,
                roots: [knownLocations.swiftPM]
            ),
            CacheRootRule(
                id: RuleID("cocoapods-cache"),
                category: .cocoapods,
                roots: [knownLocations.cocoaPods]
            ),
            CacheRootRule(
                id: RuleID("gradle-cache"),
                category: .gradleAndroid,
                roots: [knownLocations.gradleCache]
            ),
            CacheRootRule(
                id: RuleID("npm-caches"),
                category: .npmCaches,
                roots: knownLocations.npmCacheRoots
            ),
        ]
    }
}
