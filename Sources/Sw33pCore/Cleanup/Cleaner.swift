import Foundation

public struct Cleaner: Sendable {
    private let trash: any TrashClient
    private let remover: any FileRemover
    private let runner: any CommandRunner
    private let validator: CleanupValidator

    public init(
        trash: any TrashClient = FileManagerTrashClient(),
        remover: any FileRemover = FileManagerRemover(),
        runner: any CommandRunner = ProcessCommandRunner(),
        validator: CleanupValidator
    ) {
        self.trash = trash
        self.remover = remover
        self.runner = runner
        self.validator = validator
    }

    public func cleanup(
        _ plan: CleanupPlan,
        scanRoot: URL,
        shouldCancel: @Sendable () -> Bool
    ) async -> CleanupResult {
        var removedIDs = Set<String>()
        var removedURLs: [URL] = []
        var failures: [CleanupFailure] = []
        var outcomes: [CommandOutcome] = []
        var attempted: Int64 = 0
        var cancelled = false

        for item in plan.items {
            if shouldCancel() {
                cancelled = true
                break
            }
            attempted += item.allocatedBytes

            switch item.removal {
            case .managed(let action):
                do {
                    let output = try await runner.run(
                        executable: action.executable,
                        arguments: action.arguments
                    )
                    outcomes.append(CommandOutcome(
                        action: action,
                        status: output.status,
                        output: output.status == 0 ? output.stdout : output.stderr
                    ))
                    if output.status == 0 {
                        removedIDs.insert(item.id)
                    } else {
                        failures.append(CleanupFailure(
                            itemID: item.id,
                            url: item.url,
                            message: "Command exited with status \(output.status)"
                        ))
                    }
                } catch {
                    failures.append(CleanupFailure(
                        itemID: item.id,
                        url: item.url,
                        message: error.localizedDescription
                    ))
                }

            case .filesystem:
                if let validationError = validator.validate(item: item, scanRoot: scanRoot) {
                    failures.append(CleanupFailure(
                        itemID: item.id,
                        url: item.url,
                        message: String(describing: validationError)
                    ))
                    continue
                }
                var itemFailed = false
                for url in item.urls {
                    do {
                        switch plan.mode {
                        case .trash: try trash.trash(url)
                        case .permanent: try remover.remove(url)
                        }
                        removedURLs.append(url)
                    } catch {
                        itemFailed = true
                        failures.append(CleanupFailure(
                            itemID: item.id,
                            url: url,
                            message: error.localizedDescription
                        ))
                    }
                }
                if !itemFailed {
                    removedIDs.insert(item.id)
                }
            }
        }

        return CleanupResult(
            removedItemIDs: removedIDs,
            removedURLs: removedURLs,
            failures: failures,
            commandOutcomes: outcomes,
            attemptedBytes: attempted,
            cancelled: cancelled
        )
    }
}
