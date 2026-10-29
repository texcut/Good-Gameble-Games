import Foundation

/// Shared by Save and Play: an enabled option alone does not prove setup exists.
public enum MetalFXGameSetup {
    public static func prepare(runtime: WineRuntime, game: Game, prefix: URL, options: D3DMetalOptions) throws {
        guard options.metalFXEnabled else { return }
        try WineCommand.validatePrefix(prefix)
        if WitcherMetalFXPatch.isCandidate(game.executable) {
            guard game.executable.resolvingSymlinksInPath().path.hasPrefix(prefix.resolvingSymlinksInPath().path + "/") else {
                throw MetalFXError.unsupportedGame
            }
        }
        try MetalFXBridge.prepare(executable: runtime.executable)
        try MetalFXPrefix.prepare(runtime: runtime, prefix: prefix)
        if WitcherMetalFXPatch.isCandidate(game.executable) {
            try WitcherMetalFXPatch.setEnabled(true, executable: game.executable)
        }
        // Validate the exact target and bridge before settings may be committed.
        _ = try WineCommand.launch(runtime: runtime, game: game, prefix: prefix, d3dMetalOptions: options)
    }
}
