import Foundation

public struct HomebrewDetector: MaintenanceDetector {
    static let defaultCandidates = [
        URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        URL(fileURLWithPath: "/usr/local/bin/brew"),
    ]

    private let runner: any CommandRunner
    private let brewExecutable: URL?
    private let brewCandidates: [URL]

    public init(
        runner: any CommandRunner = ProcessCommandRunner(),
        brewExecutable: URL? = nil,
        brewCandidates: [URL]? = nil
    ) {
        self.runner = runner
        self.brewExecutable = brewExecutable
        self.brewCandidates = brewCandidates ?? Self.defaultCandidates
    }

    public func detect(context: ScanContext) async -> [JunkItem] {
        let brew: URL
        if let brewExecutable {
            brew = brewExecutable
        } else if let discovered = brewCandidates.first(where: isExecutableBrew) {
            brew = discovered
        } else {
            return []
        }
        guard isExecutableBrew(brew) else { return [] }

        guard let output = try? await runner.run(executable: brew, arguments: ["--cache"]),
              output.status == 0 else {
            return []
        }
        let cache = output.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .first { FileStatReader.stat($0)?.isDirectory == true }
        guard let cache,
              cache.canonicalScanURL.isDescendant(of: context.root),
              !context.overlapsExclusion(cache) else { return [] }

        let size = DirectorySizer().size(of: cache)
            ?? DirectorySize(allocatedBytes: 0, fileCount: 0)

        return [JunkItem(
            ruleID: RuleID("homebrew-cleanup"),
            category: .homebrew,
            urls: [cache],
            projectURL: nil,
            projectLabel: "Homebrew cache",
            lastActivity: FileStatReader.stat(cache)?.modified ?? Date.distantPast,
            allocatedBytes: size.allocatedBytes,
            fileCount: size.fileCount,
            warnings: [ItemWarning(
                code: "homebrew",
                message: "brew cleanup removes old downloads and outdated versions."
            )],
            removal: .managed(MaintenanceAction(
                executable: brew,
                arguments: ["cleanup"],
                summary: "brew cleanup"
            )),
            validation: .none
        )]
    }

    private func isExecutableBrew(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard FileStatReader.stat(resolved)?.isRegularFile == true else { return false }
        return FileManager.default.isExecutableFile(atPath: resolved.path)
    }
}
