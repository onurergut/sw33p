import Foundation

@MainActor
enum Formatting {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        return formatter
    }()

    static func size(_ value: Int64) -> String {
        bytes.string(fromByteCount: value)
    }

    static func age(_ date: Date, now: Date = Date()) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        if days == 0 { return "today" }
        if days == 1 { return "1 day" }
        if days < 60 { return "\(days) days" }
        if days < 730 { return "\(days / 30) months" }
        return "\(days / 365) years"
    }
}
