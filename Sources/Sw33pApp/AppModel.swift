import AppKit
import Foundation
import Observation
import Sw33pCore

struct VisibleCategoryGroup: Identifiable {
    let category: JunkCategory
    let items: [JunkItem]
    var id: JunkCategory { category }
}

@MainActor
@Observable
final class AppModel {
    var scanRoot: URL
    var userExclusions: [URL]
    var results: ScanResults
    var ageFilter: AgeFilter {
        didSet {
            preferences.ageFilter = ageFilter
            selectedIDs.formIntersection(Set(visibleItems.map(\.id)))
        }
    }
    var selectedCategory: JunkCategory?
    var selectedIDs: Set<String> = []
    var isScanning = false
    var progress = ScanProgress.zero
    var notes: [ScanNote] = []
    var issues: [ScanIssue] = []
    var scanSummary: ScanSummary?
    var pendingPlan: CleanupPlan?
    var cleanupMessage: String?
    var errorMessage: String?
    var isCleaning = false

    @ObservationIgnored private var preferences: Preferences
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(
        results: ScanResults = ScanResults(items: []),
        preferences: Preferences = Preferences()
    ) {
        self.preferences = preferences
        self.results = results
        self.scanRoot = preferences.scanRoot
        self.userExclusions = preferences.userExclusions
        self.ageFilter = preferences.ageFilter
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

    /// Human-readable aggregate for the "left alone" notes emitted by scans.
    var noteSummaries: [String] {
        notes.map(Self.presentedNote)
    }

    var combinedNoteSummary: String {
        noteSummaries.joined(separator: " · ")
    }

    /// A compact, non-modal headline for unreadable folders.
    var issueSummary: String? {
        guard !issues.isEmpty else { return nil }
        let noun = issues.count == 1 ? "folder" : "folders"
        return "\(issues.count) \(noun) could not be read — Full Disk Access may help"
    }

    var hasStatusDetails: Bool {
        !notes.isEmpty || !issues.isEmpty
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
        cancelScan()
        scanGeneration += 1
        let generation = scanGeneration

        isScanning = true
        progress = .zero
        notes = []
        issues = []
        scanSummary = nil
        errorMessage = nil
        results = ScanResults(items: [])
        selectedIDs = []
        preferences.scanRoot = scanRoot

        let root = scanRoot.resolvingSymlinksInPath()
        let locations = KnownLocations(home: home)
        let exclusions = allExclusions
        let configuration = ScanConfiguration(
            root: root,
            exclusions: exclusions,
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

        scanTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.scanGeneration == generation {
                    self.isScanning = false
                    self.scanTask = nil
                }
            }
            do {
                for try await event in ScanEngine(configuration: configuration).scan() {
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
                self.errorMessage = self.describe(error)
            }
        }
    }

    func cancelScan() {
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func toggleSelection(_ item: JunkItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAllVisible() {
        selectedIDs.formUnion(visibleItems.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func presentCleanupSummary() {
        guard !selectedItems.isEmpty else { return }
        pendingPlan = CleanupPlanner().plan(items: selectedItems, mode: .trash)
    }

    func confirmCleanup(mode: CleanupMode) async {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        isCleaning = true
        let cleaner = Cleaner(
            validator: CleanupValidator(knownLocations: KnownLocations(home: home))
        )
        let result = await cleaner.cleanup(
            CleanupPlan(items: plan.items, mode: mode),
            scanRoot: scanRoot.resolvingSymlinksInPath(),
            shouldCancel: { Task.isCancelled }
        )
        let removed = result.removedItemIDs
        let removedFilesystem = plan.items.filter {
            !$0.isManaged && removed.contains($0.id)
        }.count
        let removedManaged = removed.count - removedFilesystem
        results.items.removeAll { removed.contains($0.id) }
        selectedIDs.subtract(removed)
        isCleaning = false

        var parts: [String] = []
        if removedFilesystem > 0 {
            if mode == .trash {
                parts.append("Moved \(removedFilesystem) items to the Trash.")
            } else {
                parts.append("Deleted \(removedFilesystem) items permanently.")
            }
        }
        if removedManaged > 0 {
            parts.append("Completed \(removedManaged) maintenance tasks.")
        }
        if removedFilesystem > 0 {
            parts.append("Reported sizes are allocated sizes; APFS clones may reduce the real recovery.")
        }
        if mode == .trash && removedFilesystem > 0 {
            parts.append("Empty the Trash to free disk space.")
        }
        if !result.failures.isEmpty {
            parts.append("\(result.failures.count) items could not be removed.")
        }
        if result.cancelled {
            parts.append("Cleanup was cancelled.")
        }
        cleanupMessage = parts.joined(separator: " ")
    }

    func addExclusion(_ url: URL) {
        let exclusion = url.standardizedFileURL
        guard !userExclusions.contains(where: {
            $0.standardizedFileURL == exclusion
        }) else { return }
        userExclusions.append(exclusion)
        preferences.userExclusions = userExclusions

        // Existing results must honor a newly added exclusion too, otherwise
        // "Never scan or delete" would only apply to future scans.
        let hidden = Set(results.items.filter { item in
            item.urls.contains { Self.isDescendant($0, of: exclusion) }
        }.map(\.id))
        results.items.removeAll { hidden.contains($0.id) }
        selectedIDs.subtract(hidden)
    }

    private static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        guard candidateComponents.count >= ancestorComponents.count else { return false }
        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    func removeExclusion(_ url: URL) {
        userExclusions.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        preferences.userExclusions = userExclusions
    }

    func chooseScanRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = scanRoot
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            scanRoot = url
            preferences.scanRoot = url
        }
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
