import Foundation
import Testing
@testable import GGGMacCore

private struct GameFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac game flow \(UUID().uuidString)")
    var drive: URL { root.appendingPathComponent("drive_c") }
    init() throws { try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true) }
    func file(_ relative: String, contents: String = "test executable") throws -> URL {
        let url = drive.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func findsInstalledGameWithoutScanningWindowsOrExternalSymlinks() async throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    let game = try fixture.file("Program Files/OpenTTD/openttd.exe")
    _ = try fixture.file("Program Files/OpenTTD/unins000.exe")
    _ = try fixture.file("windows/system32/notepad.exe")
    _ = try fixture.file("Program Files/OpenTTD/README.txt")
    let external = fixture.root.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    try Data().write(to: external.appendingPathComponent("outside.exe"))
    try FileManager.default.createSymbolicLink(at: fixture.drive.appendingPathComponent("Linked Documents"), withDestinationURL: external)
    let scan = try await InstalledExecutableScanner.scan(prefix: fixture.root)
    #expect(scan.executables.count == 2)
    let found = try #require(scan.executables.first(where: { !$0.isUtility }))
    #expect(ExecutableIdentity.matches(found.executable, game))
    #expect(found.relativePath == "Program Files/OpenTTD/openttd.exe")
    #expect(scan.executables.first(where: { $0.isUtility })?.suggestedName == "unins000")
    #expect(!scan.truncated)
}

@Test func scannerDoesNotFollowSymlinkedDrive() async throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    try FileManager.default.removeItem(at: fixture.drive)
    let external = fixture.root.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: fixture.drive, withDestinationURL: external)
    await #expect(throws: LauncherError.self) { try await InstalledExecutableScanner.scan(prefix: fixture.root) }
}

@Test func scannerBoundsLargeLibrariesAndIgnoresExeDirectories() async throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    _ = try fixture.file("Games/one.EXE")
    _ = try fixture.file("Games/two.exe")
    try FileManager.default.createDirectory(at: fixture.drive.appendingPathComponent("Games/folder.exe"), withIntermediateDirectories: true)
    let limited = try await InstalledExecutableScanner.scan(prefix: fixture.root, limit: 1)
    #expect(limited.executables.count == 1)
    #expect(limited.truncated)
    let full = try await InstalledExecutableScanner.scan(prefix: fixture.root)
    #expect(full.executables.count == 2)
}

@Test func detectedGameRegistersPersistsAndBuildsLaunchCommand() async throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    _ = try fixture.file("Program Files/OpenTTD/openttd.exe")
    let wine = fixture.root.appendingPathComponent("wine")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wine)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    try Data().write(to: fixture.root.appendingPathComponent("system.reg"))
    let bottle = Bottle(name: "Game test", runtime: WineRuntime(executable: wine, version: "wine-fixture"))
    var library = Library(); library.bottles = [bottle]
    let entry = try #require(try await InstalledExecutableScanner.scan(prefix: fixture.root).executables.first)
    try library.registerGame(name: "OpenTTD", executable: entry.executable, bottleID: bottle.id, arguments: ["--test argument"])
    let store = LibraryStore(root: fixture.root.appendingPathComponent("Library"))
    try store.save(library)
    let restored = try store.load()
    let game = try #require(restored.games.first)
    let command = try WineCommand.launch(runtime: bottle.runtime, game: game, prefix: fixture.root)
    #expect(command.arguments == [entry.executable.path, "--test argument"])
    #expect(command.environment["WINEPREFIX"] == fixture.root.path)
    #expect(game.name == "OpenTTD")
    #expect(restored.bottles == [bottle])
}

@Test func registrationRejectsDuplicateAliasesButAllowsDifferentEnvironment() throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    let exe = try fixture.file("game.exe")
    let alias = fixture.drive.appendingPathComponent("alias.exe")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: exe)
    let runtime = WineRuntime(executable: fixture.root.appendingPathComponent("wine"), version: "fixture")
    let a = Bottle(name: "A", runtime: runtime), b = Bottle(name: "B", runtime: runtime)
    var library = Library(); library.bottles = [a, b]
    try library.registerGame(name: "Game", executable: exe, bottleID: a.id)
    #expect(throws: LauncherError.self) { try library.registerGame(name: "Alias", executable: alias, bottleID: a.id) }
    try library.registerGame(name: "Other environment", executable: exe, bottleID: b.id)
    #expect(library.games.count == 2)
    let different = try fixture.file("another-game.exe")
    #expect(!ExecutableIdentity.matches(exe, different))
    try FileManager.default.createDirectory(at: fixture.drive.appendingPathComponent("invalid.exe"), withIntermediateDirectories: true)
    #expect(throws: LauncherError.self) {
        try library.registerGame(name: "Directory", executable: fixture.drive.appendingPathComponent("invalid.exe"), bottleID: a.id)
    }
}

@Test func gameInstallerChecksumFailureDoesNotPublishFile() throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    let file = try fixture.file("installer.exe", contents: "abc")
    let destination = fixture.root.appendingPathComponent("Downloads")
    #expect(throws: LauncherError.self) {
        try TestGameDownload.cacheVerifiedInstaller(file, directory: destination, expectedSHA256: String(repeating: "0", count: 64))
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test func verifiedGameInstallerPreservesExistingCachedFile() throws {
    let fixture = try GameFixture(); defer { fixture.clean() }
    let file = try fixture.file("installer.exe", contents: "abc")
    let destination = fixture.root.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let existing = destination.appendingPathComponent(TestGameDownload.url.lastPathComponent)
    try Data("keep existing".utf8).write(to: existing)
    let result = try TestGameDownload.cacheVerifiedInstaller(file, directory: destination,
        expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(result != existing)
    #expect(try String(contentsOf: existing, encoding: .utf8) == "keep existing")
    #expect(try String(contentsOf: result, encoding: .utf8) == "abc")
}
