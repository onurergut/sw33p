<div align="center">
  <img src="docs/icon.png" width="112" alt="sw33p app icon">
  <h1>sw33p</h1>
  <p><b>A native macOS cleaner for old developer projects and build caches.</b></p>

  <p>
    <a href="https://github.com/onurergut/sw33p/actions/workflows/ci.yml"><img src="https://github.com/onurergut/sw33p/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build and test workflow"></a>
    <a href="https://github.com/onurergut/sw33p/releases/latest"><img src="https://img.shields.io/github/v/release/onurergut/sw33p?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Requires macOS 14 or later">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  </p>
</div>

---

**Status:** v0.1.0, first public release. Apple Silicon and Intel builds are
Developer ID-signed and notarized by Apple. Expect the scan rules and the UI to
change in 0.1.x releases; the safety contract in
[`docs/SAFETY.md`](docs/SAFETY.md) is the part that should not.

sw33p finds build output, dependencies, and package-manager caches under a folder
you choose. It groups results by category and project, shows allocated disk
usage, and lets you review a cleanup before anything is removed. The age filter
helps answer the useful question: **which old projects can I stop keeping built?**

Part of the same small Mac tools family as [conv3rt](https://github.com/onurergut/conv3rt).

## Why sw33p

- **Finder and disk analyzers** show what is large. sw33p recognizes specific
  developer artifacts, checks project markers, and adds project-age filtering.
- **Shell scripts** are better for repeatable automation. sw33p is for choosing
  a folder, comparing results, and reviewing each cleanup interactively.
- **General-purpose cleaners** cover more territory. sw33p does not uninstall
  apps or clean arbitrary application data; its rules are deliberately narrow.

**When not to use sw33p:** app uninstalling, Docker cleanup, scheduled jobs,
Windows or Linux. Use the relevant tool's own commands for those jobs.

## Install

Download the ZIP for your Mac from the
[latest release](https://github.com/onurergut/sw33p/releases/latest):

- **Apple Silicon** → `sw33p-0.1.0-apple-silicon.zip`
- **Intel** → `sw33p-0.1.0-intel.zip`

Unzip in Finder, drag **sw33p.app** to Applications, and open it. Each ZIP has a
matching `.sha256` file. Releases are Developer ID-signed with the hardened
runtime and notarized by Apple, so Gatekeeper opens them without a warning.

**Requirements:** macOS 14 or later. Homebrew is optional; if installed, its
cache appears in the scan.

To build from source instead, you need the Xcode command line tools with Swift 6:

```sh
git clone https://github.com/onurergut/sw33p.git
cd sw33p
swift run sw33p
```

That launches the SwiftUI app. Run the tests with `swift test`. Build, signing,
and notarization steps are in
[CONTRIBUTING.md](CONTRIBUTING.md#release-builds).

## Use

1. Choose a scan root. The default is your home folder.
2. Press **Scan**. Scanning runs in the background and can be cancelled.
3. Filter by category or project age: any age, 30, 90, 180, or 365 days.
4. Select results and press **Clean Up…**. Nothing is selected automatically.
5. Review the categories, counts, commands, size total, and warnings. Filesystem
   items go to the Trash unless you explicitly confirm permanent deletion.

Project age uses the newest modification time among scanned project files,
excluding matched junk. It is not a last-opened or last-used timestamp. Global
caches and managed items use their folder modification time instead.

Add folders to the exclusion list in Settings. Unreadable folders are reported;
Full Disk Access in **System Settings → Privacy & Security** may allow more of
them to be read. It is not required to scan folders you can already access.

## What it scans

| Target | Required evidence | Cleanup |
|---|---|---|
| `node_modules` | Sibling `package.json` | Trash |
| Rust `target/` | Sibling `Cargo.toml` | Trash |
| Python `.venv` / `venv` | `pyvenv.cfg` inside | Trash |
| Python `__pycache__` | Directory name; grouped by project or loose library | Trash |
| Gradle / Android `build/` | Sibling `build.gradle` or `build.gradle.kts` | Trash |
| Gradle global cache | Exact `~/.gradle/caches` path | Trash |
| Xcode DerivedData | Direct child of the known root with `info.plist` | Trash |
| Xcode Archives | `Archives/<date>/<name>.xcarchive` with `Info.plist` | Trash, with warning |
| Xcode DeviceSupport | Known platform root and version-shaped child name | Trash, with warning |
| Unavailable simulators | `simctl` reports an unavailable device with a valid UDID | `xcrun simctl delete <udid>` |
| SwiftPM / CocoaPods caches | Known cache paths | Trash |
| npm / yarn / pnpm caches | Known cache paths, including `~/.npm/_npx` | Trash |
| Homebrew | Installed `brew` and its reported cache path | `brew cleanup` |

DeviceSupport covers iOS, watchOS, tvOS, xrOS, and visionOS. Managed tasks are
listed only when their target is inside the selected root.

**Archives are not reproducible:** removing them can prevent symbolication of
older crash reports. Recreating dependencies or environments can also require
downloads and lose local changes inside those folders. Review before removing.

## Safety and size reporting

- **Trash first.** Permanent filesystem deletion requires a separate choice
  and a second confirmation. Simulator and Homebrew commands use their own
  removal behavior; they do not move files to the Trash.
- **No symlink traversal.** Filesystem targets stay inside the selected root.
  Marker files, path components, and identities are rechecked before removal.
  Path-based deletion still has a small non-atomic race; it is documented in
  the [safety model](docs/SAFETY.md#re-check-and-the-remaining-race).
- **Installed code stays out.** App, framework, and extension bundles are
  protected, even if a bundle or a folder inside it is selected as the root.
  Home scans enter hidden folders only toward known caches; explicitly
  selecting a hidden folder broadens that scan, but does not remove bundle
  protection.
- **Exclusions protect parents too.** An excluded child prevents its parent
  from being offered as one cleanup target. Adding an exclusion requests
  cancellation of running work; it cannot undo a deletion already in progress.
- **Sizes are not guaranteed savings.** sw33p uses allocated bytes. Hard links
  are deduplicated within each candidate folder, but can be counted twice
  across candidates. APFS clones can further reduce the real recovery.
- **Homebrew is an upper bound.** The displayed cache size can exceed what
  `brew cleanup` removes.
- **Moving to the Trash frees no space until the Trash is emptied.**

Full details: [Safety model](docs/SAFETY.md) · [Known limitations](docs/LIMITATIONS.md).

## Privacy

sw33p has no network client, telemetry, accounts, or updater. It does not upload
files or scan results. Command-backed checks and cleanup invoke `xcrun simctl`
and Homebrew locally. Subprocesses receive `HOMEBREW_NO_ANALYTICS=1` and
`HOMEBREW_NO_AUTO_UPDATE=1` to disable Homebrew analytics and auto-update.

## Documentation and license

- [Contributing and release builds](CONTRIBUTING.md)
- [Safety model](docs/SAFETY.md)
- [Known limitations](docs/LIMITATIONS.md)
- [Design](docs/DESIGN.md)
- [Changelog](CHANGELOG.md)

MIT. See [LICENSE](LICENSE).
