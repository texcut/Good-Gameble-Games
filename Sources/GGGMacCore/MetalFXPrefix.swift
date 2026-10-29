import Foundation

/// Streamline's NGX loader inspects the prefix file before loading it. A stale
/// Wine stub can pass LoadLibrary but fail that inspection with CRYPT_E_NO_MATCH.
public enum MetalFXPrefix {
    static let knownPlaceholderSHA256 = "76935dbf9665ab75549e61de1c912dd41f34c81bbf6cd985386717e3a2bb439b"

    public static func prepare(runtime: WineRuntime, prefix: URL) throws {
        try MetalFXBridge.validate(executable: runtime.executable)
        try WineCommand.validatePrefix(prefix)
        let root = prefix.resolvingSymlinksInPath()
        let system32 = root.appendingPathComponent("drive_c/windows/system32")
        let models = root.appendingPathComponent("drive_c/ProgramData/NVIDIA/NGX/models")
        for directory in [system32, models] {
            guard directory.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw MetalFXError.bridge }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = runtime.executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/wine/x86_64-windows/nvngx.dll")
        try installCoreDLL(source: source, destination: system32.appendingPathComponent("nvngx.dll"),
                           placeholderHash: knownPlaceholderSHA256)
        let manifest = models.appendingPathComponent("nvngx_config.txt")
        if (try? FileManager.default.attributesOfItem(atPath: manifest.path)) == nil {
            try Data("[global]\nversion = 1\n".utf8).write(to: manifest, options: .withoutOverwriting)
        }
    }

    static func installCoreDLL(source: URL, destination: URL, placeholderHash: String) throws {
        let fm = FileManager.default
        let sourceData = try Data(contentsOf: source)
        let sourceHash = VerifiedExecutableCopy.hash(sourceData)
        if let attrs = try? fm.attributesOfItem(atPath: destination.path) {
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.referenceCount] as? NSNumber)?.intValue == 1 else { throw MetalFXError.bridge }
            let hash = try RuntimeInstaller.checksum(of: destination)
            if hash == sourceHash { return }
            guard hash == placeholderHash else { throw MetalFXError.bridge }
            let backup = destination.appendingPathExtension("gggmac-wine-placeholder")
            if let backupAttrs = try? fm.attributesOfItem(atPath: backup.path) {
                guard backupAttrs[.type] as? FileAttributeType == .typeRegular,
                      (backupAttrs[.referenceCount] as? NSNumber)?.intValue == 1,
                      try RuntimeInstaller.checksum(of: backup) == placeholderHash else { throw MetalFXError.bridge }
            } else {
                try fm.copyItem(at: destination, to: backup)
                guard try RuntimeInstaller.checksum(of: backup) == placeholderHash else { throw MetalFXError.bridge }
            }
            // Only the exact known Wine placeholder is replaced; the game's
            // executable and any foreign/native DLL are never overwritten.
            guard try RuntimeInstaller.checksum(of: destination) == placeholderHash else { throw MetalFXError.bridge }
            try sourceData.write(to: destination, options: .atomic)
        } else {
            try sourceData.write(to: destination, options: .withoutOverwriting)
        }
        guard try RuntimeInstaller.checksum(of: destination) == sourceHash else { throw MetalFXError.bridge }
    }
}
