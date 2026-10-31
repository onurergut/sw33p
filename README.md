<div align="center">
  <img src="docs/icon.png" width="112" alt="sw33p app icon">
  <h1>sw33p</h1>
  <p><b>A native macOS cleaner that shows you the space you'll get back. It doesn't inflate it.</b></p>

  <p>
    <a href="https://github.com/onurergut/sw33p/actions/workflows/ci.yml"><img src="https://github.com/onurergut/sw33p/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://github.com/onurergut/sw33p/releases/latest"><img src="https://img.shields.io/github/v/release/onurergut/sw33p?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
  </p>
</div>

---

**Status:** v0.1.0.

sw33p finds build output and package-manager caches that are reproducible,
shows their allocated size, and moves them to the Trash. It only lists a folder
when a rule can prove what it is: `node_modules` needs a `package.json`, Rust
`target/` needs a `Cargo.toml`, a Python virtualenv needs `pyvenv.cfg`, and so
on. Everything else is left alone and counted.

## Screenshots

A real screenshot will be added with the first public build. sw33p does not
ship mockups.

## Why sw33p

- **Finder and `du`** tell you what is big. sw33p tells you what is safe to
  rebuild, grouped by project, with the age of the project next to it.
- **Disk analyzers** rank folders by size but do not know that a `node_modules`
  is reproducible and a `Documents` folder is not.
- **Shell snippets** work until you forget which project root you are in.
  sw33p validates markers and never follows symlinks.
- **Commercial cleaners** bundle uninstallers and monitoring. sw33p is one job,
  MIT licensed, and does not phone home.

**When not to use sw33p:** deleting application data, uninstalling apps,
recovering disk space on a Windows or Linux machine, or cleaning Docker images.
Those are different problems with different safety rules.

## What it scans

| Category | Only when | Removed with |
|---|---|---|
| `node_modules` | a sibling `package.json` exists | Trash |
| Rust `target/` | a sibling `Cargo.toml` exists | Trash |
| Python `.venv` / `venv` | `pyvenv.cfg` exists inside | Trash |
| Python `__pycache__` | always, grouped per project (or per loose library when there is no project marker) | Trash |
| Gradle / Android `build/` | a sibling `build.gradle` or `build.gradle.kts` exists | Trash |
| Gradle global cache | exact `~/.gradle/caches` path, not a symlink | Trash |
| Xcode DerivedData | `info.plist` exists inside | Trash |
| Xcode Archives | `.xcarchive` with `Info.plist` at `Archives/<date>/<name>.xcarchive`; listed with a warning | Trash |
| Xcode DeviceSupport | known platform folder (`iOS`, `watchOS`, `tvOS`, `xrOS`, `visionOS`) and version-shaped name | Trash |
| Unavailable simulators | reported by `simctl` | `xcrun simctl delete <udid>` |
| SwiftPM cache | known cache path | Trash |
| CocoaPods cache | known cache path | Trash |
| npm / yarn / pnpm caches | known cache paths, including the `npx` cache (`~/.npm/_npx`) | Trash |
| Homebrew cache | `brew` is installed; size is an upper bound | `brew cleanup` |

Nothing is selected by default. Xcode Archives are listed with a warning
because crash reports may need them; they are not preselected.

Homebrew cache bytes are the cache folder's allocated size, an upper bound.
`brew cleanup` may free less. Managed tasks are offered only when their targets
are inside the selected root. An excluded child also protects its parent from
cleanup; cache symlinks never grant cleanup permission to their targets.

## Safety

- The default is the Trash. Permanent deletion is a separate, confirmed choice.
- Symlinks are never followed. A candidate must stay inside the scan root.
- App, framework, and extension bundles are never scanned, and hidden folders
  in your home folder (`~/.vscode`, `~/.config`, `~/.local`, ...) are only
  entered to reach known caches. Code shipped inside apps, editor extensions,
  and installed CLI tools is not rebuildable, even with a `package.json` next
  to it.
- Marker files are re-checked immediately before deletion.
- Folders you exclude are honored while scanning and enforced again when a
  cleanup summary is prepared and confirmed. Adding an exclusion cancels a
  running scan or cleanup.
- Unreadable folders are reported, never guessed at. Full Disk Access may let
  sw33p read more of them.
- The summary shows categories, counts, commands, and warnings before cleanup.
- Sizes are allocated sizes. Hard links are counted once inside each candidate
  folder/subtree; shared links across candidates can be counted twice. APFS
  clones cannot be detected, so the real recovery may be smaller.
- Moving to the Trash does not free space until the Trash is emptied.

Full contract: [`docs/SAFETY.md`](docs/SAFETY.md).

## Install

1. Open the [releases page](https://github.com/onurergut/sw33p/releases) and
   download the build for your Mac:
   - **Apple Silicon** → `sw33p-0.1.0-apple-silicon.zip`
   - **Intel** → `sw33p-0.1.0-intel.zip`
2. Unzip with Finder and drag **sw33p** to Applications.
3. Open it. Public releases are Developer ID-signed and notarized by Apple.

**Requirements:** macOS 14 or later. No Homebrew required; if Homebrew is
installed, its cache is included.

The first scan of a protected folder may require Full Disk Access. Grant it in
System Settings → Privacy & Security → Full Disk Access. Without it, sw33p
reports the folders it could not read and continues.

## Use

1. Choose a scan root. The default is your home folder.
2. Press **Scan**. The scan runs in the background and can be cancelled.
3. Filter by category or by how long the project has been untouched.
4. Select items and press **Clean Up…**.
5. Review the summary. Move items to the Trash, or explicitly choose permanent
   deletion.

## Privacy

No network access, no telemetry, no accounts. sw33p reads filenames and
metadata on your Mac and nothing leaves it. Command-backed cleanup runs only
`xcrun simctl` and `brew cleanup`. Subprocesses inherit the app environment
with `HOMEBREW_NO_ANALYTICS=1` and `HOMEBREW_NO_AUTO_UPDATE=1` added; sw33p
itself contains no network code.

## Build from source

Requires the Xcode command line tools with Swift 6 and macOS 14+.

```sh
swift test
swift run sw33p
```

Packaging and notarization are in [CONTRIBUTING.md](CONTRIBUTING.md#release-builds).

## Documentation

- [Safety model](docs/SAFETY.md)
- [Known limitations](docs/LIMITATIONS.md)
- [Design](docs/DESIGN.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## License

MIT. See [`LICENSE`](LICENSE).
