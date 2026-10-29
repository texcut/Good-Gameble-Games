import Foundation

public enum GameLaunchProfile: String, Codable, Sendable {
    case sdlDirect3D11
    case fteDirect3D11

    public var requiresDXMT: Bool { true }
    public var rendererLabel: String { self == .sdlDirect3D11 ? "SDL" : "FTE" }
    public func expectsExitCode(_ code: Int32, output: String = "") -> Bool {
        // The pinned FTE SVN 6202 Windows Sys_Quit explicitly calls exit(1).
        if output.contains("wine: Unhandled page fault") || output.contains("wine: Unhandled exception") { return false }
        return code == 0 || (self == .fteDirect3D11 && code == 1)
    }

    public static let libreQuakeArguments = ["-nohome", "-window", "-width", "1280", "-height", "720", "-condebug",
        "+set", "vid_renderer", "d3d11", "+set", "vid_fullscreen", "0", "+set", "vid_width", "1280", "+set", "vid_height", "720",
        "+set", "show_fps", "1", "+wait", "+wait", "+setrenderer"]
    public static let libreQuakeBenchmarkArguments = ["+set", "cl_maxfps", "0", "+set", "vid_wait", "0",
        "+alias", "f_timedemoend", "quit", "+timedemo", "demo1"]
}

/// Evidence from the game's renderer creation or active-renderer log.
public struct GameRendererReport: Codable, Equatable, Sendable {
    public let renderer: String
    public let checkedAt: Date
    public var usesDirect3D11: Bool { renderer == "direct3d11" }

    public static func parse(_ log: String, at date: Date = Date()) -> GameRendererReport? {
        let pattern = #"Created renderer: (direct3d11|direct3d12|direct3d|opengl|opengles2|opengles|software|metal)(?=[\s"\\]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: log, range: NSRange(log.startIndex..., in: log)).last,
              let range = Range(match.range(at: 1), in: log) else { return nil }
        return GameRendererReport(renderer: String(log[range]), checkedAt: date)
    }

    public static func parseFTE(_ log: String, at date: Date = Date()) -> GameRendererReport? {
        // FTE's setrenderer listing marks the actual active renderer with (current).
        let pattern = #"\b(D3D11|D3D9|D3D8|Vulkan|OpenGL|GL|Soft|None|Headless)(?:[^\r\n"\\])*\(current\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.matches(in: log, range: NSRange(log.startIndex..., in: log)).last,
              let range = Range(match.range(at: 1), in: log) else { return nil }
        let value = String(log[range]).lowercased()
        return GameRendererReport(renderer: value == "d3d11" ? "direct3d11" : value, checkedAt: date)
    }

    public static func parse(_ log: String, profile: GameLaunchProfile?, at date: Date = Date()) -> GameRendererReport? {
        profile == .fteDirect3D11 ? parseFTE(log, at: date) : parse(log, at: date)
    }
}

public struct GameBenchmark: Codable, Equatable, Sendable {
    public let frames: Int
    public let seconds: Double
    public let framesPerSecond: Double
    public let measuredAt: Date
    public let width: Int
    public let height: Int
    public let backend: GraphicsBackend
    public let runtimeVersion: String

    public static func parse(_ log: String, runtimeVersion: String, at date: Date = Date()) -> GameBenchmark? {
        let pattern = #"\b([0-9]+) frames\s+([0-9]+\.[0-9]+) seconds\s+([0-9]+\.[0-9]+) fps\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: log, range: NSRange(log.startIndex..., in: log)).last else { return nil }
        func value(_ index: Int) -> String { Range(match.range(at: index), in: log).map { String(log[$0]) } ?? "" }
        // The pinned demo1 contains 4,526 measured frames. Interrupted demos also
        // print an FPS line, so partial runs must not become benchmark results.
        guard let frames = Int(value(1)), frames == 4526, let seconds = Double(value(2)), seconds > 0,
              let fps = Double(value(3)), fps > 0, fps.isFinite else { return nil }
        guard GameRendererReport.parseFTE(log)?.usesDirect3D11 == true,
              let modes = try? NSRegularExpression(pattern: #"Setting (?:windowed mode|mode|fullscreen windowed)[^\r\n]*"#),
              let mode = modes.matches(in: log, range: NSRange(log.startIndex..., in: log)).last,
              let range = Range(mode.range, in: log),
              log[range].hasPrefix("Setting windowed mode 1280*720 Direct3D11") else { return nil }
        return GameBenchmark(frames: frames, seconds: seconds, framesPerSecond: fps, measuredAt: date,
                             width: 1280, height: 720, backend: .dxmt, runtimeVersion: runtimeVersion)
    }
}
