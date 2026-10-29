import Foundation
import Testing
@testable import GGGMacCore

private struct GraphicsFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac graphics \(UUID().uuidString)")
    var prefix: URL { root.appendingPathComponent("prefix") }
    var payload: URL { root.appendingPathComponent("payload") }
    let names = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]
    init() throws {
        for (arch, dir) in [("x64", "system32"), ("x32", "syswow64")] {
            let directory = prefix.appendingPathComponent("drive_c/windows/\(dir)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: payload.appendingPathComponent(arch), withIntermediateDirectories: true)
            for name in names {
                var data = Data(repeating: 0, count: 128)
                data.replaceSubrange(0..<2, with: Data("MZ".utf8))
                data.append(Data("\(arch)-\(name)".utf8))
                try data.write(to: payload.appendingPathComponent("\(arch)/\(name)"))
            }
            try Data("original-\(dir)".utf8).write(to: directory.appendingPathComponent("d3d11.dll"))
        }
        try Data().write(to: prefix.appendingPathComponent("system.reg"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func graphicsDeploymentAndRestorePreserveOriginalsAndRemoveAddedFiles() async throws {
    let fixture = try GraphicsFixture(); defer { fixture.clean() }
    let manager = GraphicsBackendManager(prefix: fixture.prefix)
    #expect(try await manager.enableDXMT(payload: fixture.payload))
    try await manager.verifySelection(.dxmt)
    #expect(try await manager.enableDXMT(payload: fixture.payload) == false)
    for (arch, dir) in [("x64", "system32"), ("x32", "syswow64")] {
        for name in fixture.names {
            #expect(try Data(contentsOf: fixture.prefix.appendingPathComponent("drive_c/windows/\(dir)/\(name)")) == Data(contentsOf: fixture.payload.appendingPathComponent("\(arch)/\(name)")))
        }
    }
    try await manager.restore()
    try await manager.verifySelection(.runtimeDefault)
    for dir in ["system32", "syswow64"] {
        let directory = fixture.prefix.appendingPathComponent("drive_c/windows/\(dir)")
        #expect(try Data(contentsOf: directory.appendingPathComponent("d3d11.dll")) == Data("original-\(dir)".utf8))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("dxgi.dll").path))
    }
    try await manager.restore() // Idempotent default selection.
}

@Test func graphicsRestoreRefusesOutsideEditsBeforeReplacingAnyFiles() async throws {
    let fixture = try GraphicsFixture(); defer { fixture.clean() }
    let manager = GraphicsBackendManager(prefix: fixture.prefix)
    try await manager.enableDXMT(payload: fixture.payload)
    let changed = fixture.prefix.appendingPathComponent("drive_c/windows/system32/dxgi.dll")
    try Data("external edit".utf8).write(to: changed)
    await #expect(throws: GraphicsError.self) { try await manager.restore() }
    #expect(try Data(contentsOf: changed) == Data("external edit".utf8))
    #expect(try Data(contentsOf: fixture.prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll")) == Data(contentsOf: fixture.payload.appendingPathComponent("x64/d3d11.dll")))
    await #expect(throws: GraphicsError.self) { try await manager.verifySelection(.dxmt) }
    #expect(FileManager.default.fileExists(atPath: fixture.prefix.appendingPathComponent(".gggmac-graphics/receipt.json").path))
}

@Test func graphicsRestoreRejectsCorruptBackupAndKeepsReceipt() async throws {
    let fixture = try GraphicsFixture(); defer { fixture.clean() }
    let manager = GraphicsBackendManager(prefix: fixture.prefix)
    try await manager.enableDXMT(payload: fixture.payload)
    try Data("damaged backup".utf8).write(to: fixture.prefix.appendingPathComponent(".gggmac-graphics/originals/drive_c/windows/system32/d3d11.dll"))
    await #expect(throws: GraphicsError.self) { try await manager.restore() }
    try await manager.verifyInstalled()
}

@Test func graphicsDeploymentRejectsBuiltinPayloadAndLinkedTargets() async throws {
    let fixture = try GraphicsFixture(); defer { fixture.clean() }
    let source = fixture.payload.appendingPathComponent("x64/d3d11.dll")
    let original = try Data(contentsOf: source)
    var builtin = original
    builtin.replaceSubrange(64..<80, with: Data("Wine builtin DLL".utf8))
    try builtin.write(to: source)
    let manager = GraphicsBackendManager(prefix: fixture.prefix)
    await #expect(throws: GraphicsError.self) { try await manager.enableDXMT(payload: fixture.payload) }
    #expect(!FileManager.default.fileExists(atPath: fixture.prefix.appendingPathComponent(".gggmac-graphics").path))
    try original.write(to: source)
    let target = fixture.prefix.appendingPathComponent("drive_c/windows/system32/dxgi.dll")
    let outside = fixture.root.appendingPathComponent("keep.dll")
    try Data("preserve".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
    await #expect(throws: GraphicsError.self) { try await manager.enableDXMT(payload: fixture.payload) }
    #expect(try Data(contentsOf: outside) == Data("preserve".utf8))
}

@Test func graphicsSettingsDecodeOldLibraryAndPersistNewReport() throws {
    let fixture = try GraphicsFixture(); defer { fixture.clean() }
    var bottle = Bottle(name: "Graphics", runtime: WineRuntime(executable: fixture.root.appendingPathComponent("wine"), version: "fixture"))
    var library = Library(); library.bottles = [bottle]
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    json["schemaVersion"] = 2
    var bottles = try #require(json["bottles"] as? [[String: Any]])
    bottles[0].removeValue(forKey: "graphicsBackend"); bottles[0].removeValue(forKey: "lastGraphicsCheck")
    json["bottles"] = bottles
    let legacy = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.schemaVersion == 5)
    #expect(legacy.bottles[0].activeGraphicsBackend == .runtimeDefault)
    let store = LibraryStore(root: fixture.root.appendingPathComponent("library"))
    try store.prepare()
    let oldData = try JSONSerialization.data(withJSONObject: json)
    try oldData.write(to: store.libraryURL)
    try store.save(legacy)
    #expect(try Data(contentsOf: store.root.appendingPathComponent("library-v2.backup.json")) == oldData)
    bottle.graphicsBackend = .dxmt
    bottle.lastGraphicsCheck = GraphicsReport(checkedAt: Date(), backend: .dxmt, runtimeVersion: "fixture",
        openGL: GraphicsAPIResult(api: "opengl", passed: false, detail: "Not supported"),
        direct3D: GraphicsAPIResult(api: "d3d11", passed: true, renderer: "Test GPU", version: "11.0", detail: "Readback passed"))
    library.bottles = [bottle]
    #expect(try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library)) == library)
}

@Test func graphicsOverridesAreExplicitAndProbeParsingRejectsWrongAPI() throws {
    let wine = URL(fileURLWithPath: "/test/bin/wine")
    let defaultCommand = WineCommand(executable: wine, arguments: [], inheritedEnvironment: ["WINEDLLOVERRIDES": "wrong=n"])
    #expect(defaultCommand.environment["WINEDLLOVERRIDES"] == nil)
    #expect(defaultCommand.environment["MVK_CONFIG_LOG_LEVEL"] == "2")
    let dxmt = WineCommand(executable: wine, arguments: [], graphics: .dxmt)
    #expect(dxmt.environment["WINEDLLOVERRIDES"] == "d3d11,dxgi,d3d10core=n,b;winemetal=b")
    let output = "driver log\nGGGMAC_GRAPHICS_JSON:{\"api\":\"d3d11\",\"passed\":true,\"renderer\":\"Apple M3 Max\",\"version\":\"11.0\",\"detail\":\"Clear/readback passed\"}\r\n"
    #expect(GraphicsProbe.parse(output, api: "d3d11")?.passed == true)
    #expect(GraphicsProbe.parse(output, api: "opengl") == nil)
    #expect(GraphicsProbe.parse("GGGMAC_GRAPHICS_JSON:broken", api: "d3d11") == nil)
    let binary = try #require(GraphicsProbe.executable)
    #expect(try Data(contentsOf: binary).prefix(2) == Data("MZ".utf8))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_GRAPHICS_RUNTIME"] != nil))
func realDXMTMetalReadbackAndRestore() async throws {
    let binary = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GGGMAC_GRAPHICS_RUNTIME"]))
    let runtime = WineRuntime(executable: binary, version: "wine-11.0")
    let payload = try #require(GraphicsBackendManager.payload(for: runtime))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac real GPU \(UUID().uuidString)")
    let store = LibraryStore(root: root)
    var bottle = Bottle(name: "GPU integration", runtime: runtime)
    let prefix = store.prefix(for: bottle)
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let runner = ProcessRunner()
    func stop() async {
        _ = try? await ProcessRunner().run(WineCommand(executable: binary,
            arguments: ["wineboot", "--end-session", "--force", "--kill"], prefix: prefix),
            logURL: store.logsDirectory.appendingPathComponent("stop.log"), timeout: .seconds(15))
    }
    do {
        let initialized = try await runner.run(WineCommand(executable: binary, arguments: ["wineboot", "--init"], prefix: prefix),
            logURL: store.logsDirectory.appendingPathComponent("init.log"), timeout: .seconds(180))
        try #require(initialized.exitCode == 0)
        let manager = GraphicsBackendManager(prefix: prefix)
        try await manager.enableDXMT(payload: payload)
        bottle.graphicsBackend = .dxmt
        let report = try await GraphicsProbe.run(bottle: bottle, prefix: prefix, logDirectory: store.logsDirectory)
        print("Real graphics report:", String(decoding: try JSONEncoder().encode(report), as: UTF8.self))
        #expect(report.direct3D.passed, "\(report.direct3D.detail) Logs: \(store.logsDirectory.path)")
        try await manager.verifyInstalled()
        try await manager.restore()
        try await manager.verifySelection(.runtimeDefault)
        await stop()
        if report.direct3D.passed { try FileManager.default.removeItem(at: root) }
    } catch {
        await stop()
        print("GPU test files preserved:", root.path)
        throw error
    }
}
