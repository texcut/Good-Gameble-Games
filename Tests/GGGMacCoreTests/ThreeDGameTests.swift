import Foundation
import Testing
@testable import GGGMacCore

private struct ThreeDFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac 3D fixture \(UUID().uuidString)")
    var prefix: URL { root.appendingPathComponent("prefix") }
    init() throws {
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try Data().write(to: prefix.appendingPathComponent("system.reg"))
    }
    func zip(_ files: [String: String], name: String) async throws -> URL {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        for (path, contents) in files {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
        let archive = root.appendingPathComponent(name + ".zip")
        let result = try await ProcessRunner().run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-r", archive.path] + (try FileManager.default.contentsOfDirectory(atPath: folder.path)), workingDirectory: folder),
            logURL: root.appendingPathComponent(name + ".log"))
        try #require(result.exitCode == 0)
        return archive
    }
    static let engine = ["fteqw64.exe": "MZ-client", "fteqw_readme.txt": "license", "version.txt": "6202"]
    static let data = ["lite/id1/pak0.pak": "game", "lite/id1/pak1.pak": "game2", "lite/id1/docs/misc-docs/COPYING": "GPL"]
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func threeDSetupReusesPackageAndPreservesSavesAndModifiedFiles() async throws {
    let f = try ThreeDFixture(); defer { f.clean() }
    let engine = try await f.zip(ThreeDFixture.engine, name: "engine")
    let data = try await f.zip(ThreeDFixture.data, name: "data")
    let eh = try RuntimeInstaller.checksum(of: engine), dh = try RuntimeInstaller.checksum(of: data)
    let installer = ThreeDTestGame()
    let exe = try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix, engineHash: eh, dataHash: dh)
    let save = exe.deletingLastPathComponent().appendingPathComponent("id1/save.sav")
    try Data("keep save".utf8).write(to: save)
    #expect(try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix, engineHash: eh, dataHash: dh) == exe)
    try Data("changed".utf8).write(to: exe)
    await #expect(throws: LauncherError.self) { try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix, engineHash: eh, dataHash: dh) }
    #expect(try String(contentsOf: exe, encoding: .utf8) == "changed")
    #expect(try String(contentsOf: save, encoding: .utf8) == "keep save")
}

@Test func threeDSetupRejectsHashMismatchUnexpectedPathsAndLinkedFolders() async throws {
    let f = try ThreeDFixture(); defer { f.clean() }
    let engine = try await f.zip(ThreeDFixture.engine, name: "engine")
    let data = try await f.zip(["outside.txt": "unexpected"], name: "data")
    let installer = ThreeDTestGame()
    await #expect(throws: LauncherError.self) { try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix) }
    #expect(!FileManager.default.fileExists(atPath: f.prefix.appendingPathComponent("drive_c/GGGMac Games").path))
    let eh = try RuntimeInstaller.checksum(of: engine), dh = try RuntimeInstaller.checksum(of: data)
    await #expect(throws: LauncherError.self) { try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix, engineHash: eh, dataHash: dh) }
    for path in ["/absolute", "lite/id1/../outside", "lite/id1/./bad", "lite/id1//bad", "C:/game", "lite/id1\\bad", "lite/id1/a\nb"] {
        #expect(!ThreeDTestGame.safeRelativePath(path))
    }
    try FileManager.default.removeItem(at: f.prefix.appendingPathComponent("drive_c"))
    try FileManager.default.createSymbolicLink(at: f.prefix.appendingPathComponent("drive_c"), withDestinationURL: f.root)
    await #expect(throws: LauncherError.self) { try await installer.unpack(engineArchive: engine, dataArchive: data, prefix: f.prefix, engineHash: eh, dataHash: dh) }
}

@Test func fteSessionPreservesOldLogAndRejectsLinkedLog() throws {
    let f = try ThreeDFixture(); defer { f.clean() }
    let exe = f.prefix.appendingPathComponent("drive_c/fteqw64.exe")
    let log = try FTEGameSession.prepare(executable: exe)
    try Data("old run".utf8).write(to: log)
    #expect(try FTEGameSession.prepare(executable: exe) == log)
    #expect(!FileManager.default.fileExists(atPath: log.path))
    let old = try #require(FileManager.default.contentsOfDirectory(at: log.deletingLastPathComponent(), includingPropertiesForKeys: nil).first)
    #expect(try String(contentsOf: old, encoding: .utf8) == "old run")
    try FileManager.default.createSymbolicLink(at: log, withDestinationURL: old)
    #expect(throws: LauncherError.self) { try FTEGameSession.prepare(executable: exe) }
}

@Test func threeDBenchmarkRequiresCompleteDemoAndCurrentRendererEvidence() throws {
    #expect(GameRendererReport.parseFTE("vid_renderer d3d11\nD3D11 Feature level: 11_0") == nil)
    let output = "Setting windowed mode 1280*720 Direct3D11\nD3D11: Direct3D11 (current)\n4526 frames  37.8 seconds 119.6 fps\n"
    #expect(GameRendererReport.parseFTE(output)?.usesDirect3D11 == true)
    #expect(GameRendererReport.parseFTE(output + "gl: OpenGL (current)\n")?.usesDirect3D11 == false)
    let benchmark = try #require(GameBenchmark.parse(output, runtimeVersion: "wine-fixture"))
    #expect(benchmark.framesPerSecond == 119.6 && benchmark.width == 1280)
    #expect(GameBenchmark.parse(output.replacingOccurrences(of: "4526 frames", with: "200 frames"), runtimeVersion: "fixture") == nil)
    #expect(GameBenchmark.parse(output.replacingOccurrences(of: "1280*720", with: "640*480"), runtimeVersion: "fixture") == nil)
    #expect(GameBenchmark.parse(output + "Setting windowed mode 640*480 Direct3D11\n", runtimeVersion: "fixture") == nil)
    #expect(GameBenchmark.parse(output + "Setting fullscreen windowed Direct3D11\n", runtimeVersion: "fixture") == nil)
    #expect(GameBenchmark.parse(output + "gl: OpenGL (current)\n", runtimeVersion: "fixture") == nil)
    #expect(GameRendererReport.parseFTE(output + "headless: Headless (Null) (current)\n")?.usesDirect3D11 == false)
    #expect(GameLaunchProfile.fteDirect3D11.expectsExitCode(1))
    #expect(!GameLaunchProfile.sdlDirect3D11.expectsExitCode(1))
    #expect(!GameLaunchProfile.fteDirect3D11.expectsExitCode(1, output: "wine: Unhandled page fault"))
    var game = Game(name: "LibreQuake", executable: URL(fileURLWithPath: "/game/fteqw64.exe"), bottleID: UUID())
    game.launchProfile = .fteDirect3D11; game.lastBenchmark = benchmark
    #expect(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)) == game)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_3D_RUNTIME"] != nil))
func realLibreQuakeDirect3D11Benchmark() async throws {
    let env = ProcessInfo.processInfo.environment
    let binary = URL(fileURLWithPath: try #require(env["GGGMAC_3D_RUNTIME"]))
    let engine = URL(fileURLWithPath: try #require(env["GGGMAC_3D_ENGINE"]))
    let data = URL(fileURLWithPath: try #require(env["GGGMAC_3D_DATA"]))
    let runtime = WineRuntime(executable: binary, version: "wine-11.0")
    let payload = try #require(GraphicsBackendManager.payload(for: runtime))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac real 3D \(UUID().uuidString)")
    let prefix = root.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("benchmark.log")
    func stop() async {
        _ = try? await ProcessRunner().run(WineCommand(executable: binary.deletingLastPathComponent().appendingPathComponent("wineserver"),
            arguments: ["-k"], prefix: prefix), logURL: root.appendingPathComponent("stop.log"), timeout: .seconds(15))
    }
    do {
        let initialized = try await ProcessRunner().run(WineCommand(executable: binary, arguments: ["wineboot", "--init"], prefix: prefix),
            logURL: root.appendingPathComponent("init.log"), timeout: .seconds(180))
        try #require(initialized.exitCode == 0)
        try await GraphicsBackendManager(prefix: prefix).enableDXMT(payload: payload)
        let exe = try await ThreeDTestGame().unpack(engineArchive: engine, dataArchive: data, prefix: prefix)
        var game = Game(name: "LibreQuake integration", executable: exe, bottleID: UUID(),
            arguments: GameLaunchProfile.libreQuakeArguments + GameLaunchProfile.libreQuakeBenchmarkArguments)
        game.launchProfile = .fteDirect3D11
        let engineLog = try FTEGameSession.prepare(executable: exe)
        let command = try WineCommand.launch(runtime: runtime, game: game, prefix: prefix, graphics: .dxmt)
        let shutdown = Task {
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            await stop()
        }
        defer { shutdown.cancel() }
        let result = try await ProcessRunner().run(command, logURL: log, timeout: .seconds(140))
        let text = LogReader.tail(engineLog)
        let renderer = GameRendererReport.parseFTE(text)
        let benchmark = GameBenchmark.parse(text, runtimeVersion: runtime.version)
        #expect(GameLaunchProfile.fteDirect3D11.expectsExitCode(result.exitCode, output: text + LogReader.tail(log)))
        #expect(renderer?.usesDirect3D11 == true, "Renderer not confirmed. Logs: \(log.path)\n\(text.suffix(6000))")
        #expect(benchmark != nil, "No completed benchmark. Logs: \(log.path)")
        print("3D renderer:", renderer?.renderer ?? "unknown", "Benchmark FPS:", benchmark?.framesPerSecond ?? 0, "Exit:", result.exitCode, "Logs:", log.path)
        await stop()
        // Keep evidence for inspection; all files live in this temporary test environment.
    } catch {
        await stop()
        print("3D integration files preserved:", root.path)
        throw error
    }
}
