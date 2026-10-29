import Foundation

public enum FTEGameSession {
    /// Each run gets a fresh engine log; previous output is preserved beside it.
    public static func prepare(executable: URL) throws -> URL {
        let directory = executable.deletingLastPathComponent().appendingPathComponent("fte")
        let fm = FileManager.default
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw LauncherError.gameSetupFailed("The FTE settings folder is a symbolic link.")
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("qconsole.log")
        if let values = try? log.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw LauncherError.gameSetupFailed("The FTE console log is not a regular file.")
            }
            try fm.moveItem(at: log, to: directory.appendingPathComponent("qconsole-\(UUID().uuidString).log"))
        }
        return log
    }
}
