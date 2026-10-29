import Foundation

/// A small, optional Windows installer from the game's official distribution.
/// GGGMac does not accept installer agreements or download copyrighted TTD data.
public enum TestGameDownload {
    public static let source = URL(string: "https://www.openttd.org/downloads/openttd-releases/latest")!
    public static let url = URL(string: "https://cdn.openttd.org/openttd-releases/15.3/openttd-15.3-windows-win64.exe")!
    public static let sha256 = "f061a7fd16ebe682edd45b02d048f068735a4a296c2b2b325246b10e01c748bf"

    public static func download(root: URL) async throws -> URL {
        let directory = root.appendingPathComponent("Downloads", isDirectory: true)
        let cached = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: cached.path), try RuntimeInstaller.checksum(of: cached) == sha256 { return cached }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else { throw LauncherError.gameDownloadFailed }
        try Task.checkCancellation()
        return try cacheVerifiedInstaller(temporary, directory: directory, expectedSHA256: sha256)
    }

    static func cacheVerifiedInstaller(_ file: URL, directory: URL, expectedSHA256: String) throws -> URL {
        guard try RuntimeInstaller.checksum(of: file) == expectedSHA256 else { throw LauncherError.gameDownloadFailed }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var destination = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Preserve an unexpected existing file rather than replacing it.
            destination = directory.appendingPathComponent("openttd-15.3-\(UUID().uuidString).exe")
        }
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }
}
