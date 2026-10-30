import Foundation

public struct SimulatorDetector: MaintenanceDetector {
    private struct Output: Decodable {
        let devices: [String: [Device]]
    }

    private struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?

        var isUnavailable: Bool {
            isAvailable == false || state == "unavailable"
        }
    }

    private let devicesRoot: URL
    private let runner: any CommandRunner
    private let xcrun: URL

    public init(
        devicesRoot: URL,
        runner: any CommandRunner = ProcessCommandRunner(),
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun")
    ) {
        self.devicesRoot = devicesRoot
        self.runner = runner
        self.xcrun = xcrun
    }

    public func detect(context: ScanContext) async -> [JunkItem] {
        guard let output = try? await runner.run(
            executable: xcrun,
            arguments: ["simctl", "list", "devices", "-j"]
        ), output.status == 0 else {
            return []
        }
        guard let data = output.stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Output.self, from: data) else {
            return []
        }

        var items: [JunkItem] = []
        for (runtime, devices) in decoded.devices {
            for device in devices where device.isUnavailable {
                guard isUDID(device.udid) else { continue }
                let directory = devicesRoot.appendingPathComponent(device.udid, isDirectory: false)
                let size = DirectorySizer().size(of: directory)
                    ?? DirectorySize(allocatedBytes: 0, fileCount: 0)
                let modified = FileStatReader.stat(directory)?.modified ?? Date.distantPast
                let runtimeName = runtime
                    .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                    .replacingOccurrences(of: "-", with: " ")
                items.append(JunkItem(
                    ruleID: RuleID("unavailable-simulators"),
                    category: .simulators,
                    urls: [directory],
                    projectURL: nil,
                    projectLabel: "\(device.name) (\(runtimeName))",
                    lastActivity: modified,
                    allocatedBytes: size.allocatedBytes,
                    fileCount: size.fileCount,
                    warnings: [],
                    removal: .managed(MaintenanceAction(
                        executable: xcrun,
                        arguments: ["simctl", "delete", device.udid],
                        summary: "xcrun simctl delete \(device.udid)"
                    )),
                    validation: .none
                ))
            }
        }
        return items.sorted { ($0.projectLabel ?? "") < ($1.projectLabel ?? "") }
    }

    private func isUDID(_ value: String) -> Bool {
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
