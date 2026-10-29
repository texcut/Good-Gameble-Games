import Foundation
import Testing
@testable import GGGMacCore

private struct RuntimeFixture {
    let directory: URL
    let archive: URL
    let store: URL
    init(escapingLink: Bool = false, missingWine: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac installer \(UUID().uuidString)")
        archive = directory.appendingPathComponent("runtime.tar.gz")
        store = directory.appendingPathComponent("App Support")
        let bin = directory.appendingPathComponent("Libraries/Wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        if !missingWine {
            let wine = bin.appendingPathComponent("wine")
            try "#!/bin/sh\nprintf 'wine-fixture\\n'\n".write(to: wine, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
            try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("wine64").path, withDestinationPath: "wine")
        }
        if escapingLink {
            try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("Libraries/escape").path,
                                                       withDestinationPath: "/tmp")
        }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", directory.path, "Libraries"]
        try tar.run(); tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw RuntimeInstallError.archive("Could not prepare test archive") }
    }
    func package(checksum: String? = nil) throws -> RuntimePackage {
        RuntimePackage(id: "test-runtime", downloadURL: URL(string: "https://example.invalid/runtime.tar.gz")!,
                       sha256: try checksum ?? RuntimeInstaller.checksum(of: archive),
                       archiveBytes: try (FileManager.default.attributesOfItem(atPath: archive.path)[.size] as! NSNumber).int64Value,
                       executablePath: "Wine/bin/wine")
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Test func runtimeChecksumMatchesKnownSHA256() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("abc".utf8).write(to: url)
    #expect(try RuntimeInstaller.checksum(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func freshWinePrefixIsReadyBeforeRegistryFlush() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let system32 = root.appendingPathComponent("drive_c/windows/system32")
    try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
    #expect(throws: LauncherError.self) { try WineCommand.validatePrefix(root) }
    try Data("test Windows executable".utf8).write(to: system32.appendingPathComponent("cmd.exe"))
    try WineCommand.validatePrefix(root)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("system.reg").path))
}

@Test func runtimeInstallerPublishesVerifiedTreeAndReusesReceipt() async throws {
    let fixture = try RuntimeFixture(); defer { fixture.clean() }
    let package = try fixture.package()
    let installer = RuntimeInstaller(root: fixture.store, package: package)
    let wine = try await installer.installArchive(fixture.archive)
    #expect(wine.path.hasPrefix(fixture.store.path + "/Runtimes/test-runtime/"))
    #expect(RuntimeInstaller.installedExecutable(root: fixture.store, package: package) == wine)
    #expect(FileManager.default.fileExists(atPath: wine.deletingLastPathComponent().appendingPathComponent("wine64").path))
    try FileManager.default.removeItem(at: fixture.archive)
    #expect(try await installer.installArchive(fixture.archive) == wine)
    let contents = try FileManager.default.contentsOfDirectory(atPath: fixture.store.appendingPathComponent("Runtimes").path)
    #expect(contents == ["test-runtime"])
}

@Test func runtimeInstallerRejectsChecksumMismatchBeforeExtraction() async throws {
    let fixture = try RuntimeFixture(); defer { fixture.clean() }
    let package = try fixture.package(checksum: String(repeating: "0", count: 64))
    do {
        _ = try await RuntimeInstaller(root: fixture.store, package: package).installArchive(fixture.archive)
        Issue.record("Expected checksum failure")
    } catch let error as RuntimeInstallError {
        guard case .checksum = error else { Issue.record("Unexpected error: \(error)"); return }
    }
    #expect(!FileManager.default.fileExists(atPath: RuntimeInstaller.directory(root: fixture.store, package: package).path))
}

@Test func runtimeInstallerRejectsEscapingSymlinkAndCleansStaging() async throws {
    let fixture = try RuntimeFixture(escapingLink: true); defer { fixture.clean() }
    let package = try fixture.package()
    do {
        _ = try await RuntimeInstaller(root: fixture.store, package: package).installArchive(fixture.archive)
        Issue.record("Expected archive safety failure")
    } catch let error as RuntimeInstallError {
        guard case .archive = error else { Issue.record("Unexpected error: \(error)"); return }
    }
    let contents = try FileManager.default.contentsOfDirectory(atPath: fixture.store.appendingPathComponent("Runtimes").path)
    #expect(contents.isEmpty)
}

@Test func runtimeInstallerPreservesExistingDestination() async throws {
    let fixture = try RuntimeFixture(); defer { fixture.clean() }
    let package = try fixture.package()
    let destination = RuntimeInstaller.directory(root: fixture.store, package: package)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let marker = destination.appendingPathComponent("keep.txt")
    try Data("preserve".utf8).write(to: marker)
    do {
        _ = try await RuntimeInstaller(root: fixture.store, package: package).installArchive(fixture.archive)
        Issue.record("Expected destination conflict")
    } catch let error as RuntimeInstallError {
        guard case .destinationExists = error else { Issue.record("Unexpected error: \(error)"); return }
    }
    #expect(try String(contentsOf: marker, encoding: .utf8) == "preserve")
}

@Test func runtimeInstallerDoesNotPublishMissingWine() async throws {
    let fixture = try RuntimeFixture(missingWine: true); defer { fixture.clean() }
    let package = try fixture.package()
    await #expect(throws: LauncherError.self) {
        try await RuntimeInstaller(root: fixture.store, package: package).installArchive(fixture.archive)
    }
    #expect(RuntimeInstaller.installedExecutable(root: fixture.store, package: package) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_INTEGRATION_WINE"] != nil || ProcessInfo.processInfo.environment["GGGMAC_INTEGRATION_ARCHIVE"] != nil))
func realWineExecutesWindowsCommandInIsolatedEnvironment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac real Wine \(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(root: root)
    let runner = ProcessRunner()
    let binary: URL
    if let archive = ProcessInfo.processInfo.environment["GGGMAC_INTEGRATION_ARCHIVE"] {
        binary = try await RuntimeInstaller(root: root).installArchive(URL(fileURLWithPath: archive))
    } else {
        let path = try #require(ProcessInfo.processInfo.environment["GGGMAC_INTEGRATION_WINE"])
        binary = URL(fileURLWithPath: path)
    }
    try WineCommand.validateRuntime(binary)
    let versionLog = store.logsDirectory.appendingPathComponent("version.log")
    let version = try await runner.run(WineCommand(executable: binary, arguments: ["--version"]), logURL: versionLog, timeout: .seconds(15))
    #expect(version.exitCode == 0)
    let runtime = WineRuntime(executable: binary, version: LogReader.tail(versionLog).trimmingCharacters(in: .whitespacesAndNewlines))
    let bottle = Bottle(name: "Real Wine integration", runtime: runtime)
    let prefix = store.prefix(for: bottle)
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    func stop() async {
        _ = try? await ProcessRunner().run(WineCommand(executable: binary,
            arguments: ["wineboot", "--end-session", "--force", "--kill"], prefix: prefix),
            logURL: store.logsDirectory.appendingPathComponent("stop.log"), timeout: .seconds(15))
    }
    do {
        let initLog = store.logsDirectory.appendingPathComponent("init.log")
        let initialized = try await runner.run(WineCommand(executable: binary, arguments: ["wineboot", "--init"], prefix: prefix),
            logURL: initLog, timeout: .seconds(180))
        try #require(initialized.exitCode == 0, "\(LogReader.tail(initLog))")
        let command = try WineCommand.smokeTest(bottle: bottle, prefix: prefix)
        let smokeLog = store.logsDirectory.appendingPathComponent("windows.log")
        let result = try await runner.run(command, logURL: smokeLog, timeout: .seconds(30))
        #expect(result.exitCode == 0, "\(LogReader.tail(smokeLog))")
        #expect(LogReader.tail(smokeLog).contains(WineCommand.smokeMarker), "\(LogReader.tail(smokeLog))")
        await stop()
    } catch {
        await stop()
        throw error
    }
}
