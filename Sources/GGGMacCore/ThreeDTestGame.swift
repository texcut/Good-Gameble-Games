import Foundation

/// Official, checksum-pinned free game data and Windows engine, downloaded separately.
public actor ThreeDTestGame {
    public static let source = URL(string: "https://github.com/lavenderdotpet/LibreQuake/releases/tag/v0.09-beta")!
    public static let engineSource = URL(string: "https://fte.triptohell.info/downloads")!
    public static let dataURL = URL(string: "https://github.com/lavenderdotpet/LibreQuake/releases/download/v0.09-beta/lite.zip")!
    public static let engineURL = URL(string: "https://fte.triptohell.info/moodles/win64/fteqw_win64.zip")!
    public static let dataHash = "428e736b2f01d953e09a08c60bee975bdc4a0ac2219e97fa095c8af41754da83"
    public static let engineHash = "c39fcf26eb4b7370d2246ec3bc1e81e1d7db1087ee28cbbf579ab6348c05537e"
    private struct Receipt: Codable { let engine: String; let data: String; let files: [String: String] }
    public init() {}

    public func install(root: URL, prefix: URL) async throws -> URL {
        let directory = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let engine = try await download(Self.engineURL, hash: Self.engineHash, name: "fteqw-win64-6202.zip", directory: directory)
        let data = try await download(Self.dataURL, hash: Self.dataHash, name: "librequake-0.09-lite.zip", directory: directory)
        return try await unpack(engineArchive: engine, dataArchive: data, prefix: prefix)
    }

    private func download(_ url: URL, hash: String, name: String, directory: URL) async throws -> URL {
        let cached = directory.appendingPathComponent(name)
        if (try? RuntimeInstaller.checksum(of: cached)) == hash { return cached }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", try RuntimeInstaller.checksum(of: temporary) == hash else {
            throw LauncherError.gameSetupFailed("The LibreQuake or FTE download did not pass checksum verification.")
        }
        try Task.checkCancellation()
        let destination = FileManager.default.fileExists(atPath: cached.path)
            ? directory.appendingPathComponent("\(UUID().uuidString)-\(name)") : cached
        try FileManager.default.copyItem(at: temporary, to: destination)
        return destination
    }

    func unpack(engineArchive: URL, dataArchive: URL, prefix: URL,
                engineHash: String = ThreeDTestGame.engineHash, dataHash: String = ThreeDTestGame.dataHash) async throws -> URL {
        guard try RuntimeInstaller.checksum(of: engineArchive) == engineHash,
              try RuntimeInstaller.checksum(of: dataArchive) == dataHash else {
            throw LauncherError.gameSetupFailed("The LibreQuake or FTE archive checksum did not match.")
        }
        try WineCommand.validatePrefix(prefix)
        let fm = FileManager.default
        let drive = prefix.appendingPathComponent("drive_c")
        let parent = drive.appendingPathComponent("GGGMac Games")
        for folder in [drive, parent] {
            if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw LauncherError.gameSetupFailed("The game installation folder is a symbolic link.")
            }
        }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = parent.appendingPathComponent("librequake-0.09-fte-6202")
        if fm.fileExists(atPath: target.path) {
            guard (try target.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
                  let receipt = try? JSONDecoder().decode(Receipt.self, from: Data(contentsOf: target.appendingPathComponent(".gggmac-package.json"))),
                  receipt.engine == engineHash, receipt.data == dataHash,
                  receipt.files["fteqw64.exe"] != nil, receipt.files["id1/pak0.pak"] != nil,
                  receipt.files["id1/pak1.pak"] != nil else {
                throw LauncherError.gameSetupFailed("The LibreQuake folder already exists and was preserved. Rename it before trying again.")
            }
            for (path, hash) in receipt.files {
                guard Self.safeRelativePath(path) else { throw LauncherError.gameSetupFailed("Invalid package receipt.") }
                let file = target.appendingPathComponent(path)
                try Self.requireRegularPath(file, inside: target)
                guard try RuntimeInstaller.checksum(of: file) == hash else {
                    throw LauncherError.gameSetupFailed("An installed LibreQuake package file changed. Its folder and saves were preserved.")
                }
            }
            return target.appendingPathComponent("fteqw64.exe")
        }
        let staging = parent.appendingPathComponent(".install-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let engine = staging.appendingPathComponent("engine"), data = staging.appendingPathComponent("data")
        try fm.createDirectory(at: engine, withIntermediateDirectories: false)
        try fm.createDirectory(at: data, withIntermediateDirectories: false)
        let engineList = try await tar(["-tf", engineArchive.path], directory: staging).split(whereSeparator: \.isNewline).map(String.init)
        guard engineList.count == 3, Set(engineList) == ["fteqw64.exe", "fteqw_readme.txt", "version.txt"] else {
            throw LauncherError.gameSetupFailed("The FTE archive contains unexpected paths.")
        }
        let dataList = try await tar(["-tf", dataArchive.path], directory: staging).split(whereSeparator: \.isNewline).map(String.init)
        guard !dataList.isEmpty, dataList.count <= 100, Set(dataList).count == dataList.count,
              dataList.allSatisfy({ $0 == "lite/" || ($0.hasPrefix("lite/id1/") && Self.safeRelativePath($0)) }) else {
            throw LauncherError.gameSetupFailed("The LibreQuake archive contains unexpected paths.")
        }
        try Task.checkCancellation()
        _ = try await tar(["--no-same-owner", "--no-same-permissions", "-xf", engineArchive.path, "-C", engine.path], directory: staging)
        _ = try await tar(["--no-same-owner", "--no-same-permissions", "-xf", dataArchive.path, "-C", data.path], directory: staging)
        let tree = data.appendingPathComponent("lite")
        _ = try Self.hashTree(engine)
        try fm.copyItem(at: engine.appendingPathComponent("fteqw64.exe"), to: tree.appendingPathComponent("fteqw64.exe"))
        for name in ["fteqw_readme.txt", "version.txt"] {
            try fm.copyItem(at: engine.appendingPathComponent(name), to: tree.appendingPathComponent(name))
        }
        try Data("Windows FTE engine, revision 6202: \(Self.engineSource.absoluteString)\nGPL-2.0 license: id1/docs/misc-docs/COPYING\nEngine source: https://sourceforge.net/p/fteqw/code/6202/tree/trunk/\nLibreQuake data and license information: id1/docs/README-IMPORTANT-LICENCE-INFO\n".utf8)
            .write(to: tree.appendingPathComponent("GGGMac-sources.txt"))
        let files = try Self.hashTree(tree)
        guard files["id1/pak0.pak"] != nil, files["id1/pak1.pak"] != nil,
              files["id1/docs/misc-docs/COPYING"] != nil else { throw LauncherError.gameSetupFailed("The game data or license files are missing.") }
        try JSONEncoder().encode(Receipt(engine: engineHash, data: dataHash, files: files))
            .write(to: tree.appendingPathComponent(".gggmac-package.json"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: tree, to: target)
        return target.appendingPathComponent("fteqw64.exe")
    }

    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") &&
            !path.contains(where: { $0.isNewline || $0 == "\0" }) &&
            path.split(separator: "/", omittingEmptySubsequences: false).enumerated().allSatisfy { index, part in
                part != "." && part != ".." && (!part.isEmpty || index == path.split(separator: "/", omittingEmptySubsequences: false).count - 1)
            }
    }

    private static func requireRegularPath(_ file: URL, inside root: URL) throws {
        var current = file
        while current.pathComponents.count > root.pathComponents.count {
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, current != file || values.isRegularFile == true else {
                throw LauncherError.gameSetupFailed("A game package file was replaced with a link or an unsupported file type.")
            }
            current.deleteLastPathComponent()
        }
    }

    private static func hashTree(_ root: URL) throws -> [String: String] {
        var folders = [(root, "")], files: [String: String] = [:], bytes = 0
        while let (folder, relative) = folders.popLast() {
            let info = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard info.isSymbolicLink != true, info.isDirectory == true else { throw LauncherError.gameSetupFailed("Unexpected linked game folder.") }
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw LauncherError.gameSetupFailed("Unexpected linked game file.") }
                let path = relative + file.lastPathComponent
                if values.isDirectory == true { folders.append((file, path + "/")) }
                else if values.isRegularFile == true {
                    bytes += values.fileSize ?? 0
                    guard files.count < 100, bytes <= 256 * 1024 * 1024 else { throw LauncherError.gameSetupFailed("The expanded game package is too large.") }
                    files[path] = try RuntimeInstaller.checksum(of: file)
                } else { throw LauncherError.gameSetupFailed("Unsupported game file type.") }
            }
        }
        return files
    }

    private func tar(_ arguments: [String], directory: URL) async throws -> String {
        let log = directory.appendingPathComponent("unpack-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let result = try await ProcessRunner().run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/tar"), arguments: arguments), logURL: log, timeout: .seconds(90))
        guard result.exitCode == 0 else { throw LauncherError.gameSetupFailed("The game ZIP could not be unpacked.") }
        return LogReader.tail(log)
    }
}
