import SwiftUI

@main
@MainActor
struct Sw33pApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("sw33p") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan") { model.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isCleaning)
                Button("Cancel Scan") { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isScanning)
                Divider()
                Button("Clean Up…") { model.presentCleanupSummary() }
                    .disabled(
                        model.isScanning
                            || model.isCleaning
                            || model.pendingPlan != nil
                            || model.selectedItems.isEmpty
                    )
                Button("Cancel Cleanup") { model.cancelCleanup() }
                    .disabled(!model.isCleaning)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 380)
        }
    }
}
