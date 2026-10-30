# Component notices

Good Gameble Games' application and original tools are provided under GPL-3.0-or-later; see [LICENSE](LICENSE) and [NOTICE](NOTICE). The three-G icon and its renderer are original project assets under the same license.

## Original Windows diagnostic

`Sources/GGGMacCore/Resources/GGGMacGraphicsProbe.exe` is compiled from this repository's original C/HLSL sources. It contains startup/runtime support supplied by the separately obtained Zig/MinGW toolchain. The accompanying [MinGW-w64 notice](licenses/MinGW-w64.txt) and [Zig notice](licenses/Zig.txt) are retained in the source and app packages. The compiler itself, DXC, vendor SDK binaries and graphics drivers are not distributed with Good Gameble Games. Rebuild details and shader provenance are in [Tools/GraphicsProbe](Tools/GraphicsProbe/README.md).

## Runtime and development components

Wine, Whisky community runtime components, DXMT, MoltenVK, OpenTTD, SDL Sopwith, LibreQuake and FTE remain subject to their upstream licenses. The player interface downloads managed Wine on request. Legacy free-game setup helpers remain in the core library for development fixtures and existing installation support; the player interface no longer offers those downloads or benchmarks. Upstream runtime/game distributions are not contained in the source or app ZIP. Existing development-game installations retain their upstream notices and manuals. Source/release URLs and integrity pins remain in the corresponding setup classes and tool documentation.

Apple's Game Porting Toolkit evaluation environment is obtained separately by the user from Apple. Apple payloads are never copied into Good Gameble Games' public artifacts. Local bridge setup uses the user's existing verified files. Consult Apple's supplied terms for that download; this project does not grant a license to redistribute it.

## Compatibility information

Supported Witcher instruction changes are documented in the independent [community patch reference](https://github.com/lypiut/macOs-crossover-game-patch/blob/main/games/witcher-3/TECHNICAL.md). Good Gameble Games implements its own hash-checked companion-copy preparation; no game executable or NVIDIA game plugin is distributed.

The optional Streamline diagnostic uses separately supplied [NVIDIA Streamline headers](https://github.com/NVIDIAGameWorks/Streamline), which carry their own MIT notice. Those headers and the owner's game plugins are not included in Good Gameble Games' app package. NGX API references do not imply that NVIDIA's proprietary SDK libraries are bundled.

Product and project names belong to their respective owners. Good Gameble Games is not affiliated with those projects or vendors.
