import SwiftUI
import Sw33pCore

struct CleanupBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if !model.selectedItems.isEmpty {
                    Text("\(Formatting.items(model.selectedItems.count)) selected · \(Formatting.size(model.selectedBytes))")
                } else {
                    Text("\(Formatting.size(model.totalVisibleBytes)) found")
                }
                Text("Moving to Trash frees no space until emptied. Sizes are allocated sizes; APFS clones may reduce real recovery.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if model.isCleaning {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel Cleanup") { model.cancelCleanup() }
            } else {
                Button("Clean Up…") { model.presentCleanupSummary() }
                    .disabled(
                        model.isScanning
                            || model.selectedItems.isEmpty
                            || model.pendingPlan != nil
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
