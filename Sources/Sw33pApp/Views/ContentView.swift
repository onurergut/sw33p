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
                            hasResults: !model.results.items.isEmpty
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
        .alert("Cleanup", isPresented: Binding(
            get: { model.cleanupMessage != nil },
            set: { if !$0 { model.cleanupMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.cleanupMessage = nil }
        } message: {
            Text(model.cleanupMessage ?? "")
        }
        .alert("Scan failed", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct ScanStatusBanner: View {
    let model: AppModel
    @State private var showingIssues = false

    var body: some View {
        HStack(spacing: 12) {
            if let issueSummary = model.issueSummary {
                Button {
                    showingIssues.toggle()
                } label: {
                    Label(issueSummary, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Show folders that could not be read")
                .popover(isPresented: $showingIssues, arrowEdge: .bottom) {
                    issueList
                }
            }

            if !model.noteSummaries.isEmpty {
                Label(model.combinedNoteSummary, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.noteSummaries.joined(separator: "\n"))
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
        .accessibilityElement(children: .combine)
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
}

private struct EmptyStateView: View {
    let isScanning: Bool
    let hasResults: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasResults ? "line.3.horizontal.decrease.circle" : "sparkles")
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

    private var title: String {
        if isScanning { return "Scanning…" }
        if hasResults { return "Nothing matches this filter" }
        return "Nothing scanned yet"
    }

    private var message: String {
        if hasResults { return "Lower the age filter or choose another category." }
        return "Choose a folder and press Scan. sw33p finds only folders it can prove are disposable."
    }
}
