import AppKit
import SwiftUI
import Sw33pCore

struct ResultsList: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            ForEach(model.visibleGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: group.category.systemImage)
                        Text(group.category.title)
                        Spacer()
                        Text(Formatting.items(group.items.count))
                        Text(Formatting.size(group.items.reduce(0) { $0 + $1.allocatedBytes }))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ item: JunkItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.selectedIDs.contains(item.id) },
                set: { isOn in
                    if isOn != model.selectedIDs.contains(item.id) {
                        model.toggleSelection(item)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(
                "Select \(item.url.lastPathComponent) in \(item.projectURL?.path ?? item.projectLabel ?? "global cache")"
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent)
                        .font(.body)
                    ForEach(item.warnings) { warning in
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(warning.message)
                            .accessibilityLabel("Warning: \(warning.message)")
                    }
                }
                Text(item.projectURL?.path ?? item.projectLabel ?? "Global cache")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.projectURL?.path ?? item.projectLabel ?? "")
            }

            Spacer(minLength: 12)

            Text(Formatting.age(item.lastActivity))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

            Text(Formatting.size(item.allocatedBytes))
                .font(.callout.monospacedDigit())
                .frame(width: 82, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(item.urls)
            }
            if let project = item.projectURL {
                Button("Exclude Project Folder") {
                    model.addExclusion(project)
                }
            }
        }
    }
}
