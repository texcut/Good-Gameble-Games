# Getting started

## First run: three steps on one page

### 1. Connect a runtime

Select **Connect runtime…** and choose the `wine` or `wine64` executable from a compatible macOS Wine distribution. Keep its distribution folder intact: Wine needs the accompanying libraries.

**For Witcher 3 / Direct3D 12, connect an already prepared D3DMetal runtime.** A graphical Apple-payload importer is not included. See [graphics and compatibility](GRAPHICS.md) for the tested configuration and current manual setup limitation.

**Runtime options** contains installed-runtime discovery and the optional managed Wine 11.0 download for Direct3D 10/11. That download is 332 MB, requires macOS 15+, Rosetta 2 on Apple Silicon and at least 2 GB free space, and does not provide the Witcher DX12 setup. Scan again searches existing files; it does not install Wine.

The default runtime applies to new environments. Existing environments keep their assigned runtime.

### 2. Create an environment

Enter a name and choose **Create environment**. Wine prepares the Windows files; the first setup may take a few minutes. An environment stores installed software and settings separately from other environments.

Each environment row has **Graphics…** and a menu for changing its runtime, finding installed games or opening its folder. For the managed Direct3D 10/11 path, select **Graphics… → DXMT → Apply**. Return to Runtime default before changing the runtime. A prepared D3DMetal environment uses Runtime default.

### 3. Install or add a game

Select an environment if there is more than one. Choose **Run installer…** for a local Windows installer, or **Add installed game…** for an existing `.exe`.

For GOG offline downloads, keep the small setup `.exe` and **every** numbered `.bin` part in the same folder and select that folder. The app checks numbering gaps and incomplete downloads before opening the installer. A GOG Galaxy downloader is not the offline game installer.

Complete the Windows installer. After it closes, select the installed game executable in the discovery sheet and add it to the library. **Find installed games…** scans again. For the supported Witcher build, choose the original `bin/x64_dx12/witcher3.exe`.

The app does not sign into stores or download purchased games through store accounts. Use your own installers or existing files.

## After setup

The main page opens as a compact game list. Select **Play** to launch a game. The sliders button opens graphics settings; the row menu can reveal its executable or remove the library entry. Removing an entry leaves its files in place.

**Setup** reopens all three configuration sections on the same page. Completed steps remain compact. Use **Add another environment** when needed; **Install…** above the game list runs an installer in an existing environment. **Add game** links an existing executable. If the last game entry is removed, the numbered guidance returns.

Existing libraries do not need to repeat setup. An environment's assigned runtime counts even if no default runtime is selected.

For prepared D3DMetal games, **Graphics and performance** controls MetalFX, ray tracing availability, MSync, Metal backend and the FPS overlay. MetalFX also requires **DLSS selected inside the game**. Frame generation is not validated. The supported Witcher workaround writes a separate compatibility copy, preserves the original executable and refuses unknown hashes. See [graphics and compatibility](GRAPHICS.md).

There are no free-game downloads or timedemo controls in this interface. Previously added games remain ordinary library entries.

## Logs and troubleshooting

**Logs** opens a separate window. **Help → Show Logs** (Shift–Command–L) opens the same window. It shows the current process output, can open the logs folder and exports diagnostics. **Diagnostics** contains optional Wine, graphics and window checks for an existing environment; no diagnostic environment is created automatically.

**Stop environment** ends Windows programs in the active environment and can discard unsaved Windows work. It is available while an operation is active on the main page and in Logs. Closing the launcher alone leaves Windows programs running.

Diagnostic exports redact common personal paths and credential patterns; on-disk logs remain unchanged. Review exports before attaching them to a public issue.

## Files and backups

All application data stays under `~/Library/Application Support/GGGMac/`:

- `library.json`: library entries, environments and settings. Before a schema upgrade, the old file is preserved as `library-vN.backup.json`.
- `Bottles/`: Windows environments and installed software. Back up the relevant whole environment, including graphics-driver backups.
- `Runtimes/`: downloaded or manually prepared managed runtimes.
- `Downloads/`: previously downloaded development-game archives, if present. This version does not download those games.
- `Logs/`: full local process logs. The Logs window shows the latest 64 KB; automatic rotation is not included yet.

The interface change does not move existing data or delete installed games. Back up environments before external runtime upgrades or game changes.
