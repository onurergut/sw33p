import Foundation

public struct Cleaner: Sendable {
    private let trash: any TrashClient
    private let remover: any FileRemover
    private let runner: any CommandRunner
    private let validator: CleanupValidator

    /// Internal test hook; not part of the public API.
    var beforeDeletion: (@Sendable (URL) -> Void)?

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
        self.beforeDeletion = nil
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

        itemLoop: for item in plan.items {
            if isCancelled(shouldCancel) {
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
                    if isCancelled(shouldCancel) {
                        cancelled = true
                        break itemLoop
                    }
                    failures.append(CleanupFailure(
                        itemID: item.id,
                        url: item.url,
                        message: error.localizedDescription
                    ))
                }

            case .filesystem:
                let receipt: CleanupValidationReceipt
                switch validator.inspect(item: item, scanRoot: scanRoot) {
                case .failure(let error):
                    failures.append(CleanupFailure(
                        itemID: item.id,
                        url: error.url,
                        message: String(describing: error)
                    ))
                    continue
                case .success(let value):
                    receipt = value
                }

                var itemFailed = false
                for url in item.urls {
                    if isCancelled(shouldCancel) {
                        cancelled = true
                        break
                    }

                    beforeDeletion?(url)

                    // Validation is repeated immediately before each deletion,
                    // but path-based filesystem APIs are not atomic with these
                    // checks. A value can still be swapped between the last
                    // lstat and trashItem/removeItem. This narrows the TOCTOU
                    // window; it does not eliminate it. Closing it completely
                    // would require deleting relative to an open directory
                    // descriptor.
                    guard validator.receiptIsCurrent(receipt, for: url) else {
                        itemFailed = true
                        let error = CleanupValidationError.changed(url)
                        failures.append(CleanupFailure(
                            itemID: item.id,
                            url: url,
                            message: String(describing: error)
                        ))
                        continue
                    }

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

                if cancelled {
                    break itemLoop
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

    private func isCancelled(_ shouldCancel: @Sendable () -> Bool) -> Bool {
        Task.isCancelled || shouldCancel()
    }
}
