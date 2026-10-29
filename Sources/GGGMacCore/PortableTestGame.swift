import Foundation

/// The official, pinned Windows x64 distribution; includes the game's license and manual.
public actor PortableTestGame {
    public static let source = URL(string: "https://github.com/fragglet/sdl-sopwith/releases/tag/sdl-sopwith-2.9.0")!
    public static let url = URL(string: "https://github.com/fragglet/sdl-sopwith/releases/download/sdl-sopwith-2.9.0/sdl-sopwith-2.9.0-win64.zip")!
    public static let sha256 = "b664b5fac5feac3f3a23b7082909d9280a95ae40cc7f8daeff089b191bcc746c"
    static let files: Set<String> = ["Configuration.html", "FAQ.html", "COPYING.html", "Manual.html", "Mission.html", "NEWS.html", "README.html", "SDL2.dll", "sopwith.exe"]
    private struct Receipt: Codable { let archiveHash: String; let hashes: [String: String] }
    public init() {}

    public func install(root: URL, prefix: URL) async throws -> URL {
        let directory = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(Self.url.lastPathComponent)
        if (try? RuntimeInstaller.checksum(of: cached)) == Self.sha256 {
            return try await unpack(archive: cached, prefix: prefix)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: Self.url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", try RuntimeInstaller.checksum(of: temporary) == Self.sha256 else {
            throw LauncherError.gameSetupFailed("The official Sopwith download did not pass verification.")
        }
        try Task.checkCancellation()
        let destination = FileManager.default.fileExists(atPath: cached.path)
            ? directory.appendingPathComponent("sopwith-\(UUID().uuidString).zip") : cached
        try FileManager.default.copyItem(at: temporary, to: destination)
        return try await unpack(archive: destination, prefix: prefix)
    }

    func unpack(archive: URL, prefix: URL, expectedHash: String = PortableTestGame.sha256) async throws -> URL {
        // Authenticate the entire archive before asking libarchive to extract it.
        guard try RuntimeInstaller.checksum(of: archive) == expectedHash else {
            throw LauncherError.gameSetupFailed("The Sopwith archive checksum did not match.")
        }
        try WineCommand.validatePrefix(prefix)
        let manager = FileManager.default
        let drive = prefix.appendingPathComponent("drive_c")
        let parent = drive.appendingPathComponent("GGGMac Games")
        for folder in [drive, parent] {
            if let values = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                throw LauncherError.gameSetupFailed("The game installation folder is a symbolic link. Choose another environment.")
            }
        }
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = parent.appendingPathComponent("sdl-sopwith-2.9.0")
        let executable = target.appendingPathComponent("sopwith.exe")
        if manager.fileExists(atPath: target.path) {
            guard try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                  let receipt = try? JSONDecoder().decode(Receipt.self, from: Data(contentsOf: target.appendingPathComponent(".gggmac-package.json"))),
                  receipt.archiveHash == expectedHash, Set(receipt.hashes.keys) == Self.files else {
                throw LauncherError.gameSetupFailed("The Sopwith folder already exists and was preserved. Rename it before trying again.")
            }
            for (name, hash) in receipt.hashes {
                let file = target.appendingPathComponent(name)
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      try RuntimeInstaller.checksum(of: file) == hash else {
                    throw LauncherError.gameSetupFailed("An installed Sopwith package file changed. Its folder was preserved.")
                }
            }
            return executable
        }
        let staging = parent.appendingPathComponent(".install-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let listing = try await tar(["-tf", archive.path], in: staging)
        let entries = listing.split(whereSeparator: \.isNewline).map(String.init)
        guard entries.count == Self.files.count, Set(entries) == Self.files else {
            throw LauncherError.gameSetupFailed("The Sopwith archive contains unexpected paths.")
        }
        try Task.checkCancellation()
        _ = try await tar(["-xf", archive.path, "-C", staging.path, "--no-same-owner", "--no-same-permissions"], in: staging)
        var hashes: [String: String] = [:]
        for name in Self.files {
            let file = staging.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw LauncherError.gameSetupFailed("The Sopwith package contains an unexpected file type.")
            }
            hashes[name] = try RuntimeInstaller.checksum(of: file)
        }
        try JSONEncoder().encode(Receipt(archiveHash: expectedHash, hashes: hashes))
            .write(to: staging.appendingPathComponent(".gggmac-package.json"), options: .atomic)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: target)
        return executable
    }

    private func tar(_ arguments: [String], in directory: URL) async throws -> String {
        let log = directory.appendingPathComponent(".unpack-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let result = try await ProcessRunner().run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: arguments), logURL: log, timeout: .seconds(30))
        guard result.exitCode == 0 else { throw LauncherError.gameSetupFailed("The Sopwith ZIP could not be unpacked.") }
        return LogReader.tail(log)
    }
}
