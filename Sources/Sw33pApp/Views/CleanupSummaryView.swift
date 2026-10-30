import SwiftUI
import Sw33pCore

struct CleanupSummaryView: View {
    @Bindable var model: AppModel
    let plan: CleanupPlan
    @Environment(\.dismiss) private var dismiss
    @State private var moveToTrash = true
    @State private var confirmPermanent = false

    private var hasFilesystemItems: Bool {
        plan.items.contains { !$0.isManaged }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review cleanup")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.breakdown) { entry in
                        HStack {
                            Text(entry.category.title)
                            Spacer()
                            Text("\(entry.count) items")
                                .foregroundStyle(.secondary)
                            Text(Formatting.size(entry.bytes))
                                .monospacedDigit()
                        }
                    }

                    Divider()
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(Formatting.size(plan.totalBytes)).font(.headline.monospacedDigit())
                    }

                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    Text("Sizes are allocated sizes. Hard links are counted once; APFS clones cannot be detected, so the real recovery can be smaller.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasFilesystemItems && moveToTrash {
                        Text("Moving to Trash does not free disk space until you empty the Trash.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 260)

            if hasFilesystemItems {
                Toggle("Move to Trash", isOn: $moveToTrash)
                if !moveToTrash {
                    Label("Permanent deletion cannot be undone.", systemImage: "exclamationmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    model.pendingPlan = nil
                    dismiss()
                }
                Spacer()
                Button(moveToTrash || !hasFilesystemItems ? "Clean Up" : "Delete Permanently", role: .destructive) {
                    if hasFilesystemItems && !moveToTrash {
                        confirmPermanent = true
                    } else {
                        Task { await model.confirmCleanup(mode: .trash) }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isCleaning)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Delete permanently?", isPresented: $confirmPermanent) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task { await model.confirmCleanup(mode: .permanent) }
            }
        } message: {
            Text("This cannot be undone. The selected items will not go to the Trash.")
        }
    }

    private var warnings: [String] {
        Array(Set(plan.items.flatMap { $0.warnings.map(\.message) })).sorted()
    }
}
