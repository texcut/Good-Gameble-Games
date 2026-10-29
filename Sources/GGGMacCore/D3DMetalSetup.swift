import Foundation

/// Receipt for a private runtime prepared from the pinned Wine archive and the
/// owner's Apple evaluation download. Apple binaries are never app resources.
public struct D3DMetalRuntime: Codable, Sendable {
    public static let directoryName = "whisky-gptk-4.6.4-beta.1-apple-4.0b3"
    public static let archiveSHA256 = "c8e6a10dfeb54fc16d3dd3382ee2e9d2cec3eb1f5641613cad8b07903818cb12"
    public static let dmgSHA256 = "afa311da371f5b6dd970b45378a3d3df567cc9e535818f56f9b3f9d4c9537c1d"
    public let sourceArchiveSHA256: String
    public let appleDMGSHA256: String
    public let appleVersion: String
    public let wineVersion: String
    public let files: [String: String]

    public static func directory(root: URL) -> URL {
        root.appendingPathComponent("Runtimes/\(directoryName)")
    }
    public static func executable(root: URL) -> URL { directory(root: root).appendingPathComponent("Wine/bin/wine") }

    public static func isManaged(_ executable: URL) -> Bool {
        executable.lastPathComponent == "wine" &&
            executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == directoryName
    }

    public static func receipt(for executable: URL) -> Self? {
        guard executable.lastPathComponent == "wine" else { return nil }
        let root = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard root.lastPathComponent == directoryName,
              let data = try? Data(contentsOf: root.appendingPathComponent("gggmac-d3dmetal.json")), data.count < 64_000,
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              receipt.sourceArchiveSHA256 == archiveSHA256, receipt.appleDMGSHA256 == dmgSHA256,
              receipt.appleVersion == "4.0b3", receipt.wineVersion == "wine-11.16" else { return nil }
        return receipt
    }

    public static func validate(executable: URL) throws {
        guard let receipt = receipt(for: executable) else { throw D3DMetalSetupError.runtime }
        try WineCommand.validateRuntime(executable)
        let root = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let required: Set<String> = ["Wine/bin/wine", "Wine/bin/wineserver", "WhiskyWineVersion.plist",
            "Wine/lib/external/libd3dshared.dylib", "Wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal",
            "Wine/lib/wine/x86_64-windows/d3d12.dll", "Wine/lib/wine/x86_64-windows/d3d12core.dll",
            "Wine/lib/wine/x86_64-windows/dxgi.dll"]
        guard receipt.files.count <= 100, required.isSubset(of: Set(receipt.files.keys)) else { throw D3DMetalSetupError.runtime }
        for (path, hash) in receipt.files {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(".."), !components.contains("."), !components.contains(""), !path.contains("\\"),
                  hash.count == 64, hash.allSatisfy(\.isHexDigit) else { throw D3DMetalSetupError.runtime }
            let file = root.appendingPathComponent(path).resolvingSymlinksInPath()
            guard file.path.hasPrefix(root.path + "/"),
                  (try? RuntimeInstaller.checksum(of: file)) == hash else { throw D3DMetalSetupError.runtime }
        }
        for name in ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"] {
            let file = root.appendingPathComponent("Wine/lib/wine/x86_64-unix/\(name).so")
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == "../../external/libd3dshared.dylib" else {
                throw D3DMetalSetupError.runtime
            }
        }
    }
}

/// A local handoff from the isolated graphics test. Connecting it happens in the
/// running app, so a stale in-memory library cannot overwrite an external edit.
public struct PreparedD3DMetalGame: Codable, Sendable {
    public static let filename = "prepared-d3dmetal-game.json"
    public let gameID: UUID
    public let sourceBottleID: UUID
    public let bottleID: UUID
    public let relativeExecutablePath: String

    public static func load(root: URL) throws -> Self {
        let data = try Data(contentsOf: root.appendingPathComponent(filename))
        guard data.count < 4_096 else { throw D3DMetalSetupError.environment }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func isConnected(in library: Library) -> Bool {
        library.games.contains { $0.id == gameID && $0.bottleID == bottleID }
    }

    public func connecting(to library: Library, root: URL) throws -> Library {
        let components = relativeExecutablePath.split(separator: "/", omittingEmptySubsequences: false)
        guard sourceBottleID != bottleID, components.first == "drive_c", !components.contains(".."),
              !components.contains("."), !components.contains(""), !relativeExecutablePath.contains("\\"),
              relativeExecutablePath.lowercased().hasSuffix(".exe"),
              let index = library.games.firstIndex(where: { $0.id == gameID }),
              library.bottles.contains(where: { $0.id == sourceBottleID }) else { throw D3DMetalSetupError.environment }
        let runtimeURL = D3DMetalRuntime.executable(root: root)
        try D3DMetalRuntime.validate(executable: runtimeURL)
        let prefix = root.appendingPathComponent("Bottles/\(bottleID.uuidString)").resolvingSymlinksInPath()
        let expectedPrefix = root.resolvingSymlinksInPath().appendingPathComponent("Bottles/\(bottleID.uuidString)")
        guard prefix.path == expectedPrefix.path else { throw D3DMetalSetupError.environment }
        try WineCommand.validatePrefix(prefix)
        let executable = prefix.appendingPathComponent(relativeExecutablePath).resolvingSymlinksInPath()
        guard executable.path.hasPrefix(prefix.path + "/"), (try? executable.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            throw D3DMetalSetupError.environment
        }
        if isConnected(in: library) {
            guard let bottle = library.bottles.first(where: { $0.id == bottleID }),
                  ExecutableIdentity.matches(bottle.runtime.executable, runtimeURL), bottle.activeGraphicsBackend == .runtimeDefault,
                  ExecutableIdentity.matches(library.games[index].executable, executable) else { throw D3DMetalSetupError.environment }
            return library
        }
        let originalPrefix = root.appendingPathComponent("Bottles/\(sourceBottleID.uuidString)")
        guard library.games[index].bottleID == sourceBottleID,
              ExecutableIdentity.matches(library.games[index].executable, originalPrefix.appendingPathComponent(relativeExecutablePath)),
              !library.bottles.contains(where: { $0.id == bottleID }) else { throw D3DMetalSetupError.environment }
        var updated = library
        let runtime = WineRuntime(executable: runtimeURL, version: "wine-11.16 · Apple D3DMetal 4.0b3")
        updated.bottles.append(Bottle(id: bottleID, name: "\(library.games[index].name) · D3DMetal", runtime: runtime))
        updated.games[index].bottleID = bottleID
        updated.games[index].executable = executable
        updated.games[index].lastPlayed = nil
        updated.games[index].lastRendererReport = nil
        updated.games[index].lastBenchmark = nil
        return updated
    }
}

public enum D3DMetalSetupError: LocalizedError {
    case runtime, environment
    public var errorDescription: String? {
        switch self {
        case .runtime: "The prepared D3DMetal runtime is missing or changed. Its original files have been preserved. Prepare and verify the runtime again before connecting it."
        case .environment: "The prepared D3DMetal game environment does not match this library. No library changes were saved."
        }
    }
}
