import Foundation

public struct ScanEngine: Sendable {
    private let configuration: ScanConfiguration

    public init(configuration: ScanConfiguration) {
        self.configuration = configuration
    }

    public func scan() -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    try await self.run { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(yield: @escaping @Sendable (ScanEvent) -> Void) async throws {
        let root = configuration.root.resolvingSymlinksInPath().standardizedFileURL
        guard let rootStat = FileStatReader.stat(root) else {
            throw ScanError.rootNotFound(configuration.root)
        }
        guard rootStat.isDirectory else {
            throw ScanError.rootIsNotDirectory(configuration.root)
        }
        if FileStatReader.stat(configuration.root)?.isSymlink == true {
            throw ScanError.rootIsSymlink(configuration.root)
        }

        let context = ScanContext(
            root: root,
            knownLocations: configuration.knownLocations,
            exclusions: DefaultExclusions.urls(home: configuration.knownLocations.home)
                + configuration.exclusions
        )
        let state = WalkState(configuration: configuration, context: context, root: root)
        state.scanRoot(yield: yield)

        if state.cancelled {
            yield(.finished(state.summary(cancelled: true)))
            return
        }

        for note in state.aggregatedNotes() {
            yield(.note(note))
        }

        for detector in configuration.detectors {
            if configuration.shouldCancel() {
                state.cancelled = true
                break
            }
            for item in await detector.detect(context: context) {
                state.add(item)
                yield(.discovered(item))
            }
        }

        let summary = state.summary(cancelled: state.cancelled)
        yield(.finished(summary))
    }
}

private final class WalkState {
    private struct SizedCandidate {
        let candidate: JunkCandidate
        let size: DirectorySize
        let directoryModified: Date
    }

    private struct Activity {
        let root: URL
        let fallback: Date
        var newest: Date?
        var candidates: [SizedCandidate]

        mutating func see(_ date: Date) {
            newest = max(newest ?? date, date)
        }

        var lastActivity: Date { newest ?? fallback }
    }

    let configuration: ScanConfiguration
    let context: ScanContext
    let root: URL
    var cancelled = false
    private var items: [JunkItem] = []
    private var issueCount = 0
    private var visited = 0
    private var totalBytes: Int64 = 0
    private var notes: [String: ScanNote] = [:]
    private var lastProgress = ContinuousClock.now
    private let started = Date()

    init(configuration: ScanConfiguration, context: ScanContext, root: URL) {
        self.configuration = configuration
        self.context = context
        self.root = root
    }

    func scanRoot(yield: @escaping @Sendable (ScanEvent) -> Void) {
        var activities: [Activity] = []
        walk(root, activities: &activities, yield: yield)
    }

    private func walk(
        _ directory: URL,
        activities: inout [Activity],
        yield: @escaping @Sendable (ScanEvent) -> Void
    ) {
        if cancelled || configuration.shouldCancel() {
            cancelled = true
            return
        }
        guard let directoryStat = FileStatReader.stat(directory),
              directoryStat.isDirectory,
              !directoryStat.isSymlink else { return }

        visited += 1
        let frameIndex = activities.count
        activities.append(Activity(
            root: directory,
            fallback: directoryStat.modified,
            newest: nil,
            candidates: []
        ))

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            issueCount += 1
            yield(.issue(ScanIssue(
                url: directory,
                message: "Could not read this folder. Full Disk Access may help."
            )))
            let activity = activities.remove(at: frameIndex)
            close(activity, yield: yield)
            return
        }

        for name in names {
            if cancelled || configuration.shouldCancel() {
                cancelled = true
                return
            }
            let url = directory.appendingPathComponent(name)
            guard let stat = FileStatReader.stat(url) else { continue }
            if stat.isSymlink { continue }
            if name == ".git" || context.isExcluded(url) { continue }

            if stat.isDirectory {
                if let match = match(url: url, name: name) {
                    switch match {
                    case .candidate(let candidate):
                        guard let size = DirectorySizer().size(
                            of: url,
                            shouldCancel: configuration.shouldCancel
                        ) else {
                            cancelled = true
                            return
                        }
                        issueCount += size.unreadableCount
                        let sized = SizedCandidate(
                            candidate: candidate,
                            size: size,
                            directoryModified: stat.modified
                        )
                        if let project = candidate.projectURL,
                           let index = activities.lastIndex(where: {
                               $0.root.standardizedFileURL == project.standardizedFileURL
                           }) {
                            activities[index].candidates.append(sized)
                        } else {
                            emit(sized, lastActivity: stat.modified, yield: yield)
                        }
                    case .note(let note):
                        add(note)
                    case .skip(let note):
                        add(note)
                    }
                } else if configuration.knownLocations.shouldDescend(into: url) {
                    walk(url, activities: &activities, yield: yield)
                }
            } else if stat.isRegularFile {
                for index in activities.indices {
                    activities[index].see(stat.modified)
                }
            }
        }

        let activity = activities.remove(at: frameIndex)
        close(activity, yield: yield)
        emitProgress(currentPath: directory.path, yield: yield)
    }

    private func match(url: URL, name: String) -> RuleMatch? {
        for rule in configuration.rules {
            if let match = rule.match(url: url, name: name, context: context) {
                return match
            }
        }
        return nil
    }

    private func close(
        _ activity: Activity,
        yield: @escaping @Sendable (ScanEvent) -> Void
    ) {
        guard !cancelled else { return }
        var merged: [String: (candidate: JunkCandidate, bytes: Int64, count: Int, urls: [URL])] = [:]
        var singles: [SizedCandidate] = []

        for sized in activity.candidates {
            guard sized.candidate.aggregatesPerProject else {
                singles.append(sized)
                continue
            }
            let key = sized.candidate.ruleID.rawValue
            var entry = merged[key] ?? (
                candidate: sized.candidate,
                bytes: 0,
                count: 0,
                urls: []
            )
            entry.bytes += sized.size.allocatedBytes
            entry.count += sized.size.fileCount
            entry.urls.append(sized.candidate.url)
            merged[key] = entry
        }

        for sized in singles {
            emit(sized, lastActivity: activity.lastActivity, yield: yield)
        }
        for entry in merged.values {
            let item = makeItem(
                candidate: entry.candidate,
                urls: entry.urls,
                bytes: entry.bytes,
                count: entry.count,
                lastActivity: activity.lastActivity
            )
            items.append(item)
            totalBytes += item.allocatedBytes
            yield(.discovered(item))
            yield(.progress(progress(currentPath: item.url.path)))
        }
    }

    private func emit(
        _ sized: SizedCandidate,
        lastActivity: Date,
        yield: @escaping @Sendable (ScanEvent) -> Void
    ) {
        let item = makeItem(
            candidate: sized.candidate,
            urls: [sized.candidate.url],
            bytes: sized.size.allocatedBytes,
            count: sized.size.fileCount,
            lastActivity: lastActivity
        )
        items.append(item)
        totalBytes += item.allocatedBytes
        yield(.discovered(item))
        yield(.progress(progress(currentPath: item.url.path)))
    }

    private func makeItem(
        candidate: JunkCandidate,
        urls: [URL],
        bytes: Int64,
        count: Int,
        lastActivity: Date
    ) -> JunkItem {
        JunkItem(
            ruleID: candidate.ruleID,
            category: candidate.category,
            urls: urls,
            projectURL: candidate.projectURL,
            projectLabel: candidate.projectLabel
                ?? candidate.projectURL?.lastPathComponent
                ?? "Global cache",
            lastActivity: lastActivity,
            allocatedBytes: bytes,
            fileCount: count,
            warnings: candidate.warnings,
            removal: .filesystem,
            validation: candidate.validation
        )
    }

    func add(_ item: JunkItem) {
        items.append(item)
        totalBytes += item.allocatedBytes
    }

    private func add(_ note: ScanNote) {
        let key = note.id
        if var existing = notes[key] {
            existing = ScanNote(ruleID: note.ruleID, message: note.message, count: existing.count + note.count)
            notes[key] = existing
        } else {
            notes[key] = note
        }
    }

    func aggregatedNotes() -> [ScanNote] {
        notes.values.sorted { $0.message < $1.message }
    }

    private func progress(currentPath: String?) -> ScanProgress {
        ScanProgress(
            directoriesVisited: visited,
            bytesFound: totalBytes,
            itemsFound: items.count,
            currentPath: currentPath
        )
    }

    private func emitProgress(
        currentPath: String?,
        yield: @escaping @Sendable (ScanEvent) -> Void
    ) {
        let now = ContinuousClock.now
        if lastProgress.duration(to: now) >= configuration.progressInterval {
            lastProgress = now
            yield(.progress(progress(currentPath: currentPath)))
        }
    }

    func summary(cancelled: Bool) -> ScanSummary {
        ScanSummary(
            itemCount: items.count,
            totalBytes: totalBytes,
            directoriesVisited: visited,
            unreadableCount: issueCount,
            cancelled: cancelled,
            elapsed: Date().timeIntervalSince(started)
        )
    }
}
