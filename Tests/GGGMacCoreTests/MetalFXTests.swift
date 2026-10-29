import Foundation
import Testing
@testable import GGGMacCore

private struct MetalFXFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac MetalFX tests \(UUID().uuidString)")
    var runtime: URL { D3DMetalRuntime.executable(root: root) }
    var runtimeRoot: URL { D3DMetalRuntime.directory(root: root) }
    init() throws {
        let paths = ["Wine/bin/wine", "Wine/bin/wineserver", "WhiskyWineVersion.plist", "Wine/lib/external/libd3dshared.dylib",
            "Wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal", "Wine/lib/wine/x86_64-windows/d3d12.dll",
            "Wine/lib/wine/x86_64-windows/d3d12core.dll", "Wine/lib/wine/x86_64-windows/dxgi.dll",
            "Wine/lib/wine/x86_64-windows/nvngx-on-metalfx.dll", "Wine/lib/wine/x86_64-windows/nvapi64.dll"]
        var hashes: [String: String] = [:]
        for path in paths {
            let file = runtimeRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: file)
            hashes[path] = try RuntimeInstaller.checksum(of: file)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        let unix = runtimeRoot.appendingPathComponent("Wine/lib/wine/x86_64-unix")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        for name in ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi", "nvapi64", "nvngx-on-metalfx"] {
            try FileManager.default.createSymbolicLink(atPath: unix.appendingPathComponent(name + ".so").path,
                withDestinationPath: "../../external/libd3dshared.dylib")
        }
        let receipt = D3DMetalRuntime(sourceArchiveSHA256: D3DMetalRuntime.archiveSHA256, appleDMGSHA256: D3DMetalRuntime.dmgSHA256,
            appleVersion: "4.0b3", wineVersion: "wine-11.16", files: hashes)
        try JSONEncoder().encode(receipt).write(to: runtimeRoot.appendingPathComponent("gggmac-d3dmetal.json"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func metalFXPreparesOnlyVerifiedBridgeAndRefusesChangedAliases() throws {
    let f = try MetalFXFixture(); defer { f.clean() }
    #expect(throws: (any Error).self) { try MetalFXBridge.validate(executable: f.runtime) }
    try MetalFXBridge.prepare(executable: f.runtime)
    try MetalFXBridge.prepare(executable: f.runtime)
    try MetalFXBridge.validate(executable: f.runtime)
    try D3DMetalRuntime.validate(executable: f.runtime)
    let dll = f.runtimeRoot.appendingPathComponent("Wine/lib/wine/x86_64-windows/nvngx.dll")
    let unix = f.runtimeRoot.appendingPathComponent("Wine/lib/wine/x86_64-unix/nvngx.so")
    try FileManager.default.removeItem(at: unix)
    try FileManager.default.createSymbolicLink(atPath: unix.path, withDestinationPath: "/tmp/outside.so")
    #expect(throws: (any Error).self) { try MetalFXBridge.prepare(executable: f.runtime) }
    #expect(throws: (any Error).self) { try MetalFXBridge.validate(executable: f.runtime) }
    try Data("foreign bridge".utf8).write(to: dll)
    #expect(throws: (any Error).self) { try MetalFXBridge.prepare(executable: f.runtime) }
    #expect(try Data(contentsOf: dll) == Data("foreign bridge".utf8))
}

@Test func metalFXEnvironmentIsExplicitAndLegacyControlsDecodeWithoutIt() throws {
    let f = try MetalFXFixture(); defer { f.clean() }
    let legacy = Data(#"{"rayTracingEnabled":false,"msyncEnabled":true,"backend":"metal3","showPerformanceHUD":true}"#.utf8)
    #expect(try JSONDecoder().decode(D3DMetalOptions.self, from: legacy).metalFXEnabled == false)
    let on = D3DMetalOptions(metalFXEnabled: true)
    #expect(try JSONDecoder().decode(D3DMetalOptions.self, from: JSONEncoder().encode(on)) == on)
    let enabled = WineCommand(executable: f.runtime, arguments: [], d3dMetalOptions: on)
    #expect(enabled.environment["D3DM_ENABLE_METALFX"] == "1")
    #expect(enabled.environment["WINEDLLOVERRIDES"] == "nvapi64,nvngx=b")
    let off = WineCommand(executable: f.runtime, arguments: [], inheritedEnvironment: ["D3DM_ENABLE_METALFX": "1", "WINEDLLOVERRIDES": "nvngx=n"])
    #expect(off.environment["D3DM_ENABLE_METALFX"] == "0")
    #expect(off.environment["WINEDLLOVERRIDES"] == nil)
}

@Test func compatibilityCopyPreservesOriginalAndRejectsForeignCopies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac patch tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("game.exe")
    let original = Data([0, 1, 2, 3, 4, 5]), patched = Data([0, 1, 9, 8, 4, 5])
    let patch = VerifiedExecutableCopy(originalHash: VerifiedExecutableCopy.hash(original), patchedHash: VerifiedExecutableCopy.hash(patched),
        changes: [(2, [2, 3], [9, 8])])
    try original.write(to: executable)
    let modification = try FileManager.default.attributesOfItem(atPath: executable.path)[.modificationDate] as? Date
    try patch.setEnabled(true, executable: executable)
    try patch.setEnabled(true, executable: executable)
    try patch.validate(executable)
    #expect(try Data(contentsOf: executable) == original)
    #expect(try FileManager.default.attributesOfItem(atPath: executable.path)[.modificationDate] as? Date == modification)
    #expect(try Data(contentsOf: patch.destination(executable)) == patched)
    try patch.setEnabled(false, executable: executable)
    #expect(!FileManager.default.fileExists(atPath: patch.destination(executable).path))
    #expect(try Data(contentsOf: executable) == original)
    try Data("foreign file".utf8).write(to: patch.destination(executable))
    #expect(throws: (any Error).self) { try patch.setEnabled(true, executable: executable) }
    #expect(throws: (any Error).self) { try patch.setEnabled(false, executable: executable) }
    #expect(try Data(contentsOf: executable) == original)
    try FileManager.default.removeItem(at: patch.destination(executable))
    try FileManager.default.createSymbolicLink(at: patch.destination(executable), withDestinationURL: executable)
    #expect(throws: (any Error).self) { try patch.setEnabled(true, executable: executable) }
    #expect(try Data(contentsOf: executable) == original)
    try FileManager.default.removeItem(at: patch.destination(executable))
    let updated = Data("an unsupported game update".utf8)
    try updated.write(to: executable)
    #expect(throws: (any Error).self) { try patch.setEnabled(true, executable: executable) }
    #expect(try Data(contentsOf: executable) == updated)
    #expect(!FileManager.default.fileExists(atPath: patch.destination(executable).path))
}

@Test func schemaFourMetalFXMigrationBacksUpBeforeFirstSave() throws {
    let f = try MetalFXFixture(); defer { f.clean() }
    let store = LibraryStore(root: f.root)
    var library = Library()
    library.bottles = [Bottle(name: "Existing", runtime: WineRuntime(executable: f.runtime, version: "test"))]
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    json["schemaVersion"] = 4
    let data = try JSONSerialization.data(withJSONObject: json)
    try data.write(to: store.libraryURL)
    var migrated = try store.load()
    #expect(migrated.schemaVersion == 5)
    migrated.bottles[0].d3dMetalOptions = D3DMetalOptions(metalFXEnabled: true)
    try store.save(migrated)
    #expect(try Data(contentsOf: f.root.appendingPathComponent("library-v4.backup.json")) == data)
    #expect(try store.load().bottles[0].d3dMetalOptions?.metalFXEnabled == true)
}

@Test func metalFXSetupRequiresAValidSelectedGameBeforeItCanBeSaved() throws {
    let f = try MetalFXFixture(); defer { f.clean() }
    let prefix = f.root.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    try Data().write(to: prefix.appendingPathComponent("system.reg"))
    let runtime = WineRuntime(executable: f.runtime, version: "fixture")
    let missing = Game(name: "Missing game", executable: prefix.appendingPathComponent("missing.exe"), bottleID: UUID())
    #expect(throws: (any Error).self) {
        try MetalFXGameSetup.prepare(runtime: runtime, game: missing, prefix: prefix, options: D3DMetalOptions(metalFXEnabled: true))
    }
    let gameURL = prefix.appendingPathComponent("game.exe")
    try Data("fixture game".utf8).write(to: gameURL)
    let game = Game(name: "Selected game", executable: gameURL, bottleID: missing.bottleID)
    try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: D3DMetalOptions(metalFXEnabled: true))
    let manifest = prefix.appendingPathComponent("drive_c/ProgramData/NVIDIA/NGX/models/nvngx_config.txt")
    #expect(FileManager.default.fileExists(atPath: manifest.path))
    try Data("user manifest".utf8).write(to: manifest)
    try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: D3DMetalOptions(metalFXEnabled: true))
    #expect(try Data(contentsOf: manifest) == Data("user manifest".utf8))
    let command = try WineCommand.launch(runtime: runtime, game: game, prefix: prefix, d3dMetalOptions: D3DMetalOptions(metalFXEnabled: true))
    #expect(command.arguments.first == gameURL.path)
}

@Test func metalFXPrefixReplacesOnlyKnownStubAndPreservesBackupAndForeignFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac NGX prefix tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("apple.dll"), target = root.appendingPathComponent("nvngx.dll")
    let stub = Data("known Wine stub".utf8), bridge = Data("verified bridge".utf8)
    let stubHash = VerifiedExecutableCopy.hash(stub)
    try bridge.write(to: source); try stub.write(to: target)
    try MetalFXPrefix.installCoreDLL(source: source, destination: target, placeholderHash: stubHash)
    let backup = target.appendingPathExtension("gggmac-wine-placeholder")
    #expect(try Data(contentsOf: target) == bridge)
    #expect(try Data(contentsOf: backup) == stub)
    try MetalFXPrefix.installCoreDLL(source: source, destination: target, placeholderHash: stubHash)
    #expect(try Data(contentsOf: backup) == stub)
    try Data("foreign DLL".utf8).write(to: target)
    #expect(throws: (any Error).self) { try MetalFXPrefix.installCoreDLL(source: source, destination: target, placeholderHash: stubHash) }
    #expect(try Data(contentsOf: target) == Data("foreign DLL".utf8))
    try stub.write(to: target); try Data("changed backup".utf8).write(to: backup)
    #expect(throws: (any Error).self) { try MetalFXPrefix.installCoreDLL(source: source, destination: target, placeholderHash: stubHash) }
    #expect(try Data(contentsOf: target) == stub)
}

/// Explicit repair check: writes only the named prefix's managed NGX entries.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_METALFX_REPAIR_PREFIX"] != nil))
func realExistingMetalFXPrefixRepair() throws {
    let env = ProcessInfo.processInfo.environment
    let prefix = URL(fileURLWithPath: try #require(env["GGGMAC_METALFX_REPAIR_PREFIX"]))
    let executable = URL(fileURLWithPath: try #require(env["GGGMAC_METALFX_REPAIR_RUNTIME"]))
    let runtime = WineRuntime(executable: executable, version: "prefix repair")
    let source = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/wine/x86_64-windows/nvngx.dll")
    let dll = prefix.appendingPathComponent("drive_c/windows/system32/nvngx.dll")
    let sourceHash = try RuntimeInstaller.checksum(of: source)
    let oldHash = try RuntimeInstaller.checksum(of: dll)
    try #require([sourceHash, MetalFXPrefix.knownPlaceholderSHA256].contains(oldHash))
    try MetalFXPrefix.prepare(runtime: runtime, prefix: prefix)
    #expect(try RuntimeInstaller.checksum(of: dll) == sourceHash)
    if oldHash == MetalFXPrefix.knownPlaceholderSHA256 {
        #expect(try RuntimeInstaller.checksum(of: dll.appendingPathExtension("gggmac-wine-placeholder")) == oldHash)
    }
    try MetalFXPrefix.prepare(runtime: runtime, prefix: prefix)
    print("Existing prefix NGX repaired and verified:", dll.path)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_METALFX_TEST_RUNTIME"] != nil))
func realMetalFXBridgeAndWitcherCompatibilityCopy() async throws {
    let env = ProcessInfo.processInfo.environment
    let runtimeURL = URL(fileURLWithPath: try #require(env["GGGMAC_METALFX_TEST_RUNTIME"]))
    let probe = URL(fileURLWithPath: try #require(env["GGGMAC_METALFX_PROBE"]))
    let original = URL(fileURLWithPath: try #require(env["GGGMAC_WITCHER_ORIGINAL"]))
    let originalHash = try RuntimeInstaller.checksum(of: original)
    try #require(originalHash == WitcherMetalFXPatch.originalSHA256)
    try MetalFXBridge.prepare(executable: runtimeURL)
    try MetalFXBridge.validate(executable: runtimeURL)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac real MetalFX \(UUID().uuidString)")
    let prefix = root.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let runtime = WineRuntime(executable: runtimeURL, version: "MetalFX test")
    let options = D3DMetalOptions(backend: .metal3, metalFXEnabled: true)
    var bottle = Bottle(name: "MetalFX test", runtime: runtime); bottle.d3dMetalOptions = options
    let runner = ProcessRunner()
    do {
        let boot = try await runner.run(WineCommand(executable: runtimeURL, arguments: ["wineboot", "--init"], prefix: prefix,
            d3dMetalOptions: options), logURL: root.appendingPathComponent("boot.log"), timeout: .seconds(180))
        try #require(boot.exitCode == 0, "Logs: \(root.path)")
        let exe = prefix.appendingPathComponent("drive_c/GOG Games/Witcher/bin/x64_dx12/witcher3.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: exe)
        let game = Game(name: "Witcher", executable: exe, bottleID: bottle.id, arguments: ["literal argument"])
        #expect(throws: (any Error).self) {
            try WineCommand.launch(runtime: runtime, game: game, prefix: prefix, d3dMetalOptions: options)
        }
        try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: options)
        let copy = try WitcherMetalFXPatch.preparedExecutable(for: exe)
        #expect(try RuntimeInstaller.checksum(of: copy) == WitcherMetalFXPatch.patchedSHA256)
        // Reproduce an enabled setting whose generated executable disappeared.
        try FileManager.default.removeItem(at: copy)
        try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: options)
        #expect(try RuntimeInstaller.checksum(of: copy) == WitcherMetalFXPatch.patchedSHA256)
        let launch = try WineCommand.launch(runtime: runtime, game: game, prefix: prefix, d3dMetalOptions: options)
        #expect(launch.arguments == [copy.path, "literal argument"])
        #expect(launch.workingDirectory == exe.deletingLastPathComponent())
        #expect(try WineCommand.launch(runtime: runtime, game: game, prefix: prefix).arguments.first == exe.path)
        let bridgeGame = Game(name: "Bridge probe", executable: probe, bottleID: bottle.id)
        let result = try await runner.run(WineCommand.launch(runtime: runtime, game: bridgeGame, prefix: prefix, d3dMetalOptions: options),
            logURL: root.appendingPathComponent("bridge.log"), timeout: .seconds(90))
        try #require(result.exitCode == 0, "Logs: \(root.path)\n\(LogReader.tail(result.logURL))")
        #expect(LogReader.tail(result.logURL).contains("GGGMAC_METALFX_BRIDGE_OK"))
        try WitcherMetalFXPatch.setEnabled(false, executable: exe)
        #expect(try RuntimeInstaller.checksum(of: exe) == originalHash)
        #expect(try RuntimeInstaller.checksum(of: original) == originalHash)
        try await WineServer.stop(runtime: runtime, prefix: prefix, logURL: root.appendingPathComponent("stop.log"))
        print("MetalFX bridge initialized; compatibility copy and original routing verified. Logs:", root.path)
    } catch {
        try? await WineServer.stop(runtime: runtime, prefix: prefix, logURL: root.appendingPathComponent("stop-error.log"))
        throw error
    }
}
