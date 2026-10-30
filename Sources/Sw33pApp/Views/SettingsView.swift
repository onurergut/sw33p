import AppKit
import SwiftUI
import Sw33pCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Scan root") {
                HStack {
                    Text(model.scanRoot.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") { model.chooseScanRoot() }
                        .disabled(model.isScanning || model.isCleaning)
                }
            }

            Section("Never scan or delete") {
                if model.userExclusions.isEmpty {
                    Text("No extra exclusions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.userExclusions, id: \.self) { url in
                    HStack {
                        Text(url.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove") { model.removeExclusion(url) }
                    }
                }
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        model.addExclusion(url)
                    }
                }
            }

            Section {
                Text("sw33p always skips caches it cannot prove are reproducible, symbolic links, the Trash, iCloud Drive, Photos libraries, and app containers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
