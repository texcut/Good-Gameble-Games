import Foundation
import Testing
@testable import GGGMacCore

private struct D3DMetalFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac D3DMetal setup \(UUID().uuidString)")
    let sourceID = UUID(), targetID = UUID(), gameID = UUID()
    let relative = "drive_c/GOG Games/Witcher 3/bin/x64_dx12/witcher3.exe"
    var setup: PreparedD3DMetalGame {
        PreparedD3DMetalGame(gameID: gameID, sourceBottleID: sourceID, bottleID: targetID, relativeExecutablePath: relative)
    }
    var runtime: URL { D3DMetalRuntime.executable(root: root) }
    var library: Library {
        let original = WineRuntime(executable: root.appendingPathComponent("stock/bin/wine"), version: "stock")
        var library = Library(); library.runtime = original
        library.bottles = [Bottle(id: sourceID, name: "Original", runtime: original)]
        library.games = [Game(id: gameID, name: "The Witcher 3", executable: root.appendingPathComponent("Bottles/\(sourceID.uuidString)/\(relative)"),
                              bottleID: sourceID, arguments: ["literal argument"])]
        return library
    }
    init() throws {
        for id in [sourceID, targetID] {
            _ = try file("Bottles/\(id.uuidString)/\(relative)")
            _ = try file("Bottles/\(id.uuidString)/system.reg")
        }
        let directory = D3DMetalRuntime.directory(root: root)
        let paths = ["Wine/bin/wine", "Wine/bin/wineserver", "WhiskyWineVersion.plist", "Wine/lib/external/libd3dshared.dylib",
            "Wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal", "Wine/lib/wine/x86_64-windows/d3d12.dll",
            "Wine/lib/wine/x86_64-windows/d3d12core.dll", "Wine/lib/wine/x86_64-windows/dxgi.dll"]
        var hashes: [String: String] = [:]
        for path in paths {
            let url = try file("Runtimes/\(D3DMetalRuntime.directoryName)/\(path)")
            hashes[path] = try RuntimeInstaller.checksum(of: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        let unix = directory.appendingPathComponent("Wine/lib/wine/x86_64-unix")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        for name in ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"] {
            try FileManager.default.createSymbolicLink(atPath: unix.appendingPathComponent(name + ".so").path,
                withDestinationPath: "../../external/libd3dshared.dylib")
        }
        let receipt = D3DMetalRuntime(sourceArchiveSHA256: D3DMetalRuntime.archiveSHA256, appleDMGSHA256: D3DMetalRuntime.dmgSHA256,
            appleVersion: "4.0b3", wineVersion: "wine-11.16", files: hashes)
        try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent("gggmac-d3dmetal.json"))
        try JSONEncoder().encode(setup).write(to: root.appendingPathComponent(PreparedD3DMetalGame.filename))
    }
    func file(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture file".utf8).write(to: url)
        return url
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func preparedD3DMetalConnectsExistingGameWithoutChangingDefaultOrOriginalEnvironment() throws {
    let f = try D3DMetalFixture(); defer { f.clean() }
    let original = f.library
    let setup = try PreparedD3DMetalGame.load(root: f.root)
    let connected = try setup.connecting(to: original, root: f.root)
    #expect(connected.runtime == original.runtime)
    #expect(connected.bottles.first == original.bottles.first)
    #expect(connected.bottles.count == 2)
    #expect(connected.games.count == 1)
    #expect(connected.games[0].id == original.games[0].id)
    #expect(connected.games[0].arguments == original.games[0].arguments)
    #expect(connected.games[0].bottleID == f.targetID)
    #expect(connected.games[0].executable.path.contains(f.targetID.uuidString))
    #expect(try setup.connecting(to: connected, root: f.root) == connected)
    let store = LibraryStore(root: f.root)
    try store.save(connected)
    #expect(try store.load() == connected)
    let command = try WineCommand.launch(runtime: try #require(connected.bottles.last?.runtime), game: connected.games[0],
        prefix: store.prefix(for: connected.bottles[1]))
    #expect(command.executable == f.runtime)
    #expect(command.environment["D3DM_SUPPORT_DXR"] == "0")
    #expect(command.environment["ROSETTA_ADVERTISE_AVX"] == "1")
    #expect(command.environment["WINEPREFIX"]?.contains(f.targetID.uuidString) == true)
    #expect(command.arguments == [connected.games[0].executable.path, "literal argument"])
}

@Test func preparedD3DMetalRejectsChangedPayloadAndEscapingBridgeLink() throws {
    let f = try D3DMetalFixture(); defer { f.clean() }
    let directory = D3DMetalRuntime.directory(root: f.root)
    let dll = directory.appendingPathComponent("Wine/lib/wine/x86_64-windows/d3d12.dll")
    try Data("outside edit".utf8).write(to: dll)
    #expect(throws: D3DMetalSetupError.self) { try f.setup.connecting(to: f.library, root: f.root) }
    try Data("fixture file".utf8).write(to: dll)
    let link = directory.appendingPathComponent("Wine/lib/wine/x86_64-unix/d3d12.so")
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/tmp/outside.dylib")
    #expect(throws: D3DMetalSetupError.self) { try D3DMetalRuntime.validate(executable: f.runtime) }
}

@Test func preparedD3DMetalRejectsWrongGameAndExecutableTraversal() throws {
    let f = try D3DMetalFixture(); defer { f.clean() }
    var changed = f.library
    changed.games[0].executable = try f.file("different.exe")
    #expect(throws: D3DMetalSetupError.self) { try f.setup.connecting(to: changed, root: f.root) }
    let escaping = PreparedD3DMetalGame(gameID: f.gameID, sourceBottleID: f.sourceID, bottleID: f.targetID,
        relativeExecutablePath: "drive_c/../../outside.exe")
    #expect(throws: D3DMetalSetupError.self) { try escaping.connecting(to: f.library, root: f.root) }
    #expect(f.library.games[0].bottleID == f.sourceID)
    #expect(f.library.bottles.count == 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_D3DMETAL_SETUP_ROOT"] != nil))
func realPreparedD3DMetalLaunchWiringAndPresentation() async throws {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GGGMAC_D3DMETAL_SETUP_ROOT"]))
    let store = LibraryStore(root: root)
    let original = try store.load()
    let setup = try PreparedD3DMetalGame.load(root: root)
    let connected = try setup.connecting(to: original, root: root)
    let bottle = try #require(connected.bottles.first { $0.id == setup.bottleID })
    let game = try #require(connected.games.first { $0.id == setup.gameID })
    let prefix = store.prefix(for: bottle)
    let command = try WineCommand.launch(runtime: bottle.runtime, game: game, prefix: prefix, d3dMetalOptions: bottle.d3dMetalOptions)
    #expect(command.executable == D3DMetalRuntime.executable(root: root))
    #expect(command.environment["WINEPREFIX"] == prefix.path)
    #expect(command.environment["D3DM_SUPPORT_DXR"] == ((bottle.d3dMetalOptions ?? D3DMetalOptions()).rayTracingEnabled ? "1" : "0"))
    #expect(command.arguments.first == game.executable.path)
    let logs = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac permanent D3DMetal \(UUID().uuidString)")
    let runner = ProcessRunner()
    let boot = try await runner.run(WineCommand(executable: bottle.runtime.executable, arguments: ["wineboot", "--update"], prefix: prefix,
        d3dMetalOptions: bottle.d3dMetalOptions),
        logURL: logs.appendingPathComponent("update.log"), timeout: .seconds(150))
    try #require(boot.exitCode == 0)
    let smoke = try await runner.run(WineCommand.smokeTest(bottle: bottle, prefix: prefix),
        logURL: logs.appendingPathComponent("command.log"), timeout: .seconds(60))
    try #require(smoke.exitCode == 0)
    #expect(LogReader.tail(smoke.logURL).contains(WineCommand.smokeMarker))
    for api in ["d3d12", "d3d12-dxil", "d3d12-present"] {
        let probe = Game(name: "Relocated D3DMetal probe", executable: try #require(GraphicsProbe.executable), bottleID: bottle.id, arguments: [api])
        let result = try await runner.run(WineCommand.launch(runtime: bottle.runtime, game: probe, prefix: prefix, d3dMetalOptions: bottle.d3dMetalOptions),
            logURL: logs.appendingPathComponent(api + ".log"), timeout: .seconds(60))
        try #require(result.exitCode == 0, "See \(result.logURL.path)")
        let report = try #require(GraphicsProbe.parse(LogReader.tail(result.logURL), api: api))
        #expect(report.hasVerifiedPass)
        #expect(report.version == "Feature level 12.2")
        #expect(report.resourceBindingTier == 3)
        print("Permanent D3DMetal:", api, report.detail, "Logs:", result.logURL.path)
    }
    #expect(try store.load() == original, "The diagnostic must not save library changes behind the running app.")
}

@Test func tuningOptionsReachGameAndCommandClientsWithoutInheritingHostOverrides() throws {
    let f = try D3DMetalFixture(); defer { f.clean() }
    var library = try f.setup.connecting(to: f.library, root: f.root)
    let options = D3DMetalOptions(rayTracingEnabled: true, msyncEnabled: true, backend: .metal3, showPerformanceHUD: true)
    library.bottles[1].d3dMetalOptions = options
    let bottle = library.bottles[1]
    let prefix = LibraryStore(root: f.root).prefix(for: bottle)
    let game = try WineCommand.launch(runtime: bottle.runtime, game: library.games[0], prefix: prefix, d3dMetalOptions: bottle.d3dMetalOptions)
    let smoke = try WineCommand.smokeTest(bottle: bottle, prefix: prefix)
    for key in ["WINEMSYNC", "D3DM_SUPPORT_DXR", "D3DM_MTL4", "MTL_HUD_ENABLED"] {
        #expect(game.environment[key] == smoke.environment[key])
    }
    #expect(game.environment["WINEMSYNC"] == "1")
    #expect(game.environment["D3DM_SUPPORT_DXR"] == "1")
    #expect(game.environment["D3DM_MTL4"] == "0")
    #expect(game.environment["MTL_HUD_ENABLED"] == "1")
    let clean = WineCommand(executable: f.runtime, arguments: ["--version"],
        inheritedEnvironment: ["WINEMSYNC": "1", "D3DM_MTL4": "1", "D3DM_SUPPORT_DXR": "1", "MTL_HUD_ENABLED": "1", "MTL_HUD_LOG_ENABLED": "1"])
    #expect(clean.environment["WINEMSYNC"] == "0")
    #expect(clean.environment["D3DM_SUPPORT_DXR"] == "0")
    #expect(clean.environment["MTL_HUD_ENABLED"] == "0")
    #expect(clean.environment["D3DM_MTL4"] == nil)
    #expect(clean.environment["MTL_HUD_LOG_ENABLED"] == nil)
}

@Test func tuningSettingsMigrateSchemaThreeWithBackupAndRoundTrip() throws {
    let f = try D3DMetalFixture(); defer { f.clean() }
    let store = LibraryStore(root: f.root)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.library)) as? [String: Any])
    json["schemaVersion"] = 3
    let originalData = try JSONSerialization.data(withJSONObject: json)
    try originalData.write(to: store.libraryURL)
    var updated = try store.load()
    #expect(updated.schemaVersion == 5)
    #expect(updated.bottles[0].d3dMetalOptions == nil)
    let options = D3DMetalOptions(rayTracingEnabled: true, msyncEnabled: true, backend: .metal4, showPerformanceHUD: true)
    updated.bottles[0].d3dMetalOptions = options
    try store.save(updated)
    #expect(try store.load().bottles[0].d3dMetalOptions == options)
    #expect(try Data(contentsOf: f.root.appendingPathComponent("library-v3.backup.json")) == originalData)
    #expect(try store.load().games == f.library.games)
}

/// Each mode gets a fresh prefix so this never stops the user's game server.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_D3DMETAL_TUNING_RUNTIME"] != nil))
func realD3DMetalTuningModes() async throws {
    let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GGGMAC_D3DMETAL_TUNING_RUNTIME"]))
    try D3DMetalRuntime.validate(executable: executable)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac tuning modes \(UUID().uuidString)")
    for (index, options) in [
        D3DMetalOptions(rayTracingEnabled: true, msyncEnabled: true, backend: .metal3, showPerformanceHUD: true),
        D3DMetalOptions(rayTracingEnabled: false, msyncEnabled: false, backend: .automatic)
    ].enumerated() {
        let prefix = root.appendingPathComponent("prefix-\(index)")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let runner = ProcessRunner()
        let runtime = WineRuntime(executable: executable, version: "tuning test")
        var bottle = Bottle(name: "Tuning", runtime: runtime); bottle.d3dMetalOptions = options
        func stop() async {
            _ = try? await ProcessRunner().run(WineCommand(executable: executable.deletingLastPathComponent().appendingPathComponent("wineserver"),
                arguments: ["-k"], prefix: prefix), logURL: root.appendingPathComponent("stop-\(index).log"), timeout: .seconds(20))
        }
        do {
            let boot = try await runner.run(WineCommand(executable: executable, arguments: ["wineboot", "--init"], prefix: prefix,
                d3dMetalOptions: options), logURL: root.appendingPathComponent("boot-\(index).log"), timeout: .seconds(180))
            try #require(boot.exitCode == 0, "Logs: \(root.path)")
            let smoke = try await runner.run(WineCommand.smokeTest(bottle: bottle, prefix: prefix),
                logURL: root.appendingPathComponent("smoke-\(index).log"), timeout: .seconds(90))
            try #require(smoke.exitCode == 0, "Logs: \(root.path)")
            #expect(LogReader.tail(smoke.logURL).contains(WineCommand.smokeMarker))
            let api = "d3d12-present"
            let probe = Game(name: "Tuning probe", executable: try #require(GraphicsProbe.executable), bottleID: bottle.id, arguments: [api])
            let result = try await runner.run(WineCommand.launch(runtime: runtime, game: probe, prefix: prefix, d3dMetalOptions: options),
                logURL: root.appendingPathComponent("graphics-\(index).log"), timeout: .seconds(90))
            try #require(result.exitCode == 0, "Logs: \(root.path)")
            let report = try #require(GraphicsProbe.parse(LogReader.tail(result.logURL), api: api))
            #expect(report.hasVerifiedPass)
            #expect(report.rayTracingTier == (options.rayTracingEnabled ? "1.1" : "Not supported"))
            print("Tuning configuration:", options.summary, "Reported DXR:", report.rayTracingTier ?? "unknown", "Log:", result.logURL.path)
            await stop()
        } catch { await stop(); throw error }
    }
}
