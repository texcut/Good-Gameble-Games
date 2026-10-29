# Windows graphics diagnostic

`probe.c`, `d3d12_probe.h`, `d3d12_present.h` and the minimal shaders are original GGGMac code under GPL-3.0-or-later. The checked-in Windows x86-64 executable in `Sources/GGGMacCore/Resources/` is built from these files. It needs no game assets, compiler download or network access at runtime. SwiftPM includes it for development/tests; the app packager copies it into the app's signed Resources directory.

Rebuild with the official [Zig compiler](https://ziglang.org/download/) installed separately:

```sh
ZIG=/absolute/path/to/zig bash Tools/GraphicsProbe/build.sh
```

The development build used Zig 0.17.0 for aarch64 macOS, SHA-256 `b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a` for the official toolchain archive. The compiler is not bundled or needed to build the Swift application when using the checked-in diagnostic executable. Zig's Windows SDK/MinGW headers and CRT supply startup support; Windows API DLLs are resolved from the user's Wine runtime. The compiler/toolchain's component notices remain applicable; see [MinGW-w64 notices](https://github.com/mingw-w64/mingw-w64/blob/master/COPYING).

Modes:

- `opengl`: create a hidden Windows surface and request a 3.2 core context in the form used by OpenTTD. If accepted, clear/read a pixel and report the driver. If rejected, retry with the forward-compatible flag for diagnosis; a passing retry does not turn the original failed request into a pass.
- `d3d11`: dynamically load `D3D11CreateDevice`, request a hardware device at feature level 11.0/10.1/10.0, clear a 4×4 RGBA render target, copy it to a staging texture and verify a mapped pixel. Report the DXGI adapter name and negotiated feature level.
- `d3d12`: dynamically load `D3D12CreateDevice`, select a DXGI adapter without the software flag, and request a feature-level 11.0 device. Query advertised feature levels, shader model, binding tier and ray-tracing tier independently. Compile original minimal SM 5.0 vertex/pixel shaders using the runtime's `d3dcompiler_47.dll`, serialize an empty root signature, create a graphics pipeline, clear a 4×4 render target to black and draw a full-screen triangle with a known color. Transition the texture, copy it to a readback buffer, signal/wait for a fence, and verify the pixel. The optimized clear value is also black, so a missing draw cannot pass by returning the clear color. Report the Windows adapter name, builtin/external D3D12 implementation and advertised capabilities. GPU completion has a 15-second timeout; the host process has a 45-second timeout. Pending GPU resources are left to process teardown on timeout/device loss rather than freed while in use.
- `d3d12-dxil`: execute the same offscreen draw using embedded SM 6.0/DXIL vertex and pixel shaders compiled from our own `shaders/triangle.hlsl`. This does not fall back to SM 5.0 if DXIL fails. Pipeline creation alone cannot pass: the shader-written pixel must match after GPU execution and readback.
- `d3d12-present`: open a fixed 640×360 window and use those SM 6.0/DXIL shaders in a two-buffer flip-discard swap chain. For each of 60 frames, transition the active back buffer, clear it to black, draw, copy it to readback, return it to PRESENT state, wait for the GPU and verify its pixel. Require `Present(1, 0)` to return exactly `S_OK`; occlusion statuses do not count. Wait for final queued presentation before releasing resources. Report the successful-present count; early closure/minimization, a partial run, device loss or timeout cannot pass. The window closes itself. This is API-level presentation plus back-buffer verification, not a screenshot or human visual check. Normal Check graphics remains offscreen; the app's Run window test explicitly opts in.

Each mode prints one `GGGMAC_GRAPHICS_JSON:` line. Capability failures produce `passed: false` with a zero process exit status; a nonzero exit or missing/malformed JSON is a diagnostic failure. The Swift reader keeps these outcomes distinct.

These are **64-bit checks**. Shader-model advertisement, SM 5.0 execution, SM 6.0/DXIL execution and window presentation are separate results. Only `d3d12-present` opens a visible window. The checks do not establish full shader functionality, visual correctness, 32-bit graphics, long-term stability, game compatibility, ray tracing or FPS. The Windows adapter name may be a Wine compatibility identity; it is not an independent physical-GPU inventory. The diagnostic does not edit game configurations or saved games. It may initialize Wine's graphics modules and produce driver caches/logs.

## Rebuilding the DXIL shaders

The checked-in `shaders/triangle_dxil.h` contains only compiled output from our original shader source. DXC is a development tool and is not shipped in the app. To regenerate with Microsoft's official [DirectX Shader Compiler](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2609), use the native compiler or run its Windows x64 build through a complete Wine distribution:

```sh
python3 Tools/GraphicsProbe/build-dxil.py \
  --dxc /absolute/path/to/bin/x64/dxc.exe \
  --wine /absolute/path/to/Wine/bin/wine
ZIG=/absolute/path/to/zig bash Tools/GraphicsProbe/build.sh
```

The script creates and removes a dedicated temporary prefix, compiles `vs_main`/`ps_main` with targets `vs_6_0`/`ps_6_0`, strips debug/reflection data, validates that each output container contains a DXIL chunk, and publishes the C header atomically. Without `--wine`, `--dxc` runs directly. Microsoft's Windows ZIP uses backslashes in paths; unpack it with a tool that normalizes Windows ZIP paths, or place the `bin/x64` files together manually.

Provenance for the checked-in shader output:

- Microsoft DXC `v1.9.2609`, Windows x64, reported version `1.9.2609.5 (01b62ad47)`.
- Official `dxc_2026_09_29.zip`: SHA-256 `ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1`, matched to the GitHub release digest.
- Vertex DXIL, 1,644 bytes: SHA-256 `66ed4994446ab232b18dc947636cf1a7a9e4f49432461da8b382d21161f456b6`.
- Pixel DXIL, 1,432 bytes: SHA-256 `dd2e3e11969ad061e86505bff7cefc09bbdb7974922333a4290fb171499e8c8c`.
- The generated header records the input HLSL source checksum. Compiler notices remain with the separately downloaded DXC distribution; no DXC libraries or Microsoft shader samples are bundled.

Primary API references: [D3D11CreateDevice](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-d3d11createdevice), [Map](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-map), [D3D12 swap chains and presentation](https://learn.microsoft.com/en-us/windows/win32/direct3d12/swap-chains). The OpenTTD context comparison follows [its Windows driver](https://github.com/OpenTTD/OpenTTD/blob/15.3/src/video/win32_v.cpp) and [OpenGL requirements](https://github.com/OpenTTD/OpenTTD/blob/15.3/src/video/opengl.cpp). DXMT's documented [native/builtin variants](https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks) have different installation rules; GGGMac supports only the native payload in its pinned managed runtime.
