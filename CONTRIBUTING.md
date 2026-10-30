# Contributing to sw33p

## Ground rules

- Only list a folder when a rule can prove it is safe to remove; exceptions
  (Xcode Archives, Homebrew cleanup) are labeled with warnings.
- Never follow a symlink.
- Trash is the default. Permanent deletion requires explicit confirmation.
- Report allocated sizes. Do not inflate savings; state the APFS clone caveat.
- Do not add network access.
- Keep the app small and the core UI-free.

## Development

```sh
swift test
swift run sw33p
```

## Adding a rule

1. Add a `JunkRule` implementation in `Sources/Sw33pCore/Rules/`.
2. Require a marker file or a compiled-in known location.
3. Add it to `RuleCatalog.rules(knownLocations:)`.
4. Add positive, missing-marker, and symlinked-marker tests in
   `Tests/Sw33pCoreTests/JunkRuleTests.swift`.
5. Add an integration scan test in `ScanEngineTests.swift`.
6. Update the README table and `docs/SAFETY.md` if the safety model changes.

## Release builds

```sh
swift test
swift build -c release
bash scripts/test-packaging.sh
scripts/package.sh arm64 0.1.0 1
scripts/package.sh x86_64 0.1.0 1
scripts/notarize.sh dist/sw33p-0.1.0-apple-silicon/sw33p.app
```

Set `CODESIGN_IDENTITY` for Developer ID signing. Without it the bundle is
ad-hoc signed and is not distributable.

The app icon is generated from `scripts/make-icon.swift`:

```sh
swift scripts/make-icon.swift docs/icon.png
iconutil -c icns /tmp/sw33p.iconset -o Resources/sw33p.icns
```
