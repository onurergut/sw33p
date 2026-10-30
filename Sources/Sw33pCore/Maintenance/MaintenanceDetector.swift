import Foundation

public protocol MaintenanceDetector: Sendable {
    func detect(context: ScanContext) async -> [JunkItem]
}
