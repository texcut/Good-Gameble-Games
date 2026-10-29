import Foundation

/// Read-only preflight for a selected installer or its folder. Data is not moved
/// or renamed. Numbering checks do not replace the installer's integrity check.
public struct InstallerSource: Sendable {
    public let executable: URL
    public let dataFiles: [URL]
    public let dataBytes: Int64

    public static func resolve(_ selection: URL) throws -> InstallerSource {
        let fm = FileManager.default
        let selected = try selection.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if selected.isDirectory != true {
            guard selected.isRegularFile == true, selection.pathExtension.lowercased() == "exe" else {
                throw LauncherError.invalidExecutable
            }
            let name = selection.lastPathComponent.lowercased()
            guard !name.hasPrefix("gog_galaxy_") else { throw InstallerSourceError.galaxyDownloader }
            // A standalone executable does not need access to unrelated siblings.
            if !name.hasPrefix("setup_") {
                return InstallerSource(executable: selection, dataFiles: [], dataBytes: 0)
            }
        }
        let directory = selected.isDirectory == true ? selection : selection.deletingLastPathComponent()
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        } catch {
            if selected.isDirectory != true { throw InstallerSourceError.chooseFolder }
            throw error
        }
        guard files.count <= 10_000 else { throw InstallerSourceError.tooManyFiles }
        let executable: URL
        if selected.isDirectory == true {
            let candidates = try files.filter { file in
                guard file.pathExtension.lowercased() == "exe",
                    file.lastPathComponent.lowercased().hasPrefix("setup_") else { return false }
                return try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            guard candidates.count == 1 else {
                throw candidates.isEmpty ? InstallerSourceError.noInstaller : InstallerSourceError.multipleInstallers
            }
            executable = candidates[0]
        } else {
            executable = selection
        }
        let stem = executable.deletingPathExtension().lastPathComponent.lowercased()
        guard !stem.hasPrefix("gog_galaxy_") else { throw InstallerSourceError.galaxyDownloader }
        var parts: [(Int, URL)] = []
        var bytes: Int64 = 0
        for file in files {
            let name = file.lastPathComponent.lowercased()
            guard name.hasPrefix(stem + "-") else { continue }
            if ["crdownload", "download", "part"].contains(file.pathExtension.lowercased()) {
                throw InstallerSourceError.incompleteDownload(file.lastPathComponent)
            }
            guard name.hasSuffix(".bin") else { continue }
            let number = String(name.dropFirst(stem.count + 1).dropLast(4))
            guard let index = Int(number), index > 0, index <= 10_000 else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
                throw InstallerSourceError.incompleteDownload(file.lastPathComponent)
            }
            parts.append((index, file)); bytes += Int64(size)
        }
        parts.sort { $0.0 < $1.0 }
        if let last = parts.last?.0 {
            guard parts.map(\.0) == Array(1...last) else { throw InstallerSourceError.missingPart }
        }
        return InstallerSource(executable: executable, dataFiles: parts.map(\.1), dataBytes: bytes)
    }
}

public enum InstallerSourceError: LocalizedError, Equatable {
    case noInstaller, multipleInstallers, galaxyDownloader, tooManyFiles, missingPart, chooseFolder, incompleteDownload(String)
    public var errorDescription: String? {
        switch self {
        case .noInstaller: "No setup_*.exe installer was found in this folder. Select the main offline installer .exe directly, or choose the folder containing it."
        case .multipleInstallers: "This folder contains several setup installers. Select the main game's setup .exe directly. Keep its numbered .bin files beside it."
        case .galaxyDownloader: "This is a GOG Galaxy downloader. Download the offline backup game installer and all of its data parts from your GOG library."
        case .tooManyFiles: "Choose the game's installer folder instead of a folder containing thousands of unrelated files."
        case .missingPart: "The numbered installer data parts contain a gap or duplicate. Finish downloading all parts and keep their original filenames together."
        case .chooseFolder: "GGGMac cannot read the files beside this installer. Choose the folder containing the setup .exe and its numbered .bin files to grant access to them together."
        case let .incompleteDownload(name): "An installer part has not finished downloading: \(name). Wait for every download to complete."
        }
    }
}
