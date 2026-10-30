import Darwin
import Foundation

public enum CleanupValidationError: Error, Hashable, Sendable {
    case missing(URL)
    case notDirectory(URL)
    case symlink(URL)
    case outsideRoot(URL)
    case markerMissing(URL)
    case markerNotRegular(URL)
    case markerOutsideRoot(URL)
    case markerSymlink(URL)
    case unknownRoot(URL)
    case notPythonCache(URL)
    case notVersionDirectory(URL)
    case notDirectChild(URL)
    case invalidPath(URL)
    case noValidation(URL)
    case changed(URL)

    /// The path that caused the failure, so multi-URL items are attributed
    /// correctly instead of always reporting `item.urls[0]`.
    public var url: URL {
        switch self {
        case .missing(let url), .notDirectory(let url), .symlink(let url),
             .outsideRoot(let url), .markerMissing(let url), .markerNotRegular(let url),
             .markerOutsideRoot(let url), .markerSymlink(let url), .unknownRoot(let url),
             .notPythonCache(let url), .notVersionDirectory(let url), .notDirectChild(let url),
             .invalidPath(let url), .noValidation(let url), .changed(let url):
            return url
        }
    }
}

public struct PathIdentity: Hashable, Sendable {
    public let path: String
    public let device: UInt64
    public let inode: UInt64
    public let mode: mode_t

    public init(path: String, device: UInt64, inode: UInt64, mode: mode_t) {
        self.path = path
        self.device = device
        self.inode = inode
        self.mode = mode
    }

    public init?(url: URL) {
        guard let stat = FileStatReader.stat(url) else { return nil }
        self.init(
            path: url.standardizedFileURL.path,
            device: stat.device,
            inode: stat.inode,
            mode: stat.mode
        )
    }

    var isRegularFile: Bool {
        (mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    var isSymlink: Bool {
        (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }
}

public struct CleanupURLReceipt: Hashable, Sendable {
    public let url: URL
    /// Scan root, every intermediate directory, and the target's parent.
    public let ancestors: [PathIdentity]
    public let target: PathIdentity
    public let marker: PathIdentity?

    public init(
        url: URL,
        ancestors: [PathIdentity],
        target: PathIdentity,
        marker: PathIdentity?
    ) {
        self.url = url
        self.ancestors = ancestors
        self.target = target
        self.marker = marker
    }
}

public struct CleanupValidationReceipt: Hashable, Sendable {
    public let itemID: String
    public let urls: [CleanupURLReceipt]

    public init(itemID: String, urls: [CleanupURLReceipt]) {
        self.itemID = itemID
        self.urls = urls
    }

    public func receipt(for url: URL) -> CleanupURLReceipt? {
        let path = url.standardizedFileURL.path
        return urls.first { $0.url.standardizedFileURL.path == path }
    }
}

public struct CleanupValidator: Sendable {
    private let knownLocations: KnownLocations

    public init(knownLocations: KnownLocations) {
        self.knownLocations = knownLocations
    }

    public func validate(item: JunkItem, scanRoot: URL) -> CleanupValidationError? {
        switch inspect(item: item, scanRoot: scanRoot) {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }

    public func inspect(
        item: JunkItem,
        scanRoot: URL
    ) -> Result<CleanupValidationReceipt, CleanupValidationError> {
        if case .managed = item.removal {
            return .success(CleanupValidationReceipt(itemID: item.id, urls: []))
        }
        let root = scanRoot.canonicalScanURL
        var receipts: [CleanupURLReceipt] = []
        for url in item.urls {
            switch inspectOne(url: url, validation: item.validation, scanRoot: root) {
            case .success(let receipt):
                receipts.append(receipt)
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(CleanupValidationReceipt(itemID: item.id, urls: receipts))
    }

    /// Cheap TOCTOU mitigation: every ancestor identity and the target/marker
    /// identity captured by `inspect` must still be present. This does not make
    /// the later deletion atomic; it only narrows the window.
    public func receiptIsCurrent(_ receipt: CleanupValidationReceipt) -> Bool {
        receipt.urls.allSatisfy(entryIsCurrent)
    }

    /// Per-URL variant for multi-URL items. Checking the whole receipt would
    /// fail after the first URL was successfully removed.
    public func receiptIsCurrent(
        _ receipt: CleanupValidationReceipt,
        for url: URL
    ) -> Bool {
        guard let entry = receipt.receipt(for: url) else { return false }
        return entryIsCurrent(entry)
    }

    private func entryIsCurrent(_ entry: CleanupURLReceipt) -> Bool {
        for ancestor in entry.ancestors where !identityIsCurrent(ancestor) {
            return false
        }
        guard identityIsCurrent(entry.target) else { return false }
        if let marker = entry.marker {
            guard identityIsCurrent(marker), marker.isRegularFile, !marker.isSymlink else {
                return false
            }
        }
        return true
    }

    private func inspectOne(
        url: URL,
        validation: ItemValidation,
        scanRoot: URL
    ) -> Result<CleanupURLReceipt, CleanupValidationError> {
        // Reject ".." and "." before any standardization. A path such as
        // root/link/../target can pass lexical containment while the kernel
        // resolves link first and escapes the root.
        guard !hasTraversalComponents(url) else {
            return .failure(.invalidPath(url))
        }

        // Never resolve the candidate. Standardization only removes "." and
        // ".."; symlinks are found component by component in `identityChain`.
        let target = url.standardizedFileURL
        guard let stat = FileStatReader.stat(target) else {
            return .failure(.missing(target))
        }
        guard target.pathComponents.count > scanRoot.pathComponents.count,
              target.isDescendant(of: scanRoot) else {
            return .failure(.outsideRoot(target))
        }
        guard let chain = identityChain(from: scanRoot, to: target),
              let targetIdentity = chain.last else {
            return .failure(.symlink(target))
        }
        guard stat.isDirectory else {
            return .failure(.notDirectory(target))
        }

        var markerIdentity: PathIdentity?
        switch validation {
        case .marker(let marker):
            switch inspectMarker(marker, scanRoot: scanRoot) {
            case .success(let identity):
                markerIdentity = identity
            case .failure(let error):
                return .failure(error)
            }
        case .knownRoot(let root):
            let canonicalRoot = root.canonicalScanURL
            guard knownLocations.isCacheRoot(canonicalRoot),
                  hasSamePath(target, canonicalRoot) else {
                return .failure(.unknownRoot(root.standardizedFileURL))
            }
        case .versionedKnownRoot(let root):
            let canonicalRoot = root.canonicalScanURL
            guard knownLocations.xcodeDeviceSupport.contains(where: {
                hasSamePath($0, canonicalRoot)
            }) else {
                return .failure(.unknownRoot(root.standardizedFileURL))
            }
            guard hasSamePath(target.deletingLastPathComponent(), canonicalRoot) else {
                return .failure(.notDirectChild(target))
            }
            guard XcodeDeviceSupportRule.isVersionDirectoryName(target.lastPathComponent) else {
                return .failure(.notVersionDirectory(target))
            }
        case .pythonCache:
            guard target.lastPathComponent == "__pycache__" else {
                return .failure(.notPythonCache(target))
            }
        case .none:
            return .failure(.noValidation(target))
        }

        return .success(CleanupURLReceipt(
            url: target,
            ancestors: Array(chain.dropLast()),
            target: targetIdentity,
            marker: markerIdentity
        ))
    }

    private func inspectMarker(
        _ marker: URL,
        scanRoot: URL
    ) -> Result<PathIdentity, CleanupValidationError> {
        guard !hasTraversalComponents(marker) else {
            return .failure(.markerOutsideRoot(marker))
        }
        let target = marker.standardizedFileURL
        guard let stat = FileStatReader.stat(target) else {
            return .failure(.markerMissing(marker))
        }
        guard stat.isRegularFile, !stat.isSymlink else {
            return .failure(.markerNotRegular(marker))
        }
        guard target.pathComponents.count > scanRoot.pathComponents.count,
              target.isDescendant(of: scanRoot) else {
            return .failure(.markerOutsideRoot(marker))
        }
        guard let chain = identityChain(from: scanRoot, to: target),
              let identity = chain.last else {
            return .failure(.markerSymlink(target))
        }
        return .success(identity)
    }

    private func identityChain(from root: URL, to url: URL) -> [PathIdentity]? {
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        guard urlComponents.count > rootComponents.count,
              let rootIdentity = PathIdentity(url: root) else {
            return nil
        }
        var chain = [rootIdentity]
        var current = root
        for component in urlComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            guard let identity = PathIdentity(url: current), !identity.isSymlink else {
                return nil
            }
            chain.append(identity)
        }
        return chain
    }

    private func identityIsCurrent(_ expected: PathIdentity) -> Bool {
        guard let current = PathIdentity(url: URL(fileURLWithPath: expected.path)) else {
            return false
        }
        return current.device == expected.device
            && current.inode == expected.inode
            && current.mode == expected.mode
    }

    private func hasTraversalComponents(_ url: URL) -> Bool {
        let components = url.pathComponents
        return components.contains("..") || components.contains(".")
    }

    /// Compares components so a directory URL with a trailing slash matches the
    /// same path without one. Neither side is symlink-resolved here.
    private func hasSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.pathComponents == rhs.standardizedFileURL.pathComponents
    }
}
