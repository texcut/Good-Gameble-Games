import Foundation

public struct LibraryStore: Sendable {
    public let root: URL
    public var libraryURL: URL { root.appendingPathComponent("library.json") }
    public var logsDirectory: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public init(root: URL) { self.root = root }
    public static var standard: LibraryStore {
        LibraryStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GGGMac", isDirectory: true))
    }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
    public func prefix(for bottle: Bottle) -> URL {
        root.appendingPathComponent("Bottles", isDirectory: true)
            .appendingPathComponent(bottle.id.uuidString, isDirectory: true)
    }
    public func load() throws -> Library {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return Library() }
        do {
            let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL))
            guard Set(library.bottles.map(\.id)).count == library.bottles.count,
                  Set(library.games.map(\.id)).count == library.games.count,
                  library.games.allSatisfy({ game in library.bottles.contains { $0.id == game.bottleID } }) else {
                throw LauncherError.damagedLibrary("Duplicate records or missing environment references.")
            }
            return library
        } catch let error as LauncherError { throw error }
        catch { throw LauncherError.damagedLibrary(error.localizedDescription) }
    }
    public func save(_ library: Library) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        // Preserve the original library before the first save in a new format.
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let original = try Data(contentsOf: libraryURL)
            if let json = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
               let version = json["schemaVersion"] as? Int, version < library.schemaVersion, (1...4).contains(version) {
                let backup = root.appendingPathComponent("library-v\(version).backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
            }
        }
        try data.write(to: libraryURL, options: .atomic)
    }
}
