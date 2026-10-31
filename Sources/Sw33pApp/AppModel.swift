import AppKit
import Foundation
import Observation
import Sw33pCore

struct VisibleCategoryGroup: Identifiable {
    let category: JunkCategory
    let items: [JunkItem]
    var id: JunkCategory { category }
}

enum AppAlert: Identifiable, Equatable {
    case scanError(String)
    case cleanupResult(String)
    case notice(String)

    var id: String {
        switch self {
        case .scanError: "scan-error"
        case .cleanupResult: "cleanup-result"
        case .notice: "notice"
        }
    }

    var title: String {
        switch self {
        case .scanError: "Scan failed"
        case .cleanupResult: "Cleanup"
        case .notice: "sw33p"
        }
    }

    var message: String {
        switch self {
        case .scanError(let message), .cleanupResult(let message), .notice(let message):
            message
        }
    }
}

struct CleanupRequest {
    let plan: CleanupPlan
    let scanRoot: URL
    let knownLocations: KnownLocations
    let exclusions: [URL]
    let shouldCancel: @Sendable () -> Bool
}

typealias ScanProvider = @MainActor (ScanConfiguration) -> AsyncThrowingStream<ScanEvent, Error>
typealias CleanupProvider = @MainActor (CleanupRequest) async -> CleanupResult

@MainActor
@Observable
final class AppModel {
    private(set) var scanRoot: URL
    var userExclusions: [URL]
    var results: ScanResults
    var ageFilter: AgeFilter {
        didSet {
            preferences.ageFilter = ageFilter
            selectedIDs.formIntersection(Set(visibleItems.map(\.id)))
        }
    }
    var selectedCategory: JunkCategory? {
        didSet {
            selectedIDs.formIntersection(Set(visibleItems.map(\.id)))
        }
    }
    var selectedIDs: Set<String> = []
    var isScanning = false
    var progress = ScanProgress.zero
    var notes: [ScanNote] = []
    var issues: [ScanIssue] = []
    var scanSummary: ScanSummary?
    var pendingPlan: CleanupPlan?
    var alert: AppAlert?
    var isCleaning = false

    @ObservationIgnored private var preferences: Preferences
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanStartedAt: Date?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupGeneration = 0
    @ObservationIgnored private let scanProvider: ScanProvider
    @ObservationIgnored private let cleanupProvider: CleanupProvider

    init(
        results: ScanResults = ScanResults(items: []),
        preferences: Preferences = Preferences(),
        scanProvider: ScanProvider? = nil,
        cleanupProvider: CleanupProvider? = nil
    ) {
        self.preferences = preferences
        self.results = results
        self.scanRoot = preferences.scanRoot
        self.userExclusions = preferences.userExclusions
        self.ageFilter = preferences.ageFilter
        self.scanProvider = scanProvider ?? { configuration in
            ScanEngine(configuration: configuration).scan()
        }
        self.cleanupProvider = cleanupProvider ?? { request in
            let cleaner = Cleaner(
                validator: CleanupValidator(
                    knownLocations: request.knownLocations,
                    exclusions: request.exclusions
                )
            )
            return await cleaner.cleanup(
                request.plan,
                scanRoot: request.scanRoot,
                shouldCancel: request.shouldCancel
            )
        }
    }

    var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var allExclusions: [URL] {
        DefaultExclusions.urls(home: home) + userExclusions
    }

    var visibleItems: [JunkItem] {
        results.filtered(age: ageFilter, category: selectedCategory, now: Date())
    }

    var visibleGroups: [VisibleCategoryGroup] {
        let grouped = Dictionary(grouping: visibleItems, by: \.category)
        return JunkCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return VisibleCategoryGroup(
                category: category,
                items: items.sorted { $0.allocatedBytes > $1.allocatedBytes }
            )
        }
    }

    var categoryTotals: [JunkCategory: Int64] {
        results.totalsByCategory(age: ageFilter, now: Date())
    }

    var selectedItems: [JunkItem] {
        visibleItems.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedBytes }
    }

    var totalVisibleBytes: Int64 {
        visibleItems.reduce(0) { $0 + $1.allocatedBytes }
    }

    var hasScanned: Bool {
        scanSummary != nil
    }

    /// Cancellation is presented as state, never as an error.
    var scanStatusMessage: String? {
        guard !isScanning, let summary = scanSummary, summary.cancelled else {
            return nil
        }
        return "Scan cancelled — showing partial results"
    }

    var noteSummaries: [String] {
        notes.map(Self.presentedNote)
    }

    var combinedNoteSummary: String {
        noteSummaries.joined(separator: " · ")
    }

    var issueSummary: String? {
        guard !issues.isEmpty else { return nil }
        let noun = issues.count == 1 ? "folder" : "folders"
        return "\(issues.count) \(noun) could not be read — Full Disk Access may help"
    }

    var hasStatusDetails: Bool {
        !notes.isEmpty || !issues.isEmpty || scanStatusMessage != nil
    }

    static func presentedNote(_ note: ScanNote) -> String {
        if note.message == "node_modules without package.json was left alone" {
            let verb = note.count == 1 ? "folder was" : "folders were"
            return "\(note.count) node_modules \(verb) left alone (no package.json)"
        }
        if note.message.hasSuffix(" without pyvenv.cfg was left alone") {
            let name = note.message
                .replacingOccurrences(of: " without pyvenv.cfg was left alone", with: "")
            let verb = note.count == 1 ? "folder was" : "folders were"
            return "\(note.count) \(name) \(verb) left alone (no pyvenv.cfg)"
        }
        return note.count > 1 ? "\(note.count) × \(note.message)" : note.message
    }

    func startScan() {
        guard !isCleaning else {
            alert = .notice("Wait for cleanup to finish before scanning.")
            return
        }
        if isScanning {
            cancelScan()
        }
        scanGeneration += 1
        let generation = scanGeneration

        isScanning = true
        progress = .zero
        notes = []
        issues = []
        scanSummary = nil
        alert = nil
        pendingPlan = nil
        results = ScanResults(items: [])
        selectedIDs = []
        scanStartedAt = Date()
        preferences.scanRoot = scanRoot

        let locations = KnownLocations(home: home)
        let configuration = ScanConfiguration(
            root: scanRoot,
            exclusions: userExclusions,
            knownLocations: locations,
            rules: RuleCatalog.rules(knownLocations: locations),
            detectors: [
                SimulatorDetector(
                    devicesRoot: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
                ),
                HomebrewDetector(),
            ],
            shouldCancel: { Task.isCancelled }
        )
        let stream = scanProvider(configuration)

        scanTask = Task { [weak self] in
            guard let self else { return }
            var scanFailed = false
            defer {
                if self.scanGeneration == generation {
                    self.isScanning = false
                    self.scanTask = nil
                }
            }
            do {
                for try await event in stream {
                    guard self.scanGeneration == generation else { return }
                    switch event {
                    case .discovered(let item):
                        self.results.items.append(item)
                    case .progress(let value):
                        self.progress = value
                    case .issue(let issue):
                        self.issues.append(issue)
                    case .note(let note):
                        self.notes.append(note)
                    case .finished(let summary):
                        self.scanSummary = summary
                    }
                }
            } catch is CancellationError {
                // The user cancelled; cancellation is not an error.
            } catch {
                guard self.scanGeneration == generation else { return }
                scanFailed = true
                self.alert = .scanError(self.describe(error))
            }

            guard self.scanGeneration == generation else { return }
            if self.scanSummary == nil, !scanFailed {
                self.scanSummary = self.makeScanSummary(cancelled: Task.isCancelled)
            }
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        if scanSummary == nil {
            scanSummary = makeScanSummary(cancelled: true)
        }
    }

    func cancelCleanup() {
        cleanupTask?.cancel()
    }

    func setScanRoot(_ url: URL) {
        guard !isScanning, !isCleaning else { return }
        guard url.standardizedFileURL != scanRoot.standardizedFileURL else { return }
        scanRoot = url
        preferences.scanRoot = url
        results = ScanResults(items: [])
        selectedIDs = []
        notes = []
        issues = []
        scanSummary = nil
        progress = .zero
        pendingPlan = nil
        alert = nil
    }

    func toggleSelection(_ item: JunkItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func presentCleanupSummary() {
        guard !isScanning, !isCleaning, pendingPlan == nil else { return }
        let eligible = selectedItems.filter { !isExcluded($0) }
        guard !eligible.isEmpty else {
            if !selectedItems.isEmpty {
                alert = .notice("The selected items are in an excluded folder. Nothing was prepared for cleanup.")
            }
            return
        }
        pendingPlan = CleanupPlanner().plan(items: eligible, mode: .trash)
    }

    func confirmCleanup(mode: CleanupMode) async {
        guard !isScanning, !isCleaning, let plan = pendingPlan else { return }
        pendingPlan = nil

        let eligible = plan.items.filter { !isExcluded($0) }
        guard !eligible.isEmpty else {
            alert = .notice("Nothing was cleaned because every selected item is excluded.")
            return
        }

        isCleaning = true
        cleanupGeneration += 1
        let generation = cleanupGeneration
        let request = CleanupRequest(
            plan: CleanupPlan(items: eligible, mode: mode),
            scanRoot: scanRoot.resolvingSymlinksInPath(),
            knownLocations: KnownLocations(home: home),
            exclusions: userExclusions,
            shouldCancel: { Task.isCancelled }
        )

        let task = Task { [weak self] in
            guard let self else { return }
            let result = await self.cleanupProvider(request)
            guard self.cleanupGeneration == generation else { return }
            self.applyCleanupResult(result, items: eligible, mode: mode)
            self.isCleaning = false
            self.cleanupTask = nil
        }
        cleanupTask = task
        await task.value
    }

    func addExclusion(_ url: URL) {
        let exclusion = url.standardizedFileURL
        guard !userExclusions.contains(where: {
            $0.standardizedFileURL == exclusion
        }) else { return }

        let cleanupWasRunning = isCleaning
        if isScanning {
            cancelScan()
        }
        if cleanupWasRunning {
            cancelCleanup()
        }

        userExclusions.append(exclusion)
        preferences.userExclusions = userExclusions

        // Existing results must honor a newly added exclusion too, otherwise
        // "Never scan or delete" would only apply to future scans.
        let hidden = Set(results.items.filter { item in
            item.urls.contains { Self.overlaps($0, exclusion) }
        }.map(\.id))
        results.items.removeAll { hidden.contains($0.id) }
        selectedIDs.subtract(hidden)
        pendingPlan = nil
        if !hidden.isEmpty {
            scanSummary = nil
        }

        var message = "Exclusion added. Rescan to apply it to the remaining folders."
        if cleanupWasRunning {
            message = "Exclusion added. The running cleanup was cancelled. Rescan to apply the exclusion."
        }
        alert = .notice(message)
    }

    func removeExclusion(_ url: URL) {
        userExclusions.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        preferences.userExclusions = userExclusions
    }

    func chooseScanRoot() {
        guard !isScanning, !isCleaning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = scanRoot
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            setScanRoot(url)
        }
    }

    func isExcluded(_ item: JunkItem) -> Bool {
        // User exclusions always bind. Default exclusions guard the walker;
        // managed maintenance items (for example unavailable simulators under
        // CoreSimulator) are produced by dedicated, validating detectors.
        if item.urls.contains(where: { url in
            userExclusions.contains { Self.overlaps(url, $0) }
        }) {
            return true
        }
        guard !item.isManaged else { return false }
        return item.urls.contains { url in
            allExclusions.contains { Self.overlaps(url, $0) }
        }
    }

    private func applyCleanupResult(
        _ result: CleanupResult,
        items: [JunkItem],
        mode: CleanupMode
    ) {
        let removed = result.removedItemIDs
        let removedFilesystem = items.filter {
            !$0.isManaged && removed.contains($0.id)
        }.count
        let removedManaged = removed.count - removedFilesystem

        results.items.removeAll { removed.contains($0.id) }
        selectedIDs.subtract(removed)

        var parts: [String] = []
        if removedFilesystem > 0 {
            if mode == .trash {
                parts.append("Moved \(Formatting.items(removedFilesystem)) to the Trash.")
            } else {
                parts.append("Deleted \(Formatting.items(removedFilesystem)) permanently.")
            }
        }
        if removedManaged > 0 {
            parts.append("Completed \(Formatting.tasks(removedManaged)).")
        }
        if !result.commandOutcomes.isEmpty {
            parts.append(
                result.commandOutcomes
                    .map(Self.commandOutcomeLine)
                    .joined(separator: "\n")
            )
        }
        if removedFilesystem > 0 {
            parts.append("Reported sizes are allocated sizes; APFS clones may reduce the real recovery.")
        }
        if mode == .trash && removedFilesystem > 0 {
            parts.append("Empty the Trash to free disk space.")
        }
        if !result.failures.isEmpty {
            let detail = result.failures.prefix(3)
                .map { "\($0.url.path): \($0.message)" }
                .joined(separator: "\n")
            let remaining = result.failures.count - min(result.failures.count, 3)
            var failureText = "\(Formatting.items(result.failures.count)) could not be removed.\n\(detail)"
            if remaining > 0 {
                failureText += "\n…and \(remaining) more."
            }
            parts.append(failureText)
        }
        if result.cancelled {
            parts.append("Cleanup was cancelled.")
        }
        if parts.isEmpty {
            parts.append("Nothing was cleaned.")
        }
        alert = .cleanupResult(parts.joined(separator: "\n"))
    }

    private static func commandOutcomeLine(_ outcome: CommandOutcome) -> String {
        let summary = outcome.action.summary
        guard outcome.status != 0 else {
            return "\(summary): succeeded"
        }
        let detail = summarizedOutput(outcome.output)
        if detail.isEmpty {
            return "\(summary): failed (status \(outcome.status))"
        }
        return "\(summary): failed (status \(outcome.status)) — \(detail)"
    }

    private static func summarizedOutput(_ text: String, limit: Int = 240) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    private func makeScanSummary(cancelled: Bool) -> ScanSummary {
        let bytes = results.items.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        return ScanSummary(
            itemCount: results.items.count,
            totalBytes: bytes,
            directoriesVisited: progress.directoriesVisited,
            unreadableCount: issues.count,
            cancelled: cancelled,
            elapsed: Date().timeIntervalSince(scanStartedAt ?? Date())
        )
    }

    private static func overlaps(_ candidate: URL, _ exclusion: URL) -> Bool {
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let exclusionComponents = exclusion.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let count = min(candidateComponents.count, exclusionComponents.count)
        return candidateComponents.prefix(count).elementsEqual(exclusionComponents.prefix(count))
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case ScanError.rootNotFound: "That folder no longer exists."
        case ScanError.rootIsNotDirectory: "The scan root is not a folder."
        case ScanError.rootIsSymlink: "The scan root resolves through a symbolic link."
        default: error.localizedDescription
        }
    }
}
