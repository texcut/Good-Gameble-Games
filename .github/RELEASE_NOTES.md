Early-access interface update for **Good Gameble Games**. Forks, modifications and contributions remain welcome under GPL-3.0-or-later.

- One main page with numbered first-run steps: connect a runtime, create an environment, then install or add a game.
- Existing libraries open as compact game rows. Setup reopens configuration on the same page.
- Activity has moved to a separate Logs window, available from the header or Help → Show Logs.
- Removed slogans, free-game download flows, benchmark controls and automatic diagnostic-environment creation from the player interface.
- Existing library entries, game files, environments and graphics preferences are retained.

Only the exact GOG Witcher 3 remaster build documented in the README is claimed as tested. The previous FPS observations and hash-verified MetalFX compatibility copy remain documented; this interface update does not claim a performance improvement.

**Direct3D 12 preparation is still manual.** The managed Wine download supplies the Direct3D 10/11 path and does not reproduce the tested Witcher setup. Apple graphics libraries, Wine distributions and game files are not bundled.

The launcher requires macOS 14+. Default artifacts are ad-hoc signed and **not Apple-notarized**. Verify downloads against SHA256SUMS. Read the README and docs/GETTING_STARTED.md for setup and limits.
