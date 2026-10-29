import Foundation

public struct InstalledExecutable: Identifiable, Equatable, Sendable {
    public var id: String { executable.path }
    public let executable: URL
    public let relativePath: String
    public let suggestedName: String
    public let isUtility: Bool
    public init(executable: URL, relativePath: String, suggestedName: String, isUtility: Bool) {
        self.executable = executable
        self.relativePath = relativePath
        self.suggestedName = suggestedName
        self.isUtility = isUtility
    }
}

public struct ExecutableScan: Sendable {
    public var executables: [InstalledExecutable] = []
    public var unreadableFolders = 0
    public var truncated = false
}

public enum InstalledExecutableScanner {
    public static func scan(prefix: URL, limit: Int = 2000, entryLimit: Int = 100_000) async throws -> ExecutableScan {
        let work = Task.detached(priority: .userInitiated) { try scanFiles(prefix: prefix, limit: limit, entryLimit: entryLimit) }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }

    private static func scanFiles(prefix: URL, limit: Int, entryLimit: Int) throws -> ExecutableScan {
        let manager = FileManager.default
        let prefix = prefix.resolvingSymlinksInPath()
        let drive = prefix.appendingPathComponent("drive_c")
        let values = try drive.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LauncherError.missingBottle }
        var result = ExecutableScan()
        var directories: [(URL, String, Int)] = [(drive, "", 0)]
        var visited = 0
        while let (directory, relativeDirectory, depth) = directories.popLast() {
            try Task.checkCancellation()
            let children: [URL]
            do {
                children = try manager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            } catch { result.unreadableFolders += 1; continue }
            for url in children.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                visited += 1
                guard visited <= entryLimit, result.executables.count < limit else { result.truncated = true; return sorted(result) }
                guard let properties = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                      properties.isSymbolicLink != true else { continue }
                let relative = relativeDirectory.isEmpty ? url.lastPathComponent : relativeDirectory + "/" + url.lastPathComponent
                if properties.isDirectory == true {
                    if depth == 0, ["windows", "$recycle.bin", "system volume information"].contains(url.lastPathComponent.lowercased()) { continue }
                    if depth < 32 { directories.append((url, relative, depth + 1)) }
                    else { result.truncated = true }
                } else if properties.isRegularFile == true, url.pathExtension.lowercased() == "exe" {
                    let name = url.deletingPathExtension().lastPathComponent
                    let lower = name.lowercased()
                    let utility = ["unins", "uninstall", "setup", "install", "crash", "vc_redist", "vcredist", "dxsetup", "updater", "unitycrash", "steamwebhelper", "easyanticheat"].contains { lower.hasPrefix($0) }
                    result.executables.append(InstalledExecutable(executable: url,
                        relativePath: relative, suggestedName: name, isUtility: utility))
                }
            }
        }
        return sorted(result)
    }

    private static func sorted(_ result: ExecutableScan) -> ExecutableScan {
        var result = result
        result.executables.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return result
    }
}
