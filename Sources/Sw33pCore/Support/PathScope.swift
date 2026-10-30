import Foundation

extension URL {
    public func isDescendant(of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let ownComponents = standardizedFileURL.pathComponents
        guard ownComponents.count >= rootComponents.count else { return false }
        return Array(ownComponents.prefix(rootComponents.count)) == rootComponents
    }

    public var standardizedPath: String {
        standardizedFileURL.path
    }
}
