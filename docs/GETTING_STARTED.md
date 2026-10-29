# Getting started

## Wine and environments

Good Gameble Games manages the library; Wine runs Windows programs. Open **Runtime** and either download managed Wine or choose an installed `wine` / `wine64` executable. Keep a manually connected runtime in its original distribution folder: its libraries are required.

The managed download is the pinned Whisky community Wine 11.0 distribution. Setup checks the download, stages extraction, and verifies the runtime before selecting it. It requires macOS 15+, Rosetta 2 on Apple Silicon, and at least 2 GB free space before game installation. Rosetta and Apple license acceptance remain under your control.

In **Environments**, create an environment for a game or a group of compatible games. Each environment has its own Windows files and runtime selection. Changing the default runtime affects new environments; change an existing one through **Actions → Change runtime**.

For the managed Direct3D 10/11 path, choose **Actions → Graphics → DXMT → Apply**. Return to Runtime default before changing an environment's runtime. Direct3D 12 uses a different setup; see [graphics](GRAPHICS.md).

## Install a game

Choose **Run installer…** in the intended environment. Complete the Windows installer, then select the installed executable in the discovery sheet and add it to Library. **Actions → Find installed games** scans again. If the executable is elsewhere, use **Add game** and choose it manually.

For GOG offline installers, download the small setup `.exe` and every numbered `.bin` part into the same folder. Select the installer folder so macOS grants access to all the parts. Good Gameble Games checks numbering gaps, duplicates, empty files and incomplete downloads before opening the installer. A GOG Galaxy downloader is not the offline game installer.

The app does not sign into stores or download games you own through store accounts. Use your own legitimately obtained installers or existing files.

## Launch and graphics

Select **Play** in Library. The game's environment supplies Wine and graphics settings; its executable directory is the working directory. Additional launch arguments are available when adding a game.

For a prepared D3DMetal game, **Graphics and performance…** controls MetalFX, ray tracing availability, MSync, the Metal backend and the optional FPS overlay. MetalFX also needs **DLSS selected inside the game**. Start with frame generation off; a successful upscaling result does not verify frame generation.

For the supported Witcher build, MetalFX creates and launches a separate compatibility executable. Turning MetalFX off returns to the original. Unsupported executable hashes are not patched. Details are in [graphics and compatibility](GRAPHICS.md).

## Free games

**Free games…** offers OpenTTD, SDL Sopwith and LibreQuake. Downloads come from their upstream sources and are checked before installation. License documents and manuals stay with the installed files. Sopwith and LibreQuake require DXMT in the selected environment.

## When something fails

**Activity** shows process output and offers **Stop environment**. Stopping an environment can discard unsaved Windows work. Closing the launcher alone leaves Windows programs running.

**Environments → Actions → Check environment** checks basic Wine command execution. Graphics diagnostics are available in the graphics panel; a separate diagnostic environment is under **Runtime → Advanced graphics diagnostics**. These checks help isolate failures but do not prove that a specific game works.

Use **Help → Export Diagnostics…** when reporting an issue. Common personal paths and credential patterns are redacted in the exported copy; on-disk logs remain unchanged. Review exported text before attaching it to a public issue.

## Files and backups

All application data is under `~/Library/Application Support/GGGMac/`:

- `library.json`: game entries, environments and settings. Before a schema upgrade, the previous file is preserved as `library-vN.backup.json`.
- `Bottles/`: Wine environments, including installed games. Back up the whole relevant environment, including `.gggmac-graphics` driver backups.
- `Runtimes/`: downloaded or manually prepared managed runtimes.
- `Downloads/`: optional verified game downloads.
- `Logs/`: full local process logs. The Activity view displays the latest 64 KB; automatic log rotation is not included yet.

Removing a library entry leaves the underlying files in place. Good Gameble Games does not delete environments or games automatically. Back up environments before external runtime upgrades or game changes.
