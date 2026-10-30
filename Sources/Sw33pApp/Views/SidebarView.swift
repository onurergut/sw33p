import SwiftUI
import Sw33pCore

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selectedCategory) {
            row(
                title: "All",
                systemImage: "square.grid.2x2",
                bytes: model.categoryTotals.values.reduce(0, +),
                tag: nil
            )
            Section("Projects") {
                ForEach(JunkCategory.allCases.filter { $0.group == .projectArtifacts }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: category
                    )
                }
            }
            Section("Xcode") {
                ForEach(JunkCategory.allCases.filter { $0.group == .xcode }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: category
                    )
                }
            }
            Section("Caches") {
                ForEach(JunkCategory.allCases.filter { $0.group == .caches }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: category
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("sw33p")
    }

    private func row(
        title: String,
        systemImage: String,
        bytes: Int64,
        tag: JunkCategory?
    ) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if bytes > 0 {
                    Text(Formatting.size(bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .tag(tag)
    }
}
