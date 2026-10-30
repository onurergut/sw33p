# Safety model

sw33p only lists a folder when a rule can prove what it is. Everything else is
left alone.

## Before deleting

For every filesystem item:

1. The path exists and is a directory, verified with `lstat`.
2. No path component from the scan root to the item is a symbolic link.
3. The item is inside the selected scan root, compared per path component.
4. The rule still validates the item: the marker file is present and regular,
   or the path is inside the compiled-in cache allowlist.

If any check fails, that item is skipped and reported. The rest continue.

Validation cases are explicit:

- `.marker(URL)`: the marker must still be a regular file, not a symlink, and
  inside the scan root.
- `.knownRoot(URL)`: the target must still be exactly one of the compiled-in
  cache roots.
- `.versionedKnownRoot(URL)`: the target must be a direct child of the exact
  Xcode platform DeviceSupport folder and its name must still be version-shaped.
- `.pythonCache`: the target's last path component must still be
  `__pycache__`.
- `.none`: rejected for filesystem items. Command-backed items are handled
  separately and are never passed to the Trash.

## Exclusions

User exclusions are enforced when a cleanup summary is prepared and again when
cleanup is confirmed. Adding an exclusion cancels a running scan or cleanup, so
it cannot be bypassed by work already in flight. Default exclusions guard the
walker and filesystem cleanup; command-backed items are exempt from the default
walk exclusions because dedicated detectors validate them, but user exclusions
always bind.

## Default: Trash

Filesystem items go to the Trash with `FileManager.trashItem`. Moving to the
Trash does not free disk space until the Trash is emptied; the summary says so.
Permanent deletion is a separate, explicitly confirmed option.

## Re-check and the remaining race

Before each deletion, `Cleaner` checks a receipt captured during validation:
the ancestor identities, the target identity, and the marker identity must
still match. This narrows the time-of-check/time-of-use window. It does not
make deletion atomic: path-based filesystem APIs can still have a value swapped
between the final `lstat` and `trashItem`/`removeItem`. Closing that race fully
would require deleting relative to an open directory descriptor.

## Sizes

Sizes are allocated sizes (`st_blocks * 512`), not logical file sizes. Hard
links are counted once inside a candidate subtree. APFS clones cannot be
detected; the summary states that the real recoverable space may be smaller.

## What is never scanned

Symbolic links, `.git` trees, the Trash, iCloud Drive, Mobile Documents, app
containers, Group Containers, Keychains, Photos libraries, and CoreSimulator
device data. Simulators are handled through `xcrun simctl`, not by deleting
files directly.

Unreadable folders are reported, never guessed at. Full Disk Access may let
sw33p read protected folders such as Desktop, Documents, Downloads, and
external volumes.

## Command-backed cleanup

Unavailable simulators are deleted with `xcrun simctl delete <udid>`.
Homebrew cleanup runs `brew cleanup`. Both commands are shown in the summary
before they run. sw33p builds the argument list itself; it does not accept
shell input. Commands run with a 120-second timeout and no stdin. Cancellation
or timeout sends the process `SIGTERM`; after a 2-second grace period sw33p
sends `SIGKILL`, and the runner waits for the process to exit before reporting.
Managed commands cannot be paused mid-run. Exit status, standard output, and
standard error are reported.

## Network

sw33p performs no network access. There is no telemetry, update check, or
account.
