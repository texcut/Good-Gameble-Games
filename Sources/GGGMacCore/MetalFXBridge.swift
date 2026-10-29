import Foundation

/// Uses only the owner's already verified Apple payload, outside the app bundle.
public enum MetalFXBridge {
    private static let forwarder = "../../external/libd3dshared.dylib"

    private static func paths(_ executable: URL) throws -> (URL, URL, URL) {
        try D3DMetalRuntime.validate(executable: executable)
        guard let receipt = D3DMetalRuntime.receipt(for: executable) else { throw D3DMetalSetupError.runtime }
        let root = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let windows = root.appendingPathComponent("Wine/lib/wine/x86_64-windows")
        let unix = root.appendingPathComponent("Wine/lib/wine/x86_64-unix")
        for folder in [windows, unix] {
            guard folder.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw MetalFXError.bridge }
        }
        for name in ["nvapi64.dll", "nvngx-on-metalfx.dll"] {
            let file = windows.appendingPathComponent(name)
            guard let hash = receipt.files["Wine/lib/wine/x86_64-windows/\(name)"],
                  try RuntimeInstaller.checksum(of: file) == hash else { throw MetalFXError.bridge }
        }
        for name in ["nvapi64.so", "nvngx-on-metalfx.so"] {
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: unix.appendingPathComponent(name).path)) == forwarder else {
                throw MetalFXError.bridge
            }
        }
        return (windows.appendingPathComponent("nvngx-on-metalfx.dll"), windows.appendingPathComponent("nvngx.dll"), unix.appendingPathComponent("nvngx.so"))
    }

    public static func validate(executable: URL) throws {
        let (source, dll, unix) = try paths(executable)
        try validateDLL(dll, source: source)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: unix.path)) == forwarder else { throw MetalFXError.bridge }
    }

    private static func validateDLL(_ file: URL, source: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              try RuntimeInstaller.checksum(of: file) == RuntimeInstaller.checksum(of: source) else { throw MetalFXError.bridge }
    }

    public static func prepare(executable: URL) throws {
        let (source, dll, unix) = try paths(executable)
        let fm = FileManager.default
        let dllExists = (try? fm.attributesOfItem(atPath: dll.path)) != nil
        let unixExists = (try? fm.attributesOfItem(atPath: unix.path)) != nil
        // Refuse conflicting files before creating either alias.
        if dllExists { try validateDLL(dll, source: source) }
        if unixExists, (try? fm.destinationOfSymbolicLink(atPath: unix.path)) != forwarder { throw MetalFXError.bridge }
        var created: [URL] = []
        do {
            if !dllExists {
                let stage = dll.deletingLastPathComponent().appendingPathComponent(".nvngx-\(UUID().uuidString).tmp")
                defer { try? fm.removeItem(at: stage) }
                try fm.copyItem(at: source, to: stage)
                try validateDLL(stage, source: source)
                try fm.moveItem(at: stage, to: dll)
                created.append(dll)
            }
            if !unixExists {
                try fm.createSymbolicLink(atPath: unix.path, withDestinationPath: forwarder)
                created.append(unix)
            }
            try validate(executable: executable)
        } catch {
            for file in created.reversed() { try? fm.removeItem(at: file) }
            throw error
        }
    }
}

public enum MetalFXError: LocalizedError {
    case bridge, unsupportedGame, changedGame, patchBusy
    public var errorDescription: String? {
        switch self {
        case .bridge: "The Apple MetalFX bridge is missing or conflicts with another file. Existing files were preserved."
        case .unsupportedGame: "This Witcher executable is not the verified 5.01 build. It has not been modified."
        case .changedGame: "The Witcher executable changed during setup. Stop other installers or file verification and try again."
        case .patchBusy: "Another Witcher patch operation or its recovery lock is present. The executable was preserved."
        }
    }
}
