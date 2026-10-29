import Foundation

public struct WineRuntime: Codable, Equatable, Sendable {
    public var executable: URL
    public var version: String
    public init(executable: URL, version: String) {
        self.executable = executable
        self.version = version
    }
}

public struct Bottle: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var runtime: WineRuntime
    public var lastSmokeTest: Date?
    public var graphicsBackend: GraphicsBackend?
    public var lastGraphicsCheck: GraphicsReport?
    public var d3dMetalOptions: D3DMetalOptions?
    public var activeGraphicsBackend: GraphicsBackend { graphicsBackend ?? .runtimeDefault }
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), runtime: WineRuntime, lastSmokeTest: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.runtime = runtime
        self.lastSmokeTest = lastSmokeTest
    }
}

public struct Game: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var executable: URL
    public var bottleID: UUID
    public var arguments: [String]
    public var lastPlayed: Date?
    public var launchProfile: GameLaunchProfile?
    public var lastRendererReport: GameRendererReport?
    public var lastBenchmark: GameBenchmark?
    public init(id: UUID = UUID(), name: String, executable: URL, bottleID: UUID,
                arguments: [String] = [], lastPlayed: Date? = nil) {
        self.id = id
        self.name = name
        self.executable = executable
        self.bottleID = bottleID
        self.arguments = arguments
        self.lastPlayed = lastPlayed
    }
}

public struct Library: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 5
    public var runtime: WineRuntime?
    public var bottles: [Bottle] = []
    public var games: [Game] = []
    public init() {}

    public mutating func registerGame(name: String, executable: URL, bottleID: UUID, arguments: [String] = []) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LauncherError.emptyName }
        guard bottles.contains(where: { $0.id == bottleID }) else { throw LauncherError.missingBottle }
        var isDirectory: ObjCBool = false
        guard executable.pathExtension.lowercased() == "exe",
              FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LauncherError.invalidExecutable
        }
        guard !games.contains(where: { $0.bottleID == bottleID && ExecutableIdentity.matches($0.executable, executable) }) else {
            throw LauncherError.duplicateGame
        }
        games.append(Game(name: name, executable: executable, bottleID: bottleID, arguments: arguments))
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, runtime, bottles, games }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard (1...5).contains(version) else { throw LauncherError.unsupportedLibrary(version) }
        runtime = try container.decodeIfPresent(WineRuntime.self, forKey: .runtime)
        games = try container.decode([Game].self, forKey: .games)
        if version == 1 {
            struct LegacyBottle: Decodable {
                var id: UUID
                var name: String
                var createdAt: Date
            }
            let legacy = try container.decode([LegacyBottle].self, forKey: .bottles)
            bottles = try legacy.map { bottle in
                guard let runtime else {
                    throw LauncherError.damagedLibrary("The older library has environments but no runtime to assign to them.")
                }
                return Bottle(id: bottle.id, name: bottle.name, createdAt: bottle.createdAt, runtime: runtime)
            }
        } else {
            bottles = try container.decode([Bottle].self, forKey: .bottles)
        }
        schemaVersion = 5
    }
}

public enum LauncherError: LocalizedError, Sendable {
    case invalidRuntime, invalidExecutable, missingBottle, emptyName, alreadyRunning, commandTimedOut, smokeTestFailed, duplicateGame, gameDownloadFailed
    case commandFailed(Int32, String), unsupportedLibrary(Int), damagedLibrary(String), gameSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRuntime: "Choose an executable Wine binary (wine or wine64) from a macOS Wine runtime."
        case .invalidExecutable: "The Windows executable is missing or is not an .exe file. Select it again."
        case .missingBottle: "This environment is missing or was not initialized successfully."
        case .emptyName: "Enter a name before continuing."
        case .alreadyRunning: "Wait for the current operation to finish first."
        case .commandTimedOut: "The Wine command timed out. See Activity for output. Any incomplete environment has been preserved."
        case .smokeTestFailed: "The Windows command did not produce the expected test output. See Activity for details."
        case .duplicateGame: "This executable is already in your library for this environment."
        case .gameDownloadFailed: "The game installer could not be downloaded or did not match the official SHA-256 checksum. It was not run. Try again later."
        case let .gameSetupFailed(detail): "Game setup could not finish. \(detail)"
        case let .commandFailed(code, detail): "Wine exited with code \(code). \(detail)"
        case let .unsupportedLibrary(version): "Library format \(version) is newer than this app supports."
        case let .damagedLibrary(detail): "The library could not be loaded. Your saved file has been preserved. \(detail)"
        }
    }
}
