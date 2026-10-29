# MetalFX bridge diagnostic

Original Windows x64 diagnostic for GGGMac's user-imported Apple payload. It loads builtin NVAPI/NGX, initializes NVAPI, creates a D3D12 device, and checks successful NGX initialization and capability-parameter allocation. It does not execute temporal upscaling, frame generation, or a game benchmark.

The dynamic ABI follows the published [NGX driver interface](https://github.com/NVIDIA/DLSS/blob/main/include/nvsdk_ngx.h); vendor SDK headers and binaries are not included.

Build with Zig:

```sh
ZIG=/path/to/zig bash Tools/MetalFXProbe/build.sh
```

Output defaults to `/tmp/GGGMacMetalFXProbe.exe`. Set `GGGMAC_METALFX_PROBE_OUTPUT` to choose another path.

The opt-in test `realMetalFXBridgeAndWitcherCompatibilityCopy` requires:

- `GGGMAC_METALFX_TEST_RUNTIME`: a **disposable clone** of the prepared managed runtime, keeping its `whisky-gptk-4.6.4-beta.1-apple-4.0b3/Wine/bin/wine` layout. The test prepares bridge aliases there.
- `GGGMAC_METALFX_PROBE`: the compiled diagnostic executable.
- `GGGMAC_WITCHER_ORIGINAL`: the owner's supported original `witcher3.exe`. The test reads this file and copies it into a fresh temporary prefix; only the disposable copy receives a generated companion executable.

Run with `bash scripts/swift-tool.sh test --filter realMetalFXBridgeAndWitcherCompatibilityCopy`. Wine requires its normal local IPC permissions. The test stops only its own temporary prefix and leaves logs for inspection.

The M3 Max test on 2026-10-28 passed NVAPI initialization (0), D3D12 device creation (S_OK), NGX initialization (1) and capability allocation (1). The generated game copy matched the published patched SHA-256; original bytes and original/copy launch selection were checked. Gameplay and actual MetalFX scaling remain separate acceptance tests.

## Streamline feature discovery

`streamline.cpp` tests the owner's actual game plugins, with verbose callbacks, and queries DLSS support before and after setting the D3D12 device. Supply the public [NVIDIA Streamline headers](https://github.com/NVIDIAGameWorks/Streamline/tree/main/include) separately; they are MIT-licensed and not included in this repository. The diagnostic requests no OTA updates and loads the owner's existing plugins rather than distributing vendor binaries.

```sh
ZIG=/path/to/zig GGGMAC_STREAMLINE_HEADERS=/path/to/Streamline/include \
  bash Tools/MetalFXProbe/build-streamline.sh
```

Run the resulting `/tmp/GGGMacStreamlineProbe.exe` with the same selected runtime, Wine prefix, and MetalFX environment as the game. Its sole argument is the Windows path to the directory containing `sl.interposer.dll` and its plugins. The program prints the Streamline result, adapter identity, driver/OS requirements, and DLSS support before and after device creation. It does not start the game or render an upscaled frame.

On 2026-10-28, the fresh test prefix reported DLSS support 0 (success) both before and after device creation. The existing game prefix reported success before device creation but 32 (feature not supported) afterward: NGXCore loading rejected its stale 1,032-byte Wine `nvngx.dll` placeholder. After the hash-pinned prefix repair, the identical diagnostic returned success at both stages. This is a stricter acceptance check than direct NGX initialization alone.
