import Foundation

public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case runtimeDefault, dxmt
    public var title: String { self == .dxmt ? "DXMT · Direct3D 10/11 → Metal" : "Runtime default" }
}

public struct GraphicsAPIResult: Codable, Equatable, Sendable {
    public let api: String
    public let passed: Bool
    public let renderer: String
    public let version: String
    public let detail: String
    public let implementation: String?
    public let shaderModel: String?
    public let resourceBindingTier: Int?
    public let rayTracingTier: String?
    public let shaderTarget: String?
    public let completedPresents: Int?
    public var hasVerifiedPass: Bool {
        guard passed else { return false }
        if api == "d3d12-dxil" { return shaderTarget == "SM 6.0 / DXIL" }
        if api == "d3d12-present" { return shaderTarget == "SM 6.0 / DXIL" && completedPresents == 60 }
        return true
    }
    public init(api: String, passed: Bool, renderer: String = "", version: String = "", detail: String,
                implementation: String? = nil, shaderModel: String? = nil, resourceBindingTier: Int? = nil, rayTracingTier: String? = nil,
                shaderTarget: String? = nil, completedPresents: Int? = nil) {
        self.api = api; self.passed = passed; self.renderer = renderer; self.version = version; self.detail = detail
        self.implementation = implementation; self.shaderModel = shaderModel
        self.resourceBindingTier = resourceBindingTier; self.rayTracingTier = rayTracingTier
        self.shaderTarget = shaderTarget; self.completedPresents = completedPresents
    }
}

public struct GraphicsReport: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let backend: GraphicsBackend
    public let runtimeVersion: String
    public let openGL: GraphicsAPIResult
    public let direct3D: GraphicsAPIResult
    public let direct3D12: GraphicsAPIResult?
    public let direct3D12DXIL: GraphicsAPIResult?
    public let direct3D12Presentation: GraphicsAPIResult?
    public var direct3D12BaselinePassed: Bool {
        direct3D12?.api == "d3d12" && direct3D12?.hasVerifiedPass == true &&
        direct3D12DXIL?.api == "d3d12-dxil" && direct3D12DXIL?.hasVerifiedPass == true &&
        direct3D12Presentation?.api == "d3d12-present" && direct3D12Presentation?.hasVerifiedPass == true
    }
    public init(checkedAt: Date, backend: GraphicsBackend, runtimeVersion: String,
                openGL: GraphicsAPIResult, direct3D: GraphicsAPIResult, direct3D12: GraphicsAPIResult? = nil,
                direct3D12DXIL: GraphicsAPIResult? = nil, direct3D12Presentation: GraphicsAPIResult? = nil) {
        self.checkedAt = checkedAt; self.backend = backend; self.runtimeVersion = runtimeVersion
        self.openGL = openGL; self.direct3D = direct3D; self.direct3D12 = direct3D12
        self.direct3D12DXIL = direct3D12DXIL; self.direct3D12Presentation = direct3D12Presentation
    }
}

public enum GraphicsError: LocalizedError {
    case missingProbe, unavailable, conflict(String), corruptBackup, restoreFirst
    public var errorDescription: String? {
        switch self {
        case .missingProbe: "The Windows graphics diagnostic is missing. Rebuild or reinstall GGGMac."
        case .unavailable: "This runtime does not provide a verified native DXMT payload and matching Wine Metal bridge. Use GGGMac’s managed runtime."
        case let .conflict(path): "Graphics files changed outside GGGMac, or a target folder is linked elsewhere. No files were replaced. Check: \(path)"
        case .corruptBackup: "The graphics backup is incomplete or damaged. It has been preserved; restore the environment from your backup."
        case .restoreFirst: "Select Runtime default in this environment’s Graphics settings before changing its Wine runtime. This restores the original graphics files."
        }
    }
}

public enum GraphicsProbe {
    public static var executable: URL? {
        Bundle.main.url(forResource: "GGGMacGraphicsProbe", withExtension: "exe") ??
            Bundle.module.url(forResource: "GGGMacGraphicsProbe", withExtension: "exe")
    }

    public static func parse(_ output: String, api: String) -> GraphicsAPIResult? {
        let marker = "GGGMAC_GRAPHICS_JSON:"
        // Wine and driver output may precede the diagnostic's own JSON line.
        for line in output.components(separatedBy: .newlines).reversed() {
            guard let range = line.range(of: marker),
                  let data = line[range.upperBound...].data(using: .utf8),
                  let result = try? JSONDecoder().decode(GraphicsAPIResult.self, from: data), result.api == api else { continue }
            if result.passed && !result.hasVerifiedPass { continue }
            return result
        }
        return nil
    }

    public static func run(bottle: Bottle, prefix: URL, logDirectory: URL, includePresentation: Bool = false,
                           progress: @escaping @MainActor @Sendable (String, URL) -> Void = { _, _ in },
                           shouldContinue: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> GraphicsReport {
        guard let executable else { throw GraphicsError.missingProbe }
        try WineCommand.validatePrefix(prefix)
        try await GraphicsBackendManager(prefix: prefix).verifySelection(bottle.activeGraphicsBackend)
        let runner = ProcessRunner()
        func check(_ api: String) async -> GraphicsAPIResult {
            let log = logDirectory.appendingPathComponent("graphics-\(api)-\(UUID().uuidString).log")
            await progress(api, log)
            do {
                let game = Game(name: "Graphics diagnostic", executable: executable, bottleID: bottle.id, arguments: [api])
                let command = try WineCommand.launch(runtime: bottle.runtime, game: game, prefix: prefix, graphics: bottle.activeGraphicsBackend,
                    d3dMetalOptions: bottle.d3dMetalOptions)
                let result = try await runner.run(command, logURL: log, timeout: .seconds(45))
                if result.exitCode == 0, let parsed = parse(LogReader.tail(log), api: api) { return parsed }
                return GraphicsAPIResult(api: api, passed: false, detail: "The diagnostic exited with code \(result.exitCode) without a valid result. See \(log.lastPathComponent).")
            } catch {
                return GraphicsAPIResult(api: api, passed: false, detail: "\(error.localizedDescription) See \(log.lastPathComponent).")
            }
        }
        let openGL = await check("opengl")
        guard await shouldContinue() else { throw CancellationError() }
        let direct3D = await check("d3d11")
        guard await shouldContinue() else { throw CancellationError() }
        let direct3D12 = await check("d3d12")
        guard await shouldContinue() else { throw CancellationError() }
        let dxil = await check("d3d12-dxil")
        var presentation: GraphicsAPIResult?
        if includePresentation {
            guard await shouldContinue() else { throw CancellationError() }
            presentation = await check("d3d12-present")
        }
        return GraphicsReport(checkedAt: Date(), backend: bottle.activeGraphicsBackend,
                              runtimeVersion: bottle.runtime.version, openGL: openGL, direct3D: direct3D, direct3D12: direct3D12,
                              direct3D12DXIL: dxil, direct3D12Presentation: presentation)
    }
}
