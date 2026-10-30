import SwiftUI
import Sw33pCore

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                ScanHeaderView(model: model)
                if model.hasStatusDetails {
                    Divider()
                    ScanStatusBanner(model: model)
                }
                Divider()
                Group {
                    if model.isScanning && model.results.items.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(model.progress.currentPath ?? "Scanning…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 520)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.visibleItems.isEmpty {
                        EmptyStateView(
                            isScanning: model.isScanning,
                            hasScanned: model.hasScanned,
                            cancelled: model.scanSummary?.cancelled == true,
                            hasResults: !model.results.items.isEmpty,
                            rootPath: model.scanRoot.path
                        )
                    } else {
                        ResultsList(model: model)
                    }
                }
                Divider()
                CleanupBar(model: model)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(item: $model.pendingPlan) { plan in
            CleanupSummaryView(model: model, plan: plan)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct ScanStatusBanner: View {
    let model: AppModel
    @State private var showingIssues = false
    @State private var showingNotes = false

    var body: some View {
        HStack(spacing: 12) {
            if let scanStatusMessage = model.scanStatusMessage {
                Label(scanStatusMessage, systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
            }

            if let issueSummary = model.issueSummary {
                Button {
                    showingIssues.toggle()
                } label: {
                    Label(issueSummary, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(issueSummary)
                .accessibilityHint("Shows folders sw33p could not read")
                .help("Show folders that could not be read")
                .popover(isPresented: $showingIssues, arrowEdge: .bottom) {
                    issueList
                }
            }

            if !model.noteSummaries.isEmpty {
                Button {
                    showingNotes.toggle()
                } label: {
                    Label(model.combinedNoteSummary, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan notes")
                .accessibilityHint("Shows folders sw33p left alone")
                .help("Show folders sw33p left alone")
                .popover(isPresented: $showingNotes, arrowEdge: .bottom) {
                    notesList
                }
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
    }

    private var issueList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.issueSummary ?? "Unreadable folders")
                .font(.headline)
            Text("sw33p does not list folders it cannot inspect. Full Disk Access in System Settings can let it read more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.issues) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "folder.badge.questionmark")
                                .foregroundStyle(.secondary)
                            Text(issue.url.path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .help(issue.url.path)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)

            HStack {
                Spacer()
                Button("Close") { showingIssues = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 460)
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Left alone")
                .font(.headline)
            Text("sw33p did not list these folders because it could not prove they are disposable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.notes) { note in
                        Text(AppModel.presentedNote(note))
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)

            HStack {
                Spacer()
                Button("Close") { showingNotes = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 460)
    }
}

private struct EmptyStateView: View {
    let isScanning: Bool
    let hasScanned: Bool
    let cancelled: Bool
    let hasResults: Bool
    let rootPath: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: imageName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageName: String {
        if cancelled { return "stop.circle" }
        if hasResults { return "line.3.horizontal.decrease.circle" }
        return "sparkles"
    }

    private var title: String {
        if isScanning { return "Scanning…" }
        if hasResults { return "Nothing matches this filter" }
        if cancelled { return "Scan cancelled" }
        if hasScanned { return "No junk found" }
        return "Nothing scanned yet"
    }

    private var message: String {
        if hasResults { return "Lower the age filter or choose another category." }
        if cancelled {
            return "No junk was found before the scan stopped. Partial results are kept."
        }
        if hasScanned {
            return "No junk found in \(rootPath). sw33p lists only folders it can prove are disposable."
        }
        return "Choose a folder and press Scan. sw33p finds only folders it can prove are disposable."
    }
}
