import Foundation

/// Prefix-local DLL deployment with a write-ahead receipt and original-file
/// backups. No shared runtime files or registry entries are changed.
public actor GraphicsBackendManager {
    private struct FileRecord: Codable {
        let path: String
        let originalHash: String?
        let installedHash: String
    }
    private struct Receipt: Codable { let files: [FileRecord] }
    private let prefix: URL
    private var state: URL { prefix.appendingPathComponent(".gggmac-graphics", isDirectory: true) }
    private static let names = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]

    public init(prefix: URL) { self.prefix = prefix.resolvingSymlinksInPath() }

    public static func payload(for runtime: WineRuntime) -> URL? {
        let root = runtime.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent("gggmac-runtime.json")),
              let receipt = try? JSONDecoder().decode(RuntimePackage.self, from: data), receipt == .whiskyWine,
              ExecutableIdentity.matches(runtime.executable, root.appendingPathComponent(receipt.executablePath)),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("Wine/lib/wine/x86_64-unix/winemetal.so").path) else { return nil }
        let payload = root.appendingPathComponent("DXMT", isDirectory: true)
        guard names.allSatisfy({ FileManager.default.fileExists(atPath: payload.appendingPathComponent("x64/\($0)").path) }),
              ["d3d11.dll", "dxgi.dll", "d3d10core.dll"].allSatisfy({ isNativePE(payload.appendingPathComponent("x64/\($0)")) }) else { return nil }
        return payload
    }

    private static func isNativePE(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 80), data.count == 80, data.prefix(2) == Data("MZ".utf8) else { return false }
        return data[64..<80] != Data("Wine builtin DLL".utf8)
    }

    /// Returns true only if a new deployment was made.
    @discardableResult
    public func enableDXMT(payload: URL) throws -> Bool {
        try WineCommand.validatePrefix(prefix)
        try validateStateDirectory()
        if FileManager.default.fileExists(atPath: state.appendingPathComponent("receipt.json").path) {
            try verifyInstalled()
            return false
        }
        guard !FileManager.default.fileExists(atPath: state.path) else { throw GraphicsError.conflict(state.path) }
        var sources: [(String, URL)] = []
        for (architecture, directory) in [("x64", "system32"), ("x32", "syswow64")] {
            if directory == "syswow64", !FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c/windows/syswow64").path) { continue }
            for name in Self.names {
                let source = payload.appendingPathComponent("\(architecture)/\(name)")
                guard FileManager.default.fileExists(atPath: source.path), name == "winemetal.dll" || Self.isNativePE(source) else { throw GraphicsError.unavailable }
                let path = "drive_c/windows/\(directory)/\(name)"
                try validateTarget(path)
                sources.append((path, source))
            }
        }
        try FileManager.default.createDirectory(at: state.appendingPathComponent("originals"), withIntermediateDirectories: true)
        var records: [FileRecord] = []
        do {
            for (path, source) in sources {
                let target = prefix.appendingPathComponent(path)
                let originalHash: String?
                if FileManager.default.fileExists(atPath: target.path) {
                    originalHash = try RuntimeInstaller.checksum(of: target)
                    let backup = state.appendingPathComponent("originals/\(path)")
                    try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: target, to: backup)
                } else { originalHash = nil }
                records.append(FileRecord(path: path, originalHash: originalHash, installedHash: try RuntimeInstaller.checksum(of: source)))
            }
            try JSONEncoder().encode(Receipt(files: records)).write(to: state.appendingPathComponent("receipt.json"), options: .atomic)
        } catch { try? FileManager.default.removeItem(at: state); throw error }
        do {
            for (path, source) in sources { try Data(contentsOf: source).write(to: prefix.appendingPathComponent(path), options: .atomic) }
        } catch {
            try restore()
            throw error
        }
        return true
    }

    public func verifyInstalled() throws {
        let receipt = try readReceipt()
        for file in receipt.files {
            try validateTarget(file.path)
            guard (try? RuntimeInstaller.checksum(of: prefix.appendingPathComponent(file.path))) == file.installedHash else {
                throw GraphicsError.conflict(file.path)
            }
        }
    }

    public func verifySelection(_ backend: GraphicsBackend) throws {
        if backend == .dxmt { try verifyInstalled() }
        else if FileManager.default.fileExists(atPath: state.path) {
            throw GraphicsError.conflict("Graphics files are deployed but the library selects Runtime default. Open Graphics settings and restore Runtime default.")
        }
    }

    public func restore() throws {
        try validateStateDirectory()
        guard FileManager.default.fileExists(atPath: state.path) else { return }
        let receipt = try readReceipt()
        // Validate every file before restoring any, preserving outside changes.
        for file in receipt.files {
            try validateTarget(file.path)
            let hash = try? RuntimeInstaller.checksum(of: prefix.appendingPathComponent(file.path))
            guard hash == file.installedHash || hash == file.originalHash else { throw GraphicsError.conflict(file.path) }
            if let original = file.originalHash {
                guard (try? RuntimeInstaller.checksum(of: state.appendingPathComponent("originals/\(file.path)"))) == original else { throw GraphicsError.corruptBackup }
            }
        }
        for file in receipt.files {
            let target = prefix.appendingPathComponent(file.path)
            if file.originalHash != nil {
                try Data(contentsOf: state.appendingPathComponent("originals/\(file.path)")).write(to: target, options: .atomic)
            } else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }
        try FileManager.default.removeItem(at: state)
    }

    private func validateStateDirectory() throws {
        if let type = try? FileManager.default.attributesOfItem(atPath: state.path)[.type] as? FileAttributeType,
           type != .typeDirectory { throw GraphicsError.conflict(state.path) }
    }
    private func readReceipt() throws -> Receipt {
        try validateStateDirectory()
        let x64 = Set(Self.names.map { "drive_c/windows/system32/\($0)" })
        let x32 = Set(Self.names.map { "drive_c/windows/syswow64/\($0)" })
        guard let data = try? Data(contentsOf: state.appendingPathComponent("receipt.json")),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), !receipt.files.isEmpty,
              Set(receipt.files.map(\.path)).count == receipt.files.count,
              (Set(receipt.files.map(\.path)) == x64 || Set(receipt.files.map(\.path)) == x64.union(x32)),
              receipt.files.allSatisfy({ file in
                  ["system32", "syswow64"].contains { directory in
                      Self.names.contains { file.path == "drive_c/windows/\(directory)/\($0)" }
                  }
              }) else { throw GraphicsError.corruptBackup }
        return receipt
    }
    private func validateTarget(_ path: String) throws {
        let target = prefix.appendingPathComponent(path)
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard parent.hasPrefix(prefix.path + "/") else { throw GraphicsError.conflict(path) }
        if let type = try? FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType,
           type != .typeRegular { throw GraphicsError.conflict(path) }
    }
}
