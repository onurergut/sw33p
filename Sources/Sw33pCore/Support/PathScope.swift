import Foundation

extension URL {
    /// Resolves symlinks once and drops the directory flag so identical paths
    /// compare equally whether or not the target currently exists.
    var canonicalScanURL: URL {
        let resolved = resolvingSymlinksInPath().standardizedFileURL
        return URL(fileURLWithPath: resolved.path, isDirectory: false)
    }

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
