import Foundation

public enum CleanupValidationError: Error, Hashable, Sendable {
    case missing(URL)
    case notDirectory(URL)
    case symlink(URL)
    case outsideRoot(URL)
    case markerMissing(URL)
    case markerNotRegular(URL)
    case unknownRoot(URL)
    case notPythonCache(URL)
    case notVersionDirectory(URL)
    case noValidation(URL)
}

public struct CleanupValidator: Sendable {
    private let knownLocations: KnownLocations

    public init(knownLocations: KnownLocations) {
        self.knownLocations = knownLocations
    }

    public func validate(item: JunkItem, scanRoot: URL) -> CleanupValidationError? {
        if case .managed = item.removal { return nil }
        let root = scanRoot.canonicalScanURL
        for url in item.urls {
            if let error = validateOne(url: url, validation: item.validation, scanRoot: root) {
                return error
            }
        }
        return nil
    }

    private func validateOne(
        url: URL,
        validation: ItemValidation,
        scanRoot: URL
    ) -> CleanupValidationError? {
        // Never resolve the candidate. Standardization only removes "." and "..";
        // symlinks are found component by component below.
        let target = url.standardizedFileURL
        guard let stat = FileStatReader.stat(target) else { return .missing(target) }
        guard target.pathComponents.count > scanRoot.pathComponents.count,
              target.isDescendant(of: scanRoot) else {
            return .outsideRoot(target)
        }
        if hasSymlinkComponent(from: scanRoot, to: target) {
            return .symlink(target)
        }
        guard stat.isDirectory else {
            return .notDirectory(target)
        }

        switch validation {
        case .marker(let marker):
            guard let markerStat = FileStatReader.stat(marker) else {
                return .markerMissing(marker)
            }
            guard markerStat.isRegularFile, !markerStat.isSymlink else {
                return .markerNotRegular(marker)
            }
        case .knownRoot(let root):
            let canonicalRoot = root.canonicalScanURL
            guard knownLocations.isKnownRoot(canonicalRoot),
                  hasSamePath(target, canonicalRoot) else {
                return .unknownRoot(root.standardizedFileURL)
            }
        case .versionedKnownRoot(let root):
            let canonicalRoot = root.canonicalScanURL
            guard knownLocations.xcodeDeviceSupport.contains(where: {
                hasSamePath($0, canonicalRoot)
            }) else {
                return .unknownRoot(root.standardizedFileURL)
            }
            guard hasSamePath(target.deletingLastPathComponent(), canonicalRoot) else {
                return .outsideRoot(target)
            }
            guard XcodeDeviceSupportRule.isVersionDirectoryName(target.lastPathComponent) else {
                return .notVersionDirectory(target)
            }
        case .pythonCache:
            guard target.lastPathComponent == "__pycache__" else {
                return .notPythonCache(target)
            }
        case .none:
            return .noValidation(target)
        }
        return nil
    }

    /// Compares components so a directory URL with a trailing slash matches the
    /// same path without one. Neither side is symlink-resolved here.
    private func hasSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.pathComponents == rhs.standardizedFileURL.pathComponents
    }

    private func hasSymlinkComponent(from root: URL, to url: URL) -> Bool {
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        guard urlComponents.count > rootComponents.count else { return true }
        var current = root
        for component in urlComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            guard let stat = FileStatReader.stat(current) else { return true }
            if stat.isSymlink { return true }
        }
        return false
    }
}
