import Foundation

public enum ProjectMarkers {
    public static let names = [
        ".git",
        "package.json",
        "Cargo.toml",
        "build.gradle",
        "build.gradle.kts",
        "pyproject.toml",
        "setup.py",
        "requirements.txt",
    ]

    public static func isProject(_ url: URL) -> Bool {
        names.contains { name in
            let candidate = url.appendingPathComponent(name)
            return FileStatReader.stat(candidate).map { $0.isDirectory || $0.isRegularFile } ?? false
        }
    }
}
