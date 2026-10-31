# Changelog

## 0.1.0

Unreleased.

- First release.
- Scans `node_modules`, Rust `target/`, Python virtualenvs and `__pycache__`,
  Gradle caches and Android `build/`, Xcode DerivedData, Archives, DeviceSupport, SwiftPM,
  CocoaPods, npm/yarn/pnpm caches, unavailable simulators, and the Homebrew
  cache.
- Marker-file validation and a compiled-in allowlist for global caches,
  including the `npx` cache.
- App, framework, and extension bundles and hidden home folders such as
  `~/.vscode` and `~/.config` are not scanned, so code shipped with apps,
  editor extensions, and installed tools is never listed.
- `__pycache__` folders outside a project are grouped per loose library
  instead of one row per folder.
- Cancellable background scan with live progress.
- Age filter for projects untouched for 30, 90, 180, or 365 days.
- Cleanup summary with per-category totals, warnings, and the Trash caveat.
- Trash by default; permanent deletion is opt-in and confirmed.
- Cleanup revalidates symlinks, containment, and markers for filesystem items
  immediately before removal.
- MIT licensed. Developer ID-signed and notarized releases.
