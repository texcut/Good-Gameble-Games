import Foundation
import Testing
@testable import GGGMacCore

@Test func dxilAndPresentationRequireExecutionEvidenceBeyondAdvertisedCapabilities() throws {
    let basic = GraphicsAPIResult(api: "d3d12", passed: true, detail: "SM5 draw", shaderModel: "6.0")
    let dxil = GraphicsAPIResult(api: "d3d12-dxil", passed: true, detail: "DXIL draw", shaderTarget: "SM 6.0 / DXIL")
    #expect(!GraphicsAPIResult(api: "d3d12-dxil", passed: true, detail: "Only advertised", shaderModel: "6.0").hasVerifiedPass)
    for frames in [0, 1, 59] {
        #expect(!GraphicsAPIResult(api: "d3d12-present", passed: true, detail: "Partial", shaderTarget: "SM 6.0 / DXIL", completedPresents: frames).hasVerifiedPass)
    }
    let present = GraphicsAPIResult(api: "d3d12-present", passed: true, detail: "60 verified frames", shaderTarget: "SM 6.0 / DXIL", completedPresents: 60)
    #expect(present.hasVerifiedPass)
    #expect(!GraphicsAPIResult(api: "d3d12-present", passed: false, detail: "Final fence failed", shaderTarget: "SM 6.0 / DXIL", completedPresents: 60).hasVerifiedPass)
    var report = GraphicsReport(checkedAt: Date(), backend: .runtimeDefault, runtimeVersion: "fixture", openGL: basic, direct3D: basic, direct3D12: basic)
    #expect(!report.direct3D12BaselinePassed)
    report = GraphicsReport(checkedAt: report.checkedAt, backend: report.backend, runtimeVersion: report.runtimeVersion,
        openGL: report.openGL, direct3D: report.direct3D, direct3D12: basic, direct3D12DXIL: dxil, direct3D12Presentation: present)
    #expect(report.direct3D12BaselinePassed)
    #expect(try JSONDecoder().decode(GraphicsReport.self, from: JSONEncoder().encode(report)) == report)
    let invalid = #"GGGMAC_GRAPHICS_JSON:{"api":"d3d12-present","passed":true,"renderer":"GPU","version":"12","detail":"No frames"}"#
    #expect(GraphicsProbe.parse(invalid, api: "d3d12-present") == nil)
    let valid = "GGGMAC_GRAPHICS_JSON:" + String(decoding: try JSONEncoder().encode(present), as: UTF8.self)
    #expect(GraphicsProbe.parse(valid, api: "d3d12-present") == present)
    #expect(GraphicsProbe.parse(valid, api: "d3d12-dxil") == nil)
}

@Test func direct3D12ReportPreservesOldGraphicsReportsAndRejectsWrongAPI() throws {
    let old = GraphicsReport(checkedAt: Date(), backend: .runtimeDefault, runtimeVersion: "fixture",
        openGL: GraphicsAPIResult(api: "opengl", passed: false, detail: "unsupported"),
        direct3D: GraphicsAPIResult(api: "d3d11", passed: true, detail: "readback"))
    #expect(try JSONDecoder().decode(GraphicsReport.self, from: JSONEncoder().encode(old)).direct3D12 == nil)
    let output = "driver output\nGGGMAC_GRAPHICS_JSON:{\"api\":\"d3d12\",\"passed\":false,\"renderer\":\"Apple GPU\",\"version\":\"\",\"detail\":\"Device creation failed\"}\n"
    #expect(GraphicsProbe.parse(output, api: "d3d12")?.passed == false)
    #expect(GraphicsProbe.parse(output, api: "d3d11") == nil)
    let result = try #require(GraphicsProbe.parse(output, api: "d3d12"))
    let new = GraphicsReport(checkedAt: old.checkedAt, backend: old.backend, runtimeVersion: old.runtimeVersion,
        openGL: old.openGL, direct3D: old.direct3D, direct3D12: result)
    #expect(try JSONDecoder().decode(GraphicsReport.self, from: JSONEncoder().encode(new)) == new)
    let detailed = GraphicsAPIResult(api: "d3d12", passed: true, detail: "SM 5.0 draw verified",
        implementation: "Wine builtin D3D12", shaderModel: "6.0", resourceBindingTier: 1, rayTracingTier: "Not supported")
    #expect(try JSONDecoder().decode(GraphicsAPIResult.self, from: JSONEncoder().encode(detailed)) == detailed)
}

/// A capability audit can legitimately report unavailable. Set EXPECT to require a GPU pass.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_D3D12_RUNTIME"] != nil))
func realDirect3D12CapabilityCheck() async throws {
    let env = ProcessInfo.processInfo.environment
    let binary = URL(fileURLWithPath: try #require(env["GGGMAC_D3D12_RUNTIME"]))
    let runtime = WineRuntime(executable: binary, version: "D3D12 capability audit")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac D3D12 \(UUID().uuidString)")
    let prefix = root.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    func stop() async {
        _ = try? await ProcessRunner().run(WineCommand(executable: binary.deletingLastPathComponent().appendingPathComponent("wineserver"),
            arguments: ["-k"], prefix: prefix), logURL: root.appendingPathComponent("stop.log"), timeout: .seconds(15))
    }
    do {
        let initialized = try await ProcessRunner().run(WineCommand(executable: binary, arguments: ["wineboot", "--init"], prefix: prefix),
            logURL: root.appendingPathComponent("init.log"), timeout: .seconds(180))
        try #require(initialized.exitCode == 0)
        let modes = ["d3d12", "d3d12-dxil"] + (env["GGGMAC_D3D12_PRESENTATION"] == "1" ? ["d3d12-present"] : [])
        for api in modes {
        let log = root.appendingPathComponent(api + ".log")
        let game = Game(name: "D3D12 probe", executable: try #require(GraphicsProbe.executable), bottleID: UUID(), arguments: [api])
        let command = try WineCommand.launch(runtime: runtime, game: game, prefix: prefix)
        let result = try await ProcessRunner().run(command, logURL: log, timeout: .seconds(45))
        try #require(result.exitCode == 0, "Logs: \(log.path)")
        let report = try #require(GraphicsProbe.parse(LogReader.tail(log), api: api), "Log: \(LogReader.tail(log))")
        print("Measured D3D12 result:", String(decoding: try JSONEncoder().encode(report), as: UTF8.self), "Logs:", log.path)
        if (api == "d3d12" && env["GGGMAC_EXPECT_D3D12"] == "1") ||
            (api == "d3d12-dxil" && env["GGGMAC_EXPECT_DXIL"] == "1") ||
            (api == "d3d12-present" && env["GGGMAC_EXPECT_PRESENTATION"] == "1") { #expect(report.passed) }
        if api == "d3d12-present", report.passed { #expect(report.completedPresents == 60) }
        }
        await stop()
    } catch {
        await stop()
        print("D3D12 files preserved:", root.path)
        throw error
    }
}
