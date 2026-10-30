import Foundation

public struct SimulatorDetector: MaintenanceDetector {
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
              let payload = try? JSONSerialization.jsonObject(with: data),
              let root = payload as? [String: Any],
              let runtimes = root["devices"] as? [String: Any] else {
            return []
        }

        var items: [JunkItem] = []
        var seenUDIDs = Set<String>()
        for (runtime, rawDevices) in runtimes {
            guard let devices = rawDevices as? [Any] else { continue }
            for entry in devices {
                guard let device = entry as? [String: Any],
                      let udid = device["udid"] as? String,
                      let name = device["name"] as? String,
                      let state = device["state"] as? String else {
                    continue
                }
                let isAvailable = device["isAvailable"] as? Bool
                let isUnavailable = isAvailable.map { !$0 } ?? (state == "unavailable")
                guard isUnavailable, isUDID(udid), seenUDIDs.insert(udid).inserted else {
                    continue
                }

                let directory = devicesRoot.appendingPathComponent(udid, isDirectory: false)
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
                    projectLabel: "\(name) (\(runtimeName))",
                    lastActivity: modified,
                    allocatedBytes: size.allocatedBytes,
                    fileCount: size.fileCount,
                    warnings: [],
                    removal: .managed(MaintenanceAction(
                        executable: xcrun,
                        arguments: ["simctl", "delete", udid],
                        summary: "xcrun simctl delete \(udid)"
                    )),
                    validation: .none
                ))
            }
        }
        return items.sorted { left, right in
            let leftLabel = left.projectLabel ?? ""
            let rightLabel = right.projectLabel ?? ""
            if leftLabel != rightLabel { return leftLabel < rightLabel }
            return left.url.lastPathComponent < right.url.lastPathComponent
        }
    }

    private func isUDID(_ value: String) -> Bool {
        let groups = [8, 4, 4, 4, 12]
        let bytes = value.utf8
        guard bytes.count == 36 else { return false }
        var index = bytes.startIndex
        for (offset, group) in groups.enumerated() {
            if offset > 0 {
                guard bytes[index] == UInt8(ascii: "-") else { return false }
                index = bytes.index(after: index)
            }
            for _ in 0..<group {
                guard index < bytes.endIndex, isHexDigit(bytes[index]) else { return false }
                index = bytes.index(after: index)
            }
        }
        return index == bytes.endIndex
    }

    private func isHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 70)
            || (byte >= 97 && byte <= 102)
    }
}
