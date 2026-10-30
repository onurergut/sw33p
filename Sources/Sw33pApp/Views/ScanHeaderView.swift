import SwiftUI
import Sw33pCore

struct ScanHeaderView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.chooseScanRoot()
            } label: {
                Label(model.scanRoot.path, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.bordered)
            .disabled(model.isScanning || model.isCleaning)
            .help("Choose the folder to scan")

            Spacer()

            Picker("Age", selection: $model.ageFilter) {
                ForEach(AgeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if model.isScanning {
                Button("Cancel") { model.cancelScan() }
            } else {
                Button("Scan") { model.startScan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isCleaning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            if model.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .offset(y: 1)
            }
        }
    }
}
