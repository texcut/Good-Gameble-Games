# Changelog

## 0.14.1 — Swift build compatibility

- Split the diagnostic export expression into smaller sections to support the older Swift compiler on GitHub Actions. Local gameplay and library data are unchanged.

## 0.14.0 — Early access

- Named the public project Good Gameble Games; retained internal GGGMac identifiers and data paths for existing users.
- Documented the single-game GOG Witcher 3 test scope, observed FPS readings, and hash-verified GOG DLSS/MetalFX workaround.
- Explicitly welcomed forks and modifications under the existing GPL license.

- Added an original three-G icon for Finder, Dock, About and the application sidebar, with editable SVG and a reproducible renderer.
- Simplified library, environment and runtime screens. Optional renderer reports and graphics diagnostics are grouped behind explicit controls.
- Replaced the development journal with user setup, graphics, developer and release documentation.
- Added local release packaging, source-selection checks, component notices and GitHub issue/release preparation workflows.
- Added best-effort personal-path and credential redaction for diagnostic exports.
- Preserved existing Wine/DXMT setup and verified D3DMetal/MetalFX behavior. Existing libraries and preferences remain in place.

### Known limits

- D3DMetal preparation is manual; no graphical importer is included yet.
- The Witcher workaround supports one exact executable hash.
- Broad game compatibility, frame generation and sustained 60 FPS are not guaranteed.
- Builds are ad-hoc signed unless a maintainer supplies a Developer ID identity; notarization is separate.
- Intel gameplay and detached launcher tracking need further validation.

## 0.13.x — Development builds

- Added MetalFX/DLSS bridge setup and a separate hash-verified Witcher compatibility executable that preserves the original.
- Fixed game selection during setup and recreation of a missing compatibility copy.
- Repaired the known stale Wine NGX placeholder that blocked Streamline feature discovery in existing environments.

## Earlier development

Local library and environments, verified Wine downloads, installer discovery, reversible DXMT deployment, optional free games, graphics diagnostics, and environment-wide performance options.
