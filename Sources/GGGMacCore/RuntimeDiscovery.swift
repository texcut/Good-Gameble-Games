import Foundation

public struct RuntimeSearchLocation: Sendable {
    public var name: String
    public var directory: URL
    public init(name: String, directory: URL) { self.name = name; self.directory = directory }
}

public struct RuntimeCandidate: Identifiable, Equatable, Sendable {
    public var id: String { executable.path }
    public let name: String
    public let executable: URL
}

public enum RuntimeDiscovery {
    /// Filesystem discovery only: detected programs are never executed until selected.
    public static func discover(in locations: [RuntimeSearchLocation]) -> [RuntimeCandidate] {
        var seen = Set<String>()
        var candidates: [RuntimeCandidate] = []
        for location in locations {
            for name in ["wine", "wine64"] {
                let executable = location.directory.appendingPathComponent(name)
                guard (try? WineCommand.validateRuntime(executable)) != nil else { continue }
                let identity = executable.resolvingSymlinksInPath().path
                guard seen.insert(identity).inserted else { continue }
                candidates.append(RuntimeCandidate(name: location.name, executable: executable))
            }
        }
        return candidates
    }

    public static var standardLocations: [RuntimeSearchLocation] {
        var result = [
            RuntimeSearchLocation(name: "Homebrew", directory: URL(fileURLWithPath: "/opt/homebrew/bin")),
            RuntimeSearchLocation(name: "Local installation", directory: URL(fileURLWithPath: "/usr/local/bin"))
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
        for appDirectory in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for name in ["Wine Stable", "Wine Devel", "Wine Staging"] {
                result.append(RuntimeSearchLocation(name: name,
                    directory: appDirectory.appendingPathComponent("\(name).app/Contents/Resources/wine/bin")))
            }
        }
        return result
    }
}
