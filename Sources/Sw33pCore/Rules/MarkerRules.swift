import Foundation

public struct NodeModulesRule: JunkRule {
    public let id = RuleID("node-modules")
    public let category: JunkCategory = .nodeModules
    public init() {}

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        guard name == "node_modules", MarkerCheck.realDirectory(url) else { return nil }
        let project = url.deletingLastPathComponent()
        let marker = project.appendingPathComponent("package.json")
        guard MarkerCheck.file(marker) else {
            return .skip(ScanNote(
                ruleID: id,
                message: "node_modules without package.json was left alone",
                count: 1
            ))
        }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: project,
            validation: .marker(marker)
        ))
    }
}

public struct RustTargetRule: JunkRule {
    public let id = RuleID("rust-target")
    public let category: JunkCategory = .rustTarget
    public init() {}

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        guard name == "target", MarkerCheck.realDirectory(url) else { return nil }
        let project = url.deletingLastPathComponent()
        let marker = project.appendingPathComponent("Cargo.toml")
        guard MarkerCheck.file(marker) else { return nil }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: project,
            validation: .marker(marker)
        ))
    }
}

public struct GradleAndroidRule: JunkRule {
    public let id = RuleID("gradle-build")
    public let category: JunkCategory = .gradleAndroid
    public init() {}

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        guard name == "build", MarkerCheck.realDirectory(url) else { return nil }
        let project = url.deletingLastPathComponent()
        let groovy = project.appendingPathComponent("build.gradle")
        let kotlin = project.appendingPathComponent("build.gradle.kts")
        let marker = MarkerCheck.file(groovy) ? groovy : (MarkerCheck.file(kotlin) ? kotlin : nil)
        guard let marker else { return nil }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: project,
            validation: .marker(marker)
        ))
    }
}

public struct PythonArtifactsRule: JunkRule {
    public let id = RuleID("python")
    public let category: JunkCategory = .pythonArtifacts
    public init() {}

    public func match(url: URL, name: String, context: ScanContext) -> RuleMatch? {
        if name == "__pycache__" {
            guard MarkerCheck.realDirectory(url) else { return nil }
            let parent = url.deletingLastPathComponent()
            let project = context.nearestProject(above: parent)
                ?? context.pythonSourceRoot(containing: parent)
            return .candidate(JunkCandidate(
                ruleID: RuleID("python-pycache"),
                category: category,
                url: url,
                projectURL: project,
                validation: .pythonCache,
                aggregatesPerProject: true
            ))
        }

        guard name == ".venv" || name == "venv", MarkerCheck.realDirectory(url) else {
            return nil
        }
        let marker = url.appendingPathComponent("pyvenv.cfg")
        guard MarkerCheck.file(marker) else {
            return .skip(ScanNote(
                ruleID: id,
                message: "\(name) without pyvenv.cfg was left alone",
                count: 1
            ))
        }
        return .candidate(JunkCandidate(
            ruleID: id,
            category: category,
            url: url,
            projectURL: url.deletingLastPathComponent(),
            validation: .marker(marker)
        ))
    }
}
