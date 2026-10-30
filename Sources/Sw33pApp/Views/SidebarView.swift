import SwiftUI
import Sw33pCore

private enum SidebarSelection: Hashable {
    case all
    case category(JunkCategory)

    var category: JunkCategory? {
        switch self {
        case .all: nil
        case .category(let category): category
        }
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: selection) {
            row(
                title: "All",
                systemImage: "square.grid.2x2",
                bytes: model.categoryTotals.values.reduce(0, +),
                tag: .all
            )
            Section("Projects") {
                ForEach(JunkCategory.allCases.filter { $0.group == .projectArtifacts }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: .category(category)
                    )
                }
            }
            Section("Xcode") {
                ForEach(JunkCategory.allCases.filter { $0.group == .xcode }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: .category(category)
                    )
                }
            }
            Section("Caches") {
                ForEach(JunkCategory.allCases.filter { $0.group == .caches }, id: \.self) { category in
                    row(
                        title: category.title,
                        systemImage: category.systemImage,
                        bytes: model.categoryTotals[category] ?? 0,
                        tag: .category(category)
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("sw33p")
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { model.selectedCategory.map(SidebarSelection.category) ?? .all },
            set: { model.selectedCategory = $0?.category }
        )
    }

    private func row(
        title: String,
        systemImage: String,
        bytes: Int64,
        tag: SidebarSelection
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
