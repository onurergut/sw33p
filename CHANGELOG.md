# Changelog

## 0.1.0

Released 30 October 2026.

- First release.
- Scans `node_modules`, Rust `target/`, Python virtualenvs and `__pycache__`,
  Gradle/Android `build/`, Xcode DerivedData, Archives, DeviceSupport, SwiftPM,
  CocoaPods, npm/yarn/pnpm caches, unavailable simulators, and the Homebrew
  cache.
- Marker-file validation and a compiled-in allowlist for global caches.
- Cancellable background scan with live progress.
- Age filter for projects untouched for 30, 90, 180, or 365 days.
- Cleanup summary with per-category totals, warnings, and the Trash caveat.
- Trash by default; permanent deletion is opt-in and confirmed.
- Cleanup revalidates symlinks, containment, and markers immediately before
  removal.
- MIT licensed. Developer ID-signed and notarized releases.
