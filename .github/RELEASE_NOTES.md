First public early-access release of **Good Gameble Games**: a free macOS launcher built to play a legally owned GOG Witcher 3 remaster without a paid CrossOver license. Forks, modifications and contributions are welcome under GPL-3.0-or-later.

**Tested game scope:** only the exact GOG Witcher 3 remaster 5.01 executable documented in the README, on an M3 Max / macOS 27.2 / Wine 11.16 / Apple evaluation environment 4.0 beta 3. Other games and builds, ray tracing and frame generation are not validated by this release.

Captured readings included 44.78 FPS at 1080p, 57.93 FPS at 1344×756, and 41.05 FPS in a night scene with temporal MetalFX at 1707×960 → 2560×1440. These are individual observations from different runs, not controlled benchmark averages or promised performance. See the README for the full record and limitations.

- Original three-G icon and native local library/environment interface.
- Managed Wine and reversible DXMT setup for Direct3D 10/11.
- **Witcher / Direct3D 12 preparation remains manual.** There is no graphical Apple-payload importer. Downloading managed Wine alone does not reproduce the Witcher setup.
- Hash-verified GOG compatibility copy exposes the DLSS interface to Apple's MetalFX bridge while leaving the original executable untouched. Unknown hashes are refused.
- Internal GGGMac identifiers/data paths are retained for existing libraries.

The launcher requires macOS 14+; the managed runtime requires macOS 15+ and Rosetta 2 on Apple Silicon. The tested DX12 stack has its own requirements, documented in [graphics and setup](https://github.com/texcut/Good-Gameble-Games/blob/v0.14.0/docs/GRAPHICS.md).

Artifacts are ad-hoc signed, **not Apple-notarized**. Downloaded builds may be blocked by Gatekeeper. No Wine distribution, Apple graphics libraries, game executables or game assets are bundled; the original diagnostic executable is included with source and notices. Verify downloads against SHA256SUMS.

Read the [README, test observations and GOG patch instructions](https://github.com/texcut/Good-Gameble-Games/tree/v0.14.0#readme) before downloading. The macOS app archive targets Apple Silicon (arm64); the source archive is included for builds and forks.
