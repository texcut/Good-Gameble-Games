# Development

## Layout

- `Sources/GGGMac`: SwiftUI application and main-actor orchestration.
- `Sources/GGGMacCore`: library storage, runtime setup, environment isolation, verified file deployment, process execution and diagnostics.
- `Tests/GGGMacCoreTests`: synthetic fixtures and opt-in real-runtime checks.
- `Tools/GraphicsProbe`: original Windows graphics diagnostic, shader sources and build recipe.
- `Tools/MetalFXProbe`: NGX and Streamline diagnostics; vendor/game binaries are not included.
- `Tools/AppIcon`: dependency-free rendering of the three-G icon.
- `assets`: editable SVG, preview PNG and macOS ICNS.

SwiftPM has no external package dependencies. The original checked-in `GGGMacGraphicsProbe.exe` is a build resource with corresponding source and rebuild instructions. Other Windows executables, Wine engines, Apple payloads and game assets do not belong in the repository.

## Build and test

```sh
bash scripts/swift-tool.sh test
bash scripts/build-app.sh             # debug app
bash scripts/build-app.sh release     # optimized app
```

`GGGMAC_BUILD_DIR` selects another scratch/cache directory. The helper accommodates standalone Command Line Tools installations whose Swift Testing macro plugin is not discovered automatically. Its SwiftPM `--disable-sandbox` flag concerns the nested package build sandbox, not macOS app security. There are no package build plugins.

Normal tests use fixtures and do not download or execute Wine. Real integration tests are disabled until their explicit environment variables are supplied. Do not run integration tests against someone else's active game environment.

## Optional real-runtime checks

- Basic Wine commands: `GGGMAC_INTEGRATION_ARCHIVE` or `GGGMAC_INTEGRATION_WINE`, filter `realWineExecutesWindowsCommand`.
- DXMT deployment: `GGGMAC_GRAPHICS_RUNTIME`, filter `realDXMTMetalReadbackAndRestore`.
- D3D12: `GGGMAC_D3D12_RUNTIME`, filter `realDirect3D12CapabilityCheck`. `GGGMAC_EXPECT_D3D12`, `GGGMAC_EXPECT_DXIL` and `GGGMAC_EXPECT_PRESENTATION` require those checks to pass; presentation additionally requires `GGGMAC_D3D12_PRESENTATION=1`.
- Sopwith: `GGGMAC_SOPWITH_RUNTIME`, `GGGMAC_SOPWITH_ARCHIVE`, filter `realSopwithCreatesDirect3D11Renderer`.
- LibreQuake: `GGGMAC_3D_RUNTIME`, `GGGMAC_3D_ENGINE`, `GGGMAC_3D_DATA`, filter `realLibreQuakeDirect3D11Benchmark`.
- D3DMetal option transitions: `GGGMAC_SERVER_TEST_RUNTIME`, filter `realWineServerIdleAndMSyncTransitions`.
- MetalFX: see [bridge diagnostics](../Tools/MetalFXProbe/README.md). Use a disposable runtime clone for `realMetalFXBridgeAndWitcherCompatibilityCopy`.

Most integration checks create temporary environments. Some explicitly named checks operate on a supplied prepared setup; read their source before selecting that input. In particular, `realExistingMetalFXPrefixRepair` deliberately repairs the specified prefix's managed NGX entries and is not a read-only test. Never use blanket integration environment settings in CI or a normal test run.

## Asset generation

The normal Swift build uses checked-in assets; it does not need Zig, DXC, or icon rendering tools.

```sh
swift Tools/AppIcon/generate.swift assets
```

The icon renderer produces standard PNG sizes and invokes macOS `iconutil`. `assets/AppIcon.svg` is the editable vector reference. See the tool READMEs for the graphics probe's Zig/DXC provenance and the optional Streamline headers.

## Data guarantees

Library saves are atomic. Schema upgrades preserve the previous library. Damaged or newer libraries are reported instead of silently replaced. Runtime and graphics setup checks receipts and paths before publishing files; unknown edits remain intact.

Games use explicit `WINEPREFIX` values and the executable's directory as working directory. Environment variables that could redirect Wine are filtered. Process output is file-backed to avoid pipe deadlocks. One foreground operation is supported. Launch tracking follows the initial Wine process; detached child launchers are a known limitation.

Keep diagnostic logging and compatibility details behind explicit actions. A successful API probe is not proof of game rendering, stability or performance. See [contributing](../CONTRIBUTING.md) before changing runtime or compatibility behavior.

## Isolated interface previews

Debug builds accept `GGGMAC_PREVIEW_ROOT` as an absolute directory for a temporary library. Release builds ignore it. This supports manual checks of empty and populated libraries without changing the real application data:

```sh
bash scripts/build-app.sh debug
GGGMAC_PREVIEW_ROOT=/tmp/gggmac-empty-preview "dist/Good Gameble Games.app/Contents/MacOS/GGGMac"
```

Use temporary fixtures for a returning library; never put private library data in the repository. The main page derives setup progress from saved runtime/environment/game records. Logs is a separate SwiftUI window sharing the same model. Legacy renderer profiles and their core fixtures are retained for already installed entries, but demo download and benchmark controls have been removed from the application.
