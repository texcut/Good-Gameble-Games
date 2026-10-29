import Foundation

public struct WineCommand: Sendable {
    public static let smokeMarker = "GGGMAC_WINDOWS_SMOKE_OK"
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?

    public init(executable: URL, arguments: [String], prefix: URL? = nil,
                workingDirectory: URL? = nil, inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
                graphics: GraphicsBackend = .runtimeDefault, profile: GameLaunchProfile? = nil,
                d3dMetalOptions: D3DMetalOptions? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        // Do not inherit settings that might redirect a launch into another Wine prefix.
        var environment = inheritedEnvironment.filter {
            !$0.key.hasPrefix("WINE") && !["DXVK_CONFIG_FILE", "WINEDLLOVERRIDES", "D3DMETAL", "DXVK_ASYNC", "SDL_RENDER_DRIVER", "SDL_LOGGING"].contains($0.key)
        }
        if let prefix { environment["WINEPREFIX"] = prefix.path }
        environment["WINEDEBUG"] = "-all,err+all"
        if D3DMetalRuntime.isManaged(executable) {
            for key in ["D3DM_SUPPORT_DXR", "D3DM_ENABLE_METALFX", "ROSETTA_ADVERTISE_AVX", "D3DM_MTL4", "MTL_HUD_ENABLED",
                        "MTL_HUD_LOG_ENABLED", "MTL_HUD_LOGGING_ENABLED", "MTL_HUD_LOG_SHADER_ENABLED"] {
                environment.removeValue(forKey: key)
            }
            environment.merge((d3dMetalOptions ?? D3DMetalOptions()).environment) { _, selected in selected }
            if d3dMetalOptions?.metalFXEnabled == true {
                environment["WINEDLLOVERRIDES"] = "nvapi64,nvngx=b"
            }
        }
        if profile == .sdlDirect3D11 {
            environment["SDL_RENDER_DRIVER"] = "direct3d11"
            environment["SDL_LOGGING"] = "render=info"
            environment["WINEDEBUG"] = "-all,err+all,trace+debugstr"
        }
        // Keep warnings and errors visible without the full Vulkan extension list.
        if environment["MVK_CONFIG_LOG_LEVEL"] == nil { environment["MVK_CONFIG_LOG_LEVEL"] = "2" }
        if graphics == .dxmt { environment["WINEDLLOVERRIDES"] = "d3d11,dxgi,d3d10core=n,b;winemetal=b" }
        let bin = executable.deletingLastPathComponent().path
        environment["PATH"] = bin + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        self.environment = environment
    }

    public static func validateRuntime(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard ["wine", "wine64"].contains(url.lastPathComponent),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path) else { throw LauncherError.invalidRuntime }
    }

    public static func launch(runtime: WineRuntime, game: Game, prefix: URL, graphics: GraphicsBackend = .runtimeDefault,
                              d3dMetalOptions: D3DMetalOptions? = nil) throws -> WineCommand {
        try validateRuntime(runtime.executable)
        var isDirectory: ObjCBool = false
        guard game.executable.pathExtension.lowercased() == "exe",
              FileManager.default.fileExists(atPath: game.executable.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { throw LauncherError.invalidExecutable }
        try validatePrefix(prefix)
        var target = game.executable
        if D3DMetalRuntime.isManaged(runtime.executable), d3dMetalOptions?.metalFXEnabled == true {
            try MetalFXBridge.validate(executable: runtime.executable)
            if WitcherMetalFXPatch.isCandidate(game.executable) {
                target = try WitcherMetalFXPatch.preparedExecutable(for: game.executable)
            }
        }
        guard game.launchProfile?.requiresDXMT != true || graphics == .dxmt else {
            throw LauncherError.gameSetupFailed("Choose DXMT in this environment’s Windows graphics settings before running the Direct3D 11 test.")
        }
        return WineCommand(executable: runtime.executable, arguments: [target.path] + game.arguments,
                           prefix: prefix, workingDirectory: game.executable.deletingLastPathComponent(), graphics: graphics,
                           profile: game.launchProfile, d3dMetalOptions: d3dMetalOptions)
    }

    public static func smokeTest(bottle: Bottle, prefix: URL) throws -> WineCommand {
        try validateRuntime(bottle.runtime.executable)
        try validatePrefix(prefix)
        // Fixed Windows command, with no user input. /d disables cmd AutoRun hooks.
        return WineCommand(executable: bottle.runtime.executable,
                           arguments: ["cmd.exe", "/d", "/c", "echo \(smokeMarker) & ver"], prefix: prefix,
                           d3dMetalOptions: bottle.d3dMetalOptions)
    }

    public static func validatePrefix(_ prefix: URL) throws {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        // A newly initialized Wine server can keep the registry in memory until
        // its next flush. The installed Windows command interpreter also proves
        // that bootstrapping completed, without waiting for system.reg to appear.
        guard manager.fileExists(atPath: prefix.appendingPathComponent("drive_c").path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              manager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) ||
                manager.fileExists(atPath: prefix.appendingPathComponent("drive_c/windows/system32/cmd.exe").path) else {
            throw LauncherError.missingBottle
        }
    }
}
