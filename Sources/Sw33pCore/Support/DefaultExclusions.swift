import Foundation

public enum DefaultExclusions {
    public static func urls(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".Trash", isDirectory: true),
            home.appendingPathComponent("Library/CloudStorage", isDirectory: true),
            home.appendingPathComponent("Library/Mobile Documents", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true),
            home.appendingPathComponent("Library/Keychains", isDirectory: true),
            home.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true),
            home.appendingPathComponent("Pictures/Photos Library.photoslibrary", isDirectory: true),
        ]
    }
}
