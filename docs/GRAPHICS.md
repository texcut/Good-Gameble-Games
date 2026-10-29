# Graphics and compatibility

## DXMT and the managed runtime

The standard runtime download is [Whisky community Wine Libraries 3.1.1](https://github.com/frankea/Whisky/releases/tag/v3.1.1), based on Wine 11.0. The app pins its archive size and SHA-256, checks extraction paths, and keeps it in a versioned directory. It is downloaded from upstream, not redistributed inside Good Gameble Games.

DXMT translates Direct3D 10/11 to Metal. Select it through **Environments → Actions → Graphics**. Good Gameble Games backs up original DLLs and records what it deploys. Returning to Runtime default restores those files. Unknown edits and conflicting backups are preserved and reported instead of overwritten.

DXMT does not implement Direct3D 12. A stock Wine D3D12 device responding to a small diagnostic does not imply that a modern DX12 game meets its feature requirements.

## D3DMetal: advanced setup

**There is no graphical Apple-payload importer in this release.** The known prepared configuration uses:

- [GPTK-compatible Wine Libraries 4.6.4-beta.1](https://github.com/frankea/Whisky/releases/tag/v4.6.4-beta.1), Wine 11.16.
- The owner's download of Apple's **Evaluation environment for Windows games 4.0 beta 3**.
- Apple Silicon, with the OS requirements of those components. Metal 4 selection additionally requires macOS 27+.

Apple downloads, sign-in and license acceptance are handled directly with Apple. Apple binaries are never included in Good Gameble Games archives. The prepared runtime is hash-checked against its local receipt; arbitrary GPTK versions are not accepted as equivalent.

For developers carrying an existing compatible setup, `scripts/preserve-d3dmetal-test.py --help` describes the local handoff. It requires an already prepared runtime and stopped environment, the original pinned archive and Apple DMG, and matching existing library IDs. This is a migration/development helper, not an end-user installer. It does not download components or accept their terms. The app connects a validated handoff while preserving the previous library. A clean-machine, guided DX12 setup remains future work.

For ordinary users, the reproducible graphical setup in this release is the managed Wine/DXMT path. Do not advertise DX12 setup as automatic.

## MetalFX and DLSS

With the prepared D3DMetal runtime, **Use MetalFX (DLSS)** selects Apple's NGX/NVAPI bridge and exposes upscaling through the game's DLSS API. Enable DLSS in the game too. The HUD must show a MetalFX scaling input and target before an upscaling result is counted as active.

Existing environments can retain a small Wine NGX placeholder that passes direct library loading but fails Streamline's NGX discovery. Good Gameble Games replaces only the exact known placeholder with the verified bridge and preserves it as `nvngx.dll.gggmac-wine-placeholder`. Unknown DLLs or conflicting backups are not overwritten. A missing NGX model manifest is created without replacing an existing manifest.

MSync is an alternative CPU synchronization path, not an FPS guarantee. Changing it explicitly stops Windows programs in the selected environment. Automatic/Metal 3/Metal 4 select the graphics submission backend; compare them independently of resolution and game quality settings.

## Witcher compatibility copy

The supported original executable has SHA-256:

```text
2df765398a3d1f165db418271be7200178320a4466817379f2fa0dc0001fb101
```

The observed GOG 5.01 executable matches the binary described by the [community patch reference](https://github.com/lypiut/macOs-crossover-game-patch/blob/main/games/witcher-3/TECHNICAL.md). Good Gameble Games independently verifies the hash, instruction bytes, and resulting copy hash:

```text
5dc266a88709f0bfe3573ef5f5e3d055dfcd6a5a698a8ab4aa390be34015e419
```

When enabled, Good Gameble Games writes `witcher3-gggmac-metalfx.exe` beside the original and selects that copy for Play. The original is never patched, renamed, deleted or replaced. Disabling MetalFX launches the original again; the verified companion can be reused. A missing companion can be recreated, while an unknown or modified file is refused.

The compatibility copy removes three Wine-specific feature gates. Actual device capability checks remain. It does not implement unsupported graphics features. Game updates can change instruction locations, so an unfamiliar executable must receive a separately verified definition before this workaround is offered. A version label alone is insufficient.

## Observed gameplay

The only game claimed as tested for this release is the GOG Witcher 3 remaster 5.01 on an M3 Max running macOS 27.2. Development checks with optional free games do not extend that support claim. The Witcher HUD confirmed temporal MetalFX scaling from 1707×960 to a 2560×1440 target. The [README test observations](../README.md#observed-fps-and-settings-experiments) record the available FPS readings and their limitations; sustained 60 FPS at 1440p was not achieved.

This is limited hardware/build evidence. It is not a promise for other Macs, game builds or AAA titles. Ray tracing, frame generation, controllers, detached launchers and anti-cheat require their own validation. The optional [graphics diagnostics](../Tools/GraphicsProbe/README.md) verify small API operations; they are not game benchmarks.
