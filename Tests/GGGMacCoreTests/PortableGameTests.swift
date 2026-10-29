import Foundation
import Testing
@testable import GGGMacCore

private struct PortableFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac portable \(UUID().uuidString)")
    var prefix: URL { root.appendingPathComponent("prefix") }
    init() throws {
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try Data().write(to: prefix.appendingPathComponent("system.reg"))
    }
    func archive(extra: String? = nil) async throws -> URL {
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in PortableTestGame.files { try Data(name.utf8).write(to: source.appendingPathComponent(name)) }
        if let extra { try Data("unexpected".utf8).write(to: source.appendingPathComponent(extra)) }
        let zip = root.appendingPathComponent("game.zip")
        let result = try await ProcessRunner().run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-j", zip.path] + (try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)).map(\.path)),
            logURL: root.appendingPathComponent("zip.log"))
        try #require(result.exitCode == 0)
        return zip
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func portableInstallReusesVerifiedFilesAndPreservesChangedFiles() async throws {
    let f = try PortableFixture(); defer { f.clean() }
    let archive = try await f.archive()
    let hash = try RuntimeInstaller.checksum(of: archive)
    let installer = PortableTestGame()
    let executable = try await installer.unpack(archive: archive, prefix: f.prefix, expectedHash: hash)
    #expect(try String(contentsOf: executable, encoding: .utf8) == "sopwith.exe")
    #expect(try await installer.unpack(archive: archive, prefix: f.prefix, expectedHash: hash) == executable)
    let save = executable.deletingLastPathComponent().appendingPathComponent("save.dat")
    try Data("keep my save".utf8).write(to: save)
    try Data("user modified".utf8).write(to: executable)
    await #expect(throws: LauncherError.self) { try await installer.unpack(archive: archive, prefix: f.prefix, expectedHash: hash) }
    #expect(try String(contentsOf: executable, encoding: .utf8) == "user modified")
    #expect(try String(contentsOf: save, encoding: .utf8) == "keep my save")
}

@Test func portableInstallRejectsBadHashUnexpectedPathsAndLinkedDrive() async throws {
    let f = try PortableFixture(); defer { f.clean() }
    let archive = try await f.archive(extra: "unexpected.exe")
    let installer = PortableTestGame()
    await #expect(throws: LauncherError.self) { try await installer.unpack(archive: archive, prefix: f.prefix) }
    let hash = try RuntimeInstaller.checksum(of: archive)
    await #expect(throws: LauncherError.self) { try await installer.unpack(archive: archive, prefix: f.prefix, expectedHash: hash) }
    #expect(!FileManager.default.fileExists(atPath: f.prefix.appendingPathComponent("drive_c/GGGMac Games/sdl-sopwith-2.9.0").path))
    try FileManager.default.removeItem(at: f.prefix.appendingPathComponent("drive_c"))
    try FileManager.default.createSymbolicLink(at: f.prefix.appendingPathComponent("drive_c"), withDestinationURL: f.root)
    await #expect(throws: LauncherError.self) { try await installer.unpack(archive: archive, prefix: f.prefix, expectedHash: hash) }
}

@Test func rendererEvidenceDoesNotMistakeRequestedDriverForCreatedRenderer() throws {
    #expect(GameRendererReport.parse("SDL_RENDER_DRIVER=direct3d11\nLoaded d3d11.dll") == nil)
    #expect(GameRendererReport.parse("Created renderer: direct3d11fake") == nil)
    let log = #"002c:trace:debugstr:OutputDebugStringA \"INFO: Created renderer: direct3d11\n\""#
    #expect(GameRendererReport.parse(log)?.usesDirect3D11 == true)
    #expect(GameRendererReport.parse(log + "\nINFO: Created renderer: software\n")?.renderer == "software")
    let command = WineCommand(executable: URL(fileURLWithPath: "/test/wine"), arguments: [], profile: .sdlDirect3D11)
    #expect(command.environment["SDL_RENDER_DRIVER"] == "direct3d11")
    #expect(command.environment["SDL_LOGGING"] == "render=info")
    #expect(command.environment["WINEDEBUG"]?.contains("trace+debugstr") == true)
    let standard = WineCommand(executable: command.executable, arguments: [], inheritedEnvironment: command.environment)
    #expect(standard.environment["SDL_RENDER_DRIVER"] == nil)
    #expect(standard.environment["SDL_LOGGING"] == nil)
}

@Test func gameProfilesAreOptionalForExistingLibrariesAndPersistReports() throws {
    var game = Game(name: "Existing", executable: URL(fileURLWithPath: "/test/game.exe"), bottleID: UUID())
    let legacy = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
    #expect(legacy.launchProfile == nil && legacy.lastRendererReport == nil)
    game.launchProfile = .sdlDirect3D11
    game.lastRendererReport = GameRendererReport.parse("INFO: Created renderer: direct3d11\n")
    #expect(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)) == game)
}

@Test func sopwithVersionQueryRejectsConflictingOrAmbiguousValues() {
    #expect(SopwithCompatibility.hasWindows7Value("HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\sopwith.exe\r\n    Version    REG_SZ    win7\r\n"))
    #expect(!SopwithCompatibility.hasWindows7Value("    Version    REG_SZ    win10\r\n"))
    #expect(!SopwithCompatibility.hasWindows7Value("    Version    REG_SZ    win7extra\r\n"))
    #expect(!SopwithCompatibility.hasWindows7Value("Wine reported win7 in an unrelated message"))
}

@Test func direct3DGameProfileRequiresDXMTBeforeLaunch() throws {
    let f = try PortableFixture(); defer { f.clean() }
    let wine = f.root.appendingPathComponent("wine")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wine)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    let exe = f.prefix.appendingPathComponent("drive_c/sopwith.exe")
    try Data("MZ".utf8).write(to: exe)
    var game = Game(name: "Sopwith", executable: exe, bottleID: UUID())
    game.launchProfile = .sdlDirect3D11
    let runtime = WineRuntime(executable: wine, version: "fixture")
    #expect(throws: LauncherError.self) { try WineCommand.launch(runtime: runtime, game: game, prefix: f.prefix) }
    let command = try WineCommand.launch(runtime: runtime, game: game, prefix: f.prefix, graphics: .dxmt)
    #expect(command.environment["SDL_RENDER_DRIVER"] == "direct3d11")
    #expect(command.environment["WINEDLLOVERRIDES"]?.contains("d3d11") == true)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_SOPWITH_RUNTIME"] != nil))
func realSopwithCreatesDirect3D11Renderer() async throws {
    let env = ProcessInfo.processInfo.environment
    let binary = URL(fileURLWithPath: try #require(env["GGGMAC_SOPWITH_RUNTIME"]))
    let archive = URL(fileURLWithPath: try #require(env["GGGMAC_SOPWITH_ARCHIVE"]))
    let runtime = WineRuntime(executable: binary, version: "wine-11.0")
    let payload = try #require(GraphicsBackendManager.payload(for: runtime))
    let f = try PortableFixture()
    // Unit fixtures use a placeholder registry. Real Wine initializes its own.
    try FileManager.default.removeItem(at: f.prefix.appendingPathComponent("system.reg"))
    let log = f.root.appendingPathComponent("game.log")
    func stop() async {
        _ = try? await ProcessRunner().run(WineCommand(executable: binary.deletingLastPathComponent().appendingPathComponent("wineserver"),
            arguments: ["-k"], prefix: f.prefix), logURL: f.root.appendingPathComponent("stop.log"), timeout: .seconds(15))
    }
    do {
        let initResult = try await ProcessRunner().run(WineCommand(executable: binary, arguments: ["wineboot", "--init"], prefix: f.prefix),
            logURL: f.root.appendingPathComponent("init.log"), timeout: .seconds(180))
        try #require(initResult.exitCode == 0)
        try await GraphicsBackendManager(prefix: f.prefix).enableDXMT(payload: payload)
        let exe = try await PortableTestGame().unpack(archive: archive, prefix: f.prefix)
        try await SopwithCompatibility.prepare(runtime: runtime, prefix: f.prefix, logDirectory: f.root)
        try await SopwithCompatibility.prepare(runtime: runtime, prefix: f.prefix, logDirectory: f.root)
        var game = Game(name: "Sopwith integration", executable: exe, bottleID: UUID())
        game.launchProfile = .sdlDirect3D11
        let command = try WineCommand.launch(runtime: runtime, game: game, prefix: f.prefix, graphics: .dxmt)
        // Only this temporary prefix is stopped after observing startup. Gameplay stays a manual test.
        let shutdown = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            await stop()
        }
        defer { shutdown.cancel() }
        _ = try await ProcessRunner().run(command, logURL: log, timeout: .seconds(30))
        let text = LogReader.tail(log)
        let report = GameRendererReport.parse(text)
        #expect(report?.usesDirect3D11 == true, "Renderer log: \(text)")
        print("Sopwith renderer:", report?.renderer ?? "unconfirmed", "Logs:", f.root.path)
        await stop()
        if report?.usesDirect3D11 == true { f.clean() }
    } catch {
        await stop()
        print("Sopwith integration files preserved:", f.root.path)
        throw error
    }
}
