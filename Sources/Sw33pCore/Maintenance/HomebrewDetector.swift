import Foundation

public struct HomebrewDetector: MaintenanceDetector {
    private let runner: any CommandRunner
    private let brewExecutable: URL?
    private let candidates = [
        URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        URL(fileURLWithPath: "/usr/local/bin/brew"),
    ]

    public init(runner: any CommandRunner = ProcessCommandRunner(), brewExecutable: URL? = nil) {
        self.runner = runner
        self.brewExecutable = brewExecutable
    }

    public func detect(context: ScanContext) async -> [JunkItem] {
        guard let brew = brewExecutable ?? candidates.first(where: {
            FileStatReader.stat($0) != nil
        }), FileStatReader.stat(brew) != nil else {
            return []
        }
        guard let output = try? await runner.run(executable: brew, arguments: ["--cache"]),
              output.status == 0,
              let path = output.stdout
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }) else {
            return []
        }
        let cache = URL(fileURLWithPath: path).standardizedFileURL
        guard FileStatReader.stat(cache)?.isDirectory == true else { return [] }
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
}
