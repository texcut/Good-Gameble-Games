import Foundation
import CryptoKit

public enum WitcherMetalFXPatch {
    public static let originalSHA256 = "2df765398a3d1f165db418271be7200178320a4466817379f2fa0dc0001fb101"
    public static let patchedSHA256 = "5dc266a88709f0bfe3573ef5f5e3d055dfcd6a5a698a8ab4aa390be34015e419"
    // Published Wine feature-gate changes; normal graphics capability checks remain.
    // github.com/lypiut/macOs-crossover-game-patch/tree/main/games/witcher-3
    static let patch = VerifiedExecutableCopy(originalHash: originalSHA256, patchedHash: patchedSHA256,
        changes: [(0x1B77ECB, [0x75, 0x42], [0x90, 0x90]),
                  (0x1B7CE30, [0x74, 0x17], [0xEB, 0x17]),
                  (0x1ECEECD, [0x0F, 0x84, 0x66, 0x01, 0x00, 0x00], [0xE9, 0x67, 0x01, 0x00, 0x00, 0x90])])
    public static func isCandidate(_ executable: URL) -> Bool {
        executable.lastPathComponent.lowercased() == "witcher3.exe" &&
            executable.deletingLastPathComponent().lastPathComponent.lowercased() == "x64_dx12"
    }
    public static func preparedExecutable(for original: URL) throws -> URL {
        try patch.validate(original)
        return patch.destination(original)
    }
    public static func setEnabled(_ enabled: Bool, executable: URL) throws {
        guard isCandidate(executable) else { throw MetalFXError.unsupportedGame }
        try patch.setEnabled(enabled, executable: executable)
    }
}

/// Writes a separate executable only. The original is never replaced or removed.
struct VerifiedExecutableCopy: Sendable {
    let originalHash: String
    let patchedHash: String
    let changes: [(Int, [UInt8], [UInt8])]
    func destination(_ original: URL) -> URL {
        original.deletingLastPathComponent().appendingPathComponent(original.deletingPathExtension().lastPathComponent + "-gggmac-metalfx.exe")
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func read(_ file: URL) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.referenceCount] as? NSNumber)?.intValue == 1,
              let size = attrs[.size] as? NSNumber, size.intValue < 200_000_000 else { throw MetalFXError.unsupportedGame }
        return try Data(contentsOf: file)
    }
    func validate(_ original: URL) throws {
        guard try Self.hash(read(original)) == originalHash,
              try Self.hash(read(destination(original))) == patchedHash else { throw MetalFXError.unsupportedGame }
    }
    func setEnabled(_ enabled: Bool, executable: URL) throws {
        let fm = FileManager.default
        let output = destination(executable)
        let lock = output.appendingPathExtension("lock")
        do { try fm.createDirectory(at: lock, withIntermediateDirectories: false) }
        catch { throw MetalFXError.patchBusy }
        defer { try? fm.removeItem(at: lock) }
        let exists = (try? fm.attributesOfItem(atPath: output.path)) != nil
        if exists {
            guard try Self.hash(read(output)) == patchedHash else { throw MetalFXError.changedGame }
        }
        if !enabled {
            if exists { try fm.removeItem(at: output) }
            return
        }
        let input = try read(executable)
        guard Self.hash(input) == originalHash else { throw MetalFXError.unsupportedGame }
        if exists { return }
        var patched = input
        for (offset, before, after) in changes {
            guard offset >= 0, before.count == after.count, offset + before.count <= patched.count,
                  Array(patched[offset..<(offset + before.count)]) == before else { throw MetalFXError.unsupportedGame }
            patched.replaceSubrange(offset..<(offset + before.count), with: after)
        }
        guard Self.hash(patched) == patchedHash else { throw MetalFXError.unsupportedGame }
        let stage = output.deletingLastPathComponent().appendingPathComponent(".metalfx-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: stage) }
        try patched.write(to: stage, options: .withoutOverwriting)
        let attrs = try fm.attributesOfItem(atPath: executable.path)
        if let permissions = attrs[.posixPermissions] { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: stage.path) }
        guard try Self.hash(read(executable)) == originalHash else { throw MetalFXError.changedGame }
        try fm.moveItem(at: stage, to: output)
        try validate(executable)
    }
}
