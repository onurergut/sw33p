# sw33p design

Status: approved 30 October 2026. This document is the contract for v0.1.0.

## Product

sw33p finds reproducible developer junk on a Mac, shows how much space it
occupies, and removes it safely. It is part of the same small-tools family as
conv3rt: native SwiftUI, direct distribution, MIT licensed, no telemetry.

Slogan: **Shows you the space you'll get back. It doesn't inflate it.**

The product is deliberately honest about three things:

1. Sizes are allocated sizes, not logical sizes.
2. Hard links are counted once inside each candidate folder/subtree; shared
   links across candidates can be counted twice, and APFS clones cannot be
   detected, so the recoverable total can be lower than reported.
3. Moving files to the Trash does not free disk space until the Trash is
   emptied. The UI says so in the cleanup summary.

Not in v0.1.0: Docker cleanup (an optional `docker system df` readout may be
shown later), scheduled cleaning, menu bar mode, Windows/Linux, Sparkle
updates, App Store distribution.

## Identity

| Item | Value |
|---|---|
| App name | sw33p |
| Bundle identifier | `com.sw33p.app` |
| Minimum macOS | 14.0 |
| Language mode | Swift 6, strict concurrency |
| Distribution | Developer ID, Hardened Runtime, notarized ZIP |
| Sandbox | No |
| Network | None |
| Version | 0.1.0, build 1 |

## Repository layout

```text
Package.swift
Sources/Sw33pCore/            UI-free scanning, sizing, cleanup, maintenance
Sources/Sw33pApp/             SwiftUI app shell and views
Tests/Sw33pCoreTests/         engine and safety tests
Tests/Sw33pAppTests/          app model tests
Resources/Info.plist
Resources/sw33p.entitlements  Intentionally empty
Resources/sw33p.icns
scripts/package.sh
scripts/notarize.sh
scripts/verify-release.sh
scripts/make-icon.swift
scripts/test-packaging.sh
docs/DESIGN.md
docs/SAFETY.md
docs/LIMITATIONS.md
docs/icon.png
.github/workflows/ci.yml
README.md
CONTRIBUTING.md
CHANGELOG.md
LICENSE
.gitignore
```

SwiftPM only; no Xcode project. The app is an executable target that builds a
complete `.app` bundle at packaging time, as in conv3rt.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Scan strategy | One depth-first pass from the chosen root, rule matching per directory | One code path, natural progress/cancel, project context available, new rules are data/tests only |
| Project age | Newest mtime anywhere in the project subtree, excluding matched junk subtrees | Measures real activity, not install time; files are walked for sizing anyway |
| Updater | None in v0.1.0 | Keeps v1 scope small; Sparkle can be added in a later release |
| Deletion default | `FileManager.trashItem` | Recoverable by default |
| Permanent delete | Explicit opt-in in the summary sheet with a second confirmation | Irreversible action must be deliberate |
| Rule ambiguity | Do not list the candidate. Node/Python rules return a note; Rust, Gradle, and Xcode rules return `nil` silently | "When unsure, do not list" |
| Age filter | Applied in the UI over completed scan results | Avoid rescanning; instant feedback |
| Command-based rules | `MaintenanceDetector` producing `MaintenanceAction`, with an injected `CommandRunner` | Testable without running `simctl` or `brew` |

## Core architecture

```text
ScanEngine         Sendable struct; AsyncThrowingStream<ScanEvent>
                   DFS, cancellation, throttled progress
RuleCatalog        [JunkRule]; each rule independent
DirectorySizer     allocated size, hard-link dedupe, no symlink following
CleanupPlanner     wraps a selection into a summary by category
CleanupValidator   revalidates rules, containment, and path identities
Cleaner            injected TrashClient / FileRemover; per-item results
MaintenanceDetector simctl and brew detection with injected CommandRunner
MaintenanceAction  executable, arguments, and summary for a managed removal
```

### Models

```swift
enum JunkCategory {
    case nodeModules, rustTarget, pythonArtifacts, gradleAndroid
    case xcodeDerivedData, xcodeArchives, xcodeDeviceSupport, simulators
    case swiftPM, cocoapods, npmCaches, homebrew
}

struct JunkItem: Sendable, Identifiable {
    let ruleID: RuleID
    let category: JunkCategory
    let urls: [URL]               // folders, or the command target
    let projectURL: URL?          // validated project root, nil for global items
    let projectLabel: String?     // display name when projectURL is nil
    let lastActivity: Date        // newest project mtime, excluding junk
    let allocatedBytes: Int64
    let fileCount: Int
    let warnings: [ItemWarning]
    let removal: Removal          // .filesystem or .managed(MaintenanceAction)
    let validation: ItemValidation
}

enum ScanEvent: Sendable {
    case discovered(JunkItem)
    case progress(ScanProgress)
    case issue(ScanIssue)
    case note(ScanNote)           // e.g. "3 node_modules folders had no package.json"
    case finished(ScanSummary)
}
```

### Rule protocol

```swift
protocol JunkRule: Sendable {
    var id: RuleID { get }
    var category: JunkCategory { get }
    func match(url: URL, name: String, context: ScanContext) -> RuleMatch?
}

enum RuleMatch {
    case candidate(JunkCandidate)
    case note(ScanNote)
    case skip(ScanNote)
}
```

Marker checks use `lstat` semantics: a marker must be a regular file and must
not be a symlink. A rule that cannot validate its marker returns `.note` or
`.skip` where a user-facing note helps; otherwise it returns `nil` silently.
It never returns a candidate.

Adding a rule requires a catalog entry plus fixture tests. No scanner changes.

### Traversal

- The selected root is canonicalized once with `resolvingSymlinksInPath`.
- Traversal never follows symlinks and never resolves candidate paths. Only
  the selected home/root is canonicalized; known cache paths stay lexical so a
  cache symlink cannot grant cleanup permission to another folder.
- Containment is checked per path component against the canonical root, not by
  string prefix.
- The walker maintains a stack of project frames. Each frame tracks the newest
  mtime seen in that project, excluding matched junk subtrees.
- A project's candidates are emitted when its frame closes, so `lastActivity`
  is final on arrival.
- Global-location candidates are emitted immediately with `projectURL == nil`.
- Default pruned paths: children named `.git`, directories ending in
  `.photoslibrary`, and the prefix-excluded `~/.Trash`, `~/Library/CloudStorage`,
  `~/Library/Mobile Documents`, `~/Library/Containers`,
  `~/Library/Group Containers`, `~/Library/Keychains`,
  `~/Library/Developer/CoreSimulator`, and
  `~/Pictures/Photos Library.photoslibrary`. Prefix-excluded folders are pruned
  when encountered under the root. Selecting one as the root is not useful
  because its children are pruned too, so no filesystem items are found. A
  symlink scan root is rejected.
- Unreadable directories produce a `ScanIssue`; scanning continues.
- Cancellation is injected as `@Sendable () -> Bool` (`Task.isCancelled` in
  production) and checked per directory, so tests can cancel deterministically.
- Progress events are throttled to roughly ten per second. Progress includes
  directories visited, bytes found, and items found.

### Sizing

`DirectorySizer` walks a candidate subtree once and sums allocated bytes from
`lstat` as `st_blocks * 512`. Hard links are counted once using `(st_dev,
st_ino)` identities. Symlinks are skipped entirely. Clones cannot be detected;
this limitation is surfaced in the summary, not hidden. Deduplication is per
candidate subtree, so two candidates that share a hard link can both count it.

### Cleanup

`CleanupPlanner` turns a selection into a summary broken down by category.
User exclusions are enforced when the summary is prepared and again at confirm
time; adding an exclusion cancels a running scan or cleanup. Default
exclusions guard the walker and filesystem cleanup, while managed command items
are exempt from default walk exclusions but not from user exclusions. A parent
containing an excluded child is protected too. Managed targets must remain
inside the selected scan root, and cleanup rechecks scope and user exclusions.

`Cleaner` re-validates every filesystem item immediately before deleting:

1. The path exists and is a directory, verified with `lstat`.
2. No path component from the root to the candidate is a symlink.
3. The canonical candidate path is inside the selected scan root.
4. The rule still validates the candidate.

Validation is an explicit enum: `.marker(URL)` for a regular in-root marker,
`.knownRoot(URL)` for an exact compiled-in cache root, `.versionedKnownRoot(URL)`
for a direct child of an exact Xcode DeviceSupport platform folder with a
version-shaped name, and `.pythonCache` for a `__pycache__` directory. `.none`
is rejected for filesystem items. Command-backed items are routed by
`Removal.managed` and are never passed to the Trash. Before each deletion a
receipt re-checks ancestor, target, and marker identities; this narrows but
does not close the path-based TOCTOU window.

Deletion uses `FileManager.trashItem` by default. Permanent deletion requires
the summary sheet's Trash toggle to be off and a second confirmation. Results
are reported per item; partial failure is never collapsed into success.

## Rule catalogue (v0.1.0)

| Category | Match | Marker / validation | Removal |
|---|---|---|---|
| nodeModules | directory named `node_modules` | sibling `package.json` | Trash |
| rustTarget | directory named `target` | sibling `Cargo.toml` | Trash |
| pythonArtifacts | `.venv` or `venv` | `pyvenv.cfg` inside | Trash |
| pythonArtifacts | `__pycache__` | project context; aggregated per project, or per package source root when there is no project marker | Trash |
| gradleAndroid | directory named `build` | sibling `build.gradle` or `build.gradle.kts` | Trash |
| gradleAndroid | `~/.gradle/caches` | exact known path, non-symlink directory | Trash |
| xcodeDerivedData | `~/Library/Developer/Xcode/DerivedData/*` | `info.plist` inside; show `WorkspacePath` when present | Trash |
| xcodeArchives | `.../Archives/*/*.xcarchive` | `Info.plist` inside | Trash, warning, not preselected |
| xcodeDeviceSupport | `.../{iOS,watchOS,tvOS,xrOS,visionOS} DeviceSupport/*` | exact known parent plus version-shaped name | Trash, old-OS debugging warning |
| simulators | unavailable devices from `simctl list devices -j` | parsed JSON, UDID | `xcrun simctl delete <udid>` |
| swiftPM | `~/Library/Caches/org.swift.swiftpm` | known path | Trash |
| cocoapods | `~/Library/Caches/CocoaPods` | known path | Trash |
| npmCaches | `~/.npm/_cacache`, `~/Library/Caches/Yarn`, `~/.cache/yarn`, `~/Library/pnpm/store`, `~/.pnpm-store`, `~/Library/Caches/pnpm` | known path, only if present | Trash |
| homebrew | `brew --cache` succeeds | brew installed | `brew cleanup` |

Projectless items show "Global cache" or the managing tool instead of a project
path. Simulator rows are per unavailable device. Homebrew is one row.

## UI

One window, minimum 820 x 560.

```text
┌──────────────────────────────────────────────────────────────┐
│ [📁 /Users/onur]  [Change…]      [Scan]   Age: 90+ days ▾    │
├──────────────┬───────────────────────────────────────────────┤
│ All     4.2G │ ▾ node_modules            1.8 GB   12 items   │
│ node_modules │   ~/dev/site-a           92 days   1.2 GB     │
│ Rust         │   ~/dev/tool             41 days   610 MB     │
│ Python       │ ▾ Xcode DerivedData       2.1 GB   8 items    │
│ Gradle       │   ~/dev/ios-app         128 days   900 MB    │
│ Xcode        │ ...                                           │
│ Caches       │                                               │
│ Homebrew     │                                               │
├──────────────┴───────────────────────────────────────────────┤
│ 20 items · 4.2 GB · space is not freed until Trash is empty  │
│                                      [Clean Up…]             │
└──────────────────────────────────────────────────────────────┘
```

- The age filter re-filters completed results without rescanning.
- Rows are checkbox-selectable; nothing is preselected, including Archives.
- While scanning: progress bar, live totals, Cancel button.
- After scanning: an aggregate note for folders left alone because a marker was
  missing.
- Permission failures produce a note pointing at Full Disk Access, with the
  same information in the README.
- Settings: excluded folders (add/remove with `NSOpenPanel`), last root, default
  age filter.
- The app menu has Scan (Command-R), Cancel (Command-.), and Clean Up.

## Safety invariants

These are non-negotiable and covered by tests:

1. Default removal is Trash, never `unlink`.
2. Permanent removal requires explicit opt-in and confirmation.
3. Symlinks are never followed, and candidate paths are never resolved.
4. A candidate must be inside the scan root, checked per path component.
5. A marker-based candidate is removed only while its marker still validates.
6. A global-cache candidate must match the compiled-in allowlist.
7. The summary is shown before any deletion; it includes the total, per-category
   breakdown, warnings, and the APFS/hard-link and Trash caveats.
8. A failed item does not abort the rest silently; failures are listed.
9. The app performs no network access.

## Tests

- Per rule: positive fixture, missing marker (negative), symlinked marker
  (negative).
- Scanner: nested projects, monorepo, project age excludes junk, exclusion
  pruning, no escape above the root, symlinks not followed, unreadable
  directory, cancellation, empty root.
- Size: allocated size, hard-link dedupe, symlinks excluded.
- Cleaner: Trash path, permanent path, symlink refusal, outside-root refusal,
  stale-marker refusal, partial failure reporting.
- Maintenance: stub `CommandRunner` for simctl JSON parsing, unavailable
  filtering, missing brew.
- App model: age filtering, totals, selection.
- No CI test runs real `simctl` or `brew`.

## CI and release

CI on `macos-15`:

```sh
swift build
swift test --enable-code-coverage
# llvm-cov report, no threshold
swift build -c release
bash scripts/test-packaging.sh
```

Packaging:

```sh
scripts/package.sh arm64 0.1.0 1
scripts/package.sh x86_64 0.1.0 1
scripts/notarize.sh dist/sw33p-0.1.0-apple-silicon/sw33p.app
```

Artifacts: `sw33p-0.1.0-apple-silicon.zip` and `sw33p-0.1.0-intel.zip`, each
with a `.sha256` file. The bundler signs with Hardened Runtime when
`CODESIGN_IDENTITY` is set, otherwise ad-hoc for smoke tests. `verify-release.sh`
checks bundle structure, plist values, signature, and absence of build paths.

## Implementation order

1. `chore: scaffold SwiftPM app and repository`
2. `feat(core): add scan models and rule catalog` plus rule fixture tests
3. `feat(core): implement cancellable scanner with project activity` plus
   traversal and sizing tests
4. `feat(core): add safe trash-first cleanup` plus cleaner safety tests
5. `feat(core): add simulator and Homebrew maintenance tasks`
6. `feat(app): add SwiftUI scan, filter, and cleanup UI`
7. `build: add icon, packaging, notarization, and release verification`
8. `ci: build, test, coverage, packaging smoke`
9. `docs: add README, safety model, limitations, changelog`
