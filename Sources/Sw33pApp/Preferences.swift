import Foundation
import Sw33pCore

struct Preferences {
    private let defaults: UserDefaults
    private let rootKey = "scanRoot"
    private let exclusionsKey = "userExclusions"
    private let ageKey = "ageFilter"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var scanRoot: URL {
        get {
            if let path = defaults.string(forKey: rootKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: rootKey) }
    }

    var userExclusions: [URL] {
        get {
            (defaults.array(forKey: exclusionsKey) as? [String] ?? [])
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set { defaults.set(newValue.map(\.path), forKey: exclusionsKey) }
    }

    var ageFilter: AgeFilter {
        get { AgeFilter(rawValue: defaults.integer(forKey: ageKey)) ?? .any }
        set { defaults.set(newValue.rawValue, forKey: ageKey) }
    }
}
