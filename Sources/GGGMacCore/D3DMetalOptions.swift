import Foundation

public enum D3DMetalBackend: String, Codable, CaseIterable, Sendable {
    case automatic, metal3, metal4
    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .metal3: "Metal 3"
        case .metal4: "Metal 4 (macOS 27+)"
        }
    }
}

/// Environment-wide: all Wine clients must agree with the server's MSync mode.
public struct D3DMetalOptions: Codable, Equatable, Sendable {
    public var rayTracingEnabled: Bool
    public var msyncEnabled: Bool
    public var backend: D3DMetalBackend
    public var showPerformanceHUD: Bool
    public var metalFXEnabled: Bool

    public init(rayTracingEnabled: Bool = false, msyncEnabled: Bool = false,
                backend: D3DMetalBackend = .automatic, showPerformanceHUD: Bool = false, metalFXEnabled: Bool = false) {
        self.rayTracingEnabled = rayTracingEnabled; self.msyncEnabled = msyncEnabled
        self.backend = backend; self.showPerformanceHUD = showPerformanceHUD
        self.metalFXEnabled = metalFXEnabled
    }

    private enum CodingKeys: String, CodingKey { case rayTracingEnabled, msyncEnabled, backend, showPerformanceHUD, metalFXEnabled }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rayTracingEnabled = try c.decode(Bool.self, forKey: .rayTracingEnabled)
        msyncEnabled = try c.decode(Bool.self, forKey: .msyncEnabled)
        backend = try c.decode(D3DMetalBackend.self, forKey: .backend)
        showPerformanceHUD = try c.decode(Bool.self, forKey: .showPerformanceHUD)
        metalFXEnabled = try c.decodeIfPresent(Bool.self, forKey: .metalFXEnabled) ?? false
    }

    public var environment: [String: String] {
        var result = ["D3DM_SUPPORT_DXR": rayTracingEnabled ? "1" : "0", "ROSETTA_ADVERTISE_AVX": "1",
                      "WINEMSYNC": msyncEnabled ? "1" : "0", "MTL_HUD_ENABLED": showPerformanceHUD ? "1" : "0",
                      "D3DM_ENABLE_METALFX": metalFXEnabled ? "1" : "0"]
        if backend != .automatic { result["D3DM_MTL4"] = backend == .metal4 ? "1" : "0" }
        return result
    }
    public var summary: String {
        "RT \(rayTracingEnabled ? "requested" : "off") · MSync \(msyncEnabled ? "on" : "off") · \(backend.title) · MetalFX \(metalFXEnabled ? "on" : "off") · HUD \(showPerformanceHUD ? "on" : "off")"
    }
}
