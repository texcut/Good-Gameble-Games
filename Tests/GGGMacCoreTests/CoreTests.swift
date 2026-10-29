import Foundation
import Testing
@testable import GGGMacCore

private struct Fixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac tests \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String, contents: String = "", executable: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }
}

@Test func libraryRoundTripPreservesRecordsAndArguments() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    #expect(try store.load() == Library())
    var library = Library()
    let bottle = Bottle(name: "GOG / My environment", runtime: WineRuntime(executable: fixture.root.appendingPathComponent("wine"), version: "wine-test"))
    library.bottles = [bottle]
    library.runtime = WineRuntime(executable: fixture.root.appendingPathComponent("wine"), version: "wine-test")
    library.games = [Game(name: "A game", executable: fixture.root.appendingPathComponent("A game.exe"),
                          bottleID: bottle.id, arguments: ["--save path", "$(touch nope)"])]
    try store.save(library)
    #expect(try store.load() == library)
    #expect(store.prefix(for: bottle).lastPathComponent == bottle.id.uuidString)
    #expect(!store.prefix(for: bottle).path.contains("GOG /"))
}

@Test func damagedLibraryIsPreserved() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    let original = Data("this is not JSON".utf8)
    try original.write(to: store.libraryURL)
    #expect(throws: LauncherError.self) { try store.load() }
    #expect(try Data(contentsOf: store.libraryURL) == original)
}

@Test func unsupportedLibraryIsRejected() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    var library = Library(); library.schemaVersion = 6
    try store.save(library)
    #expect(throws: LauncherError.self) { try store.load() }
}

@Test func danglingBottleReferenceIsRejected() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    var library = Library()
    library.games = [Game(name: "Orphan", executable: fixture.root.appendingPathComponent("game.exe"), bottleID: UUID())]
    try store.save(library)
    #expect(throws: LauncherError.self) { try store.load() }
}

@Test func prefixAndWineSettingsDoNotLeakFromParent() {
    let prefix = URL(fileURLWithPath: "/tmp/my isolated prefix")
    let command = WineCommand(executable: URL(fileURLWithPath: "/tmp/runtime/bin/wine"), arguments: ["--version"],
                              prefix: prefix, inheritedEnvironment: ["WINEPREFIX": "/wrong", "WINEARCH": "win32",
                                "WINEDLLOVERRIDES": "bad", "DXVK_CONFIG_FILE": "/wrong", "PATH": "/usr/bin", "HOME": "/home/test"])
    #expect(command.environment["WINEPREFIX"] == prefix.path)
    #expect(command.environment["WINEARCH"] == nil)
    #expect(command.environment["WINEDLLOVERRIDES"] == nil)
    #expect(command.environment["DXVK_CONFIG_FILE"] == nil)
    #expect(command.environment["HOME"] == "/home/test")
    #expect(command.environment["PATH"] == "/tmp/runtime/bin:/usr/bin")
}

@Test func validatesRuntimeAndMissingExecutable() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let wrong = try fixture.file("other", executable: true)
    #expect(throws: LauncherError.self) { try WineCommand.validateRuntime(wrong) }
    let wine = try fixture.file("wine")
    #expect(throws: LauncherError.self) { try WineCommand.validateRuntime(wine) }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    try WineCommand.validateRuntime(wine)
    let game = Game(name: "Missing", executable: fixture.root.appendingPathComponent("missing.exe"), bottleID: UUID())
    #expect(throws: LauncherError.self) {
        try WineCommand.launch(runtime: WineRuntime(executable: wine, version: "test"), game: game, prefix: fixture.root)
    }
}

@Test func launchPreservesSpacesAndRequiresInitializedPrefix() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let wine = try fixture.file("wine", executable: true)
    let exe = try fixture.file("my game.exe")
    let game = Game(name: "Game", executable: exe, bottleID: UUID(), arguments: ["a b", "$(touch bad)", "--flag"])
    let runtime = WineRuntime(executable: wine, version: "test")
    #expect(throws: LauncherError.self) { try WineCommand.launch(runtime: runtime, game: game, prefix: fixture.root) }
    _ = try fixture.file("system.reg")
    try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    let command = try WineCommand.launch(runtime: runtime, game: game, prefix: fixture.root)
    #expect(command.arguments == [exe.path, "a b", "$(touch bad)", "--flag"])
    #expect(command.workingDirectory == exe.deletingLastPathComponent())
}

@Test func processCapturesOutputAndLiteralArguments() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let script = try fixture.file("wine", contents: "#!/bin/sh\nprintf '%s\\n' \"$WINEPREFIX\" \"$1\"\nprintf 'stderr message\\n' >&2\nexit 7\n", executable: true)
    let log = fixture.root.appendingPathComponent("output.log")
    let marker = fixture.root.appendingPathComponent("should-not-exist")
    let literal = "$(touch \(marker.path))"
    let result = try await ProcessRunner().run(WineCommand(executable: script, arguments: [literal], prefix: fixture.root), logURL: log)
    #expect(result.exitCode == 7)
    let output = LogReader.tail(log)
    #expect(output.contains(fixture.root.path))
    #expect(output.contains(literal))
    #expect(output.contains("stderr message"))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func processLaunchFailureReleasesRunner() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let runner = ProcessRunner()
    do {
        _ = try await runner.run(WineCommand(executable: fixture.root.appendingPathComponent("missing"), arguments: []),
                                 logURL: fixture.root.appendingPathComponent("failure.log"))
        Issue.record("Expected process launch failure")
    } catch {}
    let result = try await runner.run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: []),
                                      logURL: fixture.root.appendingPathComponent("success.log"))
    #expect(result.exitCode == 0)
}

@Test func processTimeoutReleasesRunner() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let runner = ProcessRunner()
    do {
        _ = try await runner.run(WineCommand(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"]),
                                 logURL: fixture.root.appendingPathComponent("timeout.log"), timeout: .milliseconds(100))
        Issue.record("Expected timeout")
    } catch let error as LauncherError {
        guard case .commandTimedOut = error else { Issue.record("Wrong launcher error"); return }
    }
    let result = try await runner.run(WineCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: []),
                                      logURL: fixture.root.appendingPathComponent("next.log"))
    #expect(result.exitCode == 0)
}

@Test func logTailIsBoundedAndHandlesMissingFile() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let url = try fixture.file("long.log", contents: String(repeating: "x", count: 100_000) + "the end")
    let tail = LogReader.tail(url, maxBytes: 100)
    #expect(tail.hasPrefix("[Showing the latest log output]"))
    #expect(tail.hasSuffix("the end"))
    #expect(tail.utf8.count < 200)
    #expect(LogReader.tail(fixture.root.appendingPathComponent("missing.log")).isEmpty)
}

@Test func fakeRuntimeInitializesAnIsolatedEnvironment() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let script = try fixture.file("wine", contents: """
    #!/bin/sh
    if [ "$1" = "--version" ]; then printf 'wine-test-runtime\n'; exit 0; fi
    if [ "$1" = "wineboot" ] && [ "$2" = "--init" ]; then
      mkdir -p "$WINEPREFIX/drive_c"
      printf 'test registry\n' > "$WINEPREFIX/system.reg"
      exit 0
    fi
    exit 1
    """, executable: true)
    let store = LibraryStore(root: fixture.root.appendingPathComponent("App Support"))
    let bottle = Bottle(name: "A / B", runtime: WineRuntime(executable: script, version: "wine-test-runtime"))
    let runner = ProcessRunner()
    let result = try await runner.run(WineCommand(executable: script, arguments: ["wineboot", "--init"], prefix: store.prefix(for: bottle)),
                                      logURL: store.logsDirectory.appendingPathComponent("init.log"))
    #expect(result.exitCode == 0)
    #expect(FileManager.default.fileExists(atPath: store.prefix(for: bottle).appendingPathComponent("system.reg").path))
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("system.reg").path))
}

private func legacyData(_ library: Library) throws -> Data {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    json["schemaVersion"] = 1
    json["bottles"] = (json["bottles"] as? [[String: Any]])?.map { bottle in
        bottle.filter { $0.key != "runtime" && $0.key != "lastSmokeTest" }
    }
    return try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
}

@Test func migratesLegacyLibraryAndPreservesBackup() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    let runtimeA = WineRuntime(executable: fixture.root.appendingPathComponent("old/bin/wine"), version: "wine-original")
    let runtimeB = WineRuntime(executable: fixture.root.appendingPathComponent("new/bin/wine"), version: "wine-new")
    var original = Library()
    original.runtime = runtimeA
    let bottle = Bottle(name: "Existing environment", runtime: runtimeA)
    original.bottles = [bottle]
    original.games = [Game(name: "Existing game", executable: fixture.root.appendingPathComponent("game.exe"), bottleID: bottle.id)]
    let data = try legacyData(original)
    try data.write(to: store.libraryURL)
    var migrated = try store.load()
    #expect(migrated.schemaVersion == 5)
    #expect(migrated.bottles == original.bottles)
    #expect(migrated.games == original.games)
    #expect(try Data(contentsOf: store.libraryURL) == data)
    migrated.runtime = runtimeB
    try store.save(migrated)
    let loaded = try store.load()
    #expect(loaded.runtime == runtimeB)
    #expect(loaded.bottles[0].runtime == runtimeA)
    let backup = store.root.appendingPathComponent("library-v1.backup.json")
    #expect(try Data(contentsOf: backup) == data)
    try store.save(loaded)
    #expect(try Data(contentsOf: backup) == data)
}

@Test func legacyEnvironmentsWithoutRuntimeAreRejectedWithoutRewriting() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    var original = Library()
    original.bottles = [Bottle(name: "No assignment", runtime: WineRuntime(executable: fixture.root, version: "unused"))]
    let data = try legacyData(original)
    try data.write(to: store.libraryURL)
    #expect(throws: LauncherError.self) { try store.load() }
    #expect(try Data(contentsOf: store.libraryURL) == data)
}

@Test func emptyLegacyLibraryMigratesWithoutRuntime() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let store = LibraryStore(root: fixture.root)
    try legacyData(Library()).write(to: store.libraryURL)
    #expect(try store.load() == Library())
}

@Test func discoveryDeduplicatesSymlinksAndNeverExecutesCandidates() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let wine = try fixture.file("wine", contents: "#!/bin/sh\ntouch \"$0-ran\"\n", executable: true)
    let alias = fixture.root.appendingPathComponent("wine64")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: wine)
    let location = RuntimeSearchLocation(name: "Test runtime", directory: fixture.root)
    let found = RuntimeDiscovery.discover(in: [location, location])
    #expect(found.count == 1)
    #expect(found.first?.executable == wine)
    #expect(found.first?.name == "Test runtime")
    #expect(!FileManager.default.fileExists(atPath: wine.path + "-ran"))
}

@Test func discoveryRejectsDirectoriesAndNonExecutableFiles() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("wine"), withIntermediateDirectories: true)
    _ = try fixture.file("wine64", executable: false)
    #expect(RuntimeDiscovery.discover(in: [RuntimeSearchLocation(name: "Invalid", directory: fixture.root)]).isEmpty)
}

@Test func smokeTestUsesAssignedRuntimeAndIsolatedPrefix() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let wine = try fixture.file("wine", contents: """
    #!/bin/sh
    printf '%s\n' "$WINEPREFIX" "$1" "$2" "$3" "$4"
    """, executable: true)
    let runtime = WineRuntime(executable: wine, version: "wine-fixture")
    let bottle = Bottle(name: "Isolated", runtime: runtime, lastSmokeTest: Date())
    _ = try fixture.file("system.reg")
    try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    let command = try WineCommand.smokeTest(bottle: bottle, prefix: fixture.root)
    #expect(command.executable == runtime.executable)
    #expect(command.arguments == ["cmd.exe", "/d", "/c", "echo \(WineCommand.smokeMarker) & ver"])
    let result = try await ProcessRunner().run(command, logURL: fixture.root.appendingPathComponent("smoke.log"), timeout: .seconds(5))
    #expect(result.exitCode == 0)
    #expect(LogReader.tail(result.logURL).contains(WineCommand.smokeMarker))
    #expect(LogReader.tail(result.logURL).contains(fixture.root.path))
    var library = Library(); library.bottles = [bottle]
    let store = LibraryStore(root: fixture.root)
    try store.save(library)
    #expect(try store.load().bottles[0].lastSmokeTest == bottle.lastSmokeTest)
}

@Test func smokeTestRejectsUninitializedEnvironment() throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let wine = try fixture.file("wine", executable: true)
    let bottle = Bottle(name: "Incomplete", runtime: WineRuntime(executable: wine, version: "wine-fixture"))
    #expect(throws: LauncherError.self) { try WineCommand.smokeTest(bottle: bottle, prefix: fixture.root) }
}
