import Foundation
import CryptoKit

public struct RuntimePackage: Codable, Equatable, Sendable {
    public let id: String
    public let downloadURL: URL
    public let sha256: String
    public let archiveBytes: Int64
    public let executablePath: String

    public static let whiskyWine = RuntimePackage(
        id: "whisky-wine-3.1.1",
        downloadURL: URL(string: "https://github.com/frankea/Whisky/releases/download/v3.1.1/Libraries.tar.gz")!,
        sha256: "01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3",
        archiveBytes: 332_438_526,
        executablePath: "Wine/bin/wine")
}

public enum RuntimeInstallError: LocalizedError {
    case checksum, download, archive(String), destinationExists, requirements(String), inProgress
    public var errorDescription: String? {
        switch self {
        case .checksum: "The runtime download did not match the expected size or SHA-256 checksum. Nothing was installed. Try downloading again."
        case .download: "The runtime server did not return a successful HTTPS download. Try again later."
        case let .archive(detail): "The runtime archive could not be installed safely. \(detail)"
        case .destinationExists: "The runtime folder already exists but could not be verified. It has been preserved. Check the Runtimes folder in GGGMac’s application data."
        case let .requirements(detail): detail
        case .inProgress: "A runtime installation is already in progress."
        }
    }
}

/// Installs one checksum-pinned package into an owned, versioned folder.
/// Downloading a runtime does not update other runtimes or Windows environments.
public actor RuntimeInstaller {
    public typealias Progress = @MainActor @Sendable (String) -> Void
    public let root: URL
    private let package: RuntimePackage
    private var installing = false

    public init(root: URL, package: RuntimePackage = .whiskyWine) { self.root = root; self.package = package }

    public static var requirementIssue: String? {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) else {
            return "The managed runtime requires macOS 15 or later. You can still connect another compatible Wine runtime manually."
        }
        #if arch(arm64)
        guard FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime") else {
            return "This Wine runtime needs Apple’s Rosetta 2 on Apple Silicon. Install Rosetta through macOS, then try again."
        }
        #endif
        return nil
    }

    public nonisolated static func directory(root: URL, package: RuntimePackage = .whiskyWine) -> URL {
        root.appendingPathComponent("Runtimes", isDirectory: true).appendingPathComponent(package.id, isDirectory: true)
    }

    public nonisolated static func installedExecutable(root: URL, package: RuntimePackage = .whiskyWine) -> URL? {
        let directory = directory(root: root, package: package)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("gggmac-runtime.json")),
              let receipt = try? JSONDecoder().decode(RuntimePackage.self, from: data), receipt == package else { return nil }
        let executable = directory.appendingPathComponent(package.executablePath)
        guard (try? WineCommand.validateRuntime(executable)) != nil else { return nil }
        return executable
    }

    public func downloadAndInstall(progress: @escaping Progress) async throws -> URL {
        guard !installing else { throw RuntimeInstallError.inProgress }
        installing = true
        defer { installing = false }
        if let existing = Self.installedExecutable(root: root, package: package) { return existing }
        if let issue = Self.requirementIssue { throw RuntimeInstallError.requirements(issue) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let free = try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber,
           free.uint64Value < 2_000_000_000 {
            throw RuntimeInstallError.requirements("Free at least 2 GB of disk space before installing the Wine runtime.")
        }
        try Task.checkCancellation()
        await progress("Downloading Wine · 332 MB. This may take a few minutes…")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1200
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: package.downloadURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else { throw RuntimeInstallError.download }
        return try await unpack(temporary, progress: progress)
    }

    /// Used by integration checks with the exact published archive; does not run downloaded code.
    public func installArchive(_ archive: URL, progress: @escaping Progress = { _ in }) async throws -> URL {
        guard !installing else { throw RuntimeInstallError.inProgress }
        installing = true
        defer { installing = false }
        if let existing = Self.installedExecutable(root: root, package: package) { return existing }
        return try await unpack(archive, progress: progress)
    }

    private func unpack(_ archive: URL, progress: @escaping Progress) async throws -> URL {
        let manager = FileManager.default
        await progress("Verifying runtime size and SHA-256 checksum…")
        try Task.checkCancellation()
        guard try manager.attributesOfItem(atPath: archive.path)[.size] as? Int64 == package.archiveBytes,
              try Self.checksum(of: archive) == package.sha256 else { throw RuntimeInstallError.checksum }
        let destination = Self.directory(root: root, package: package)
        guard !manager.fileExists(atPath: destination.path) else { throw RuntimeInstallError.destinationExists }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let runner = ProcessRunner()
        let listing = staging.appendingPathComponent("entries.txt")
        let listResult = try await runner.run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-tzf", archive.path]), logURL: listing, timeout: .seconds(120))
        guard listResult.exitCode == 0 else { throw RuntimeInstallError.archive(LogReader.tail(listing, maxBytes: 2048)) }
        guard let size = try manager.attributesOfItem(atPath: listing.path)[.size] as? Int64, size < 10_000_000 else {
            throw RuntimeInstallError.archive("The archive file list is too large.")
        }
        let entries = try String(contentsOf: listing, encoding: .utf8).split(separator: "\n")
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            (entry == "Libraries" || entry.hasPrefix("Libraries/")) &&
            !entry.split(separator: "/").contains("..") && !entry.contains("\\") && !entry.contains("\r")
        }) else { throw RuntimeInstallError.archive("Unexpected or unsafe archive paths.") }
        await progress("Unpacking Wine into its own versioned folder…")
        try Task.checkCancellation()
        let extractionLog = staging.appendingPathComponent("extract.log")
        let extraction = try await runner.run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["--no-same-owner", "--no-same-permissions", "-xzf", archive.path, "-C", staging.path]),
            logURL: extractionLog, timeout: .seconds(180))
        guard extraction.exitCode == 0 else { throw RuntimeInstallError.archive(LogReader.tail(extractionLog, maxBytes: 2048)) }
        let tree = staging.appendingPathComponent("Libraries", isDirectory: true)
        try Self.validateTree(tree)
        try WineCommand.validateRuntime(tree.appendingPathComponent(package.executablePath))
        try Task.checkCancellation()
        try JSONEncoder().encode(package).write(to: tree.appendingPathComponent("gggmac-runtime.json"), options: .atomic)
        try manager.moveItem(at: tree, to: destination)
        return destination.appendingPathComponent(package.executablePath)
    }

    public nonisolated static func checksum(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func validateTree(_ root: URL) throws {
        let manager = FileManager.default
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw RuntimeInstallError.archive("The runtime root must be a regular directory.")
        }
        let base = root.resolvingSymlinksInPath().path + "/"
        var directories = [root]
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                if values.isSymbolicLink == true {
                    let target = try manager.destinationOfSymbolicLink(atPath: url.path)
                    guard !target.hasPrefix("/"), url.resolvingSymlinksInPath().path.hasPrefix(base) else {
                        throw RuntimeInstallError.archive("A symbolic link points outside the runtime.")
                    }
                } else if values.isDirectory == true { directories.append(url) }
                else if values.isRegularFile != true { throw RuntimeInstallError.archive("Unsupported archive file type.") }
            }
        }
    }
}
