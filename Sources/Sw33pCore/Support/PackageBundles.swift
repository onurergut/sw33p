import Foundation

/// Directories that macOS treats as a single item. Their contents ship with an
/// app or extension and are not rebuildable, even when they contain a
/// `node_modules` next to a `package.json`.
public enum PackageBundles {
    static let extensions: Set<String> = [
        "app", "appex", "bundle", "framework", "kext", "plugin",
        "prefpane", "systemextension", "xpc",
    ]

    public static func isBundle(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && extensions.contains(ext)
    }

    /// Includes the selected directory itself and ancestors above the scan root.
    public static func containsBundleComponent(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { isBundle(name: $0) }
    }
}
