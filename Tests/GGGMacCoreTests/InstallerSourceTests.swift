import Foundation
import Testing
@testable import GGGMacCore

private struct InstallerFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac installer \(UUID().uuidString)")
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func file(_ name: String, bytes: Int = 3) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 42, count: bytes).write(to: url)
        return url
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func installerFolderResolvesNumberedPartsInNumericOrderWithoutChangingFiles() throws {
    let fixture = try InstallerFixture(); defer { fixture.clean() }
    let executable = try fixture.file("setup_witcher.exe")
    for index in 1...23 { _ = try fixture.file("setup_witcher-\(index).bin", bytes: index) }
    _ = try fixture.file("unrelated-1.bin", bytes: 99)
    _ = try fixture.file("setup_witcher-readme.txt")
    let source = try InstallerSource.resolve(fixture.root)
    #expect(ExecutableIdentity.matches(source.executable, executable))
    #expect(source.dataFiles.map(\.lastPathComponent) == (1...23).map { "setup_witcher-\($0).bin" })
    #expect(source.dataBytes == 276)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).count == 26)
    #expect(try Data(contentsOf: executable) == Data(repeating: 42, count: 3))
    #expect(try InstallerSource.resolve(executable).dataFiles == source.dataFiles)
}

@Test func installerPreflightRejectsGapsDuplicatesEmptyAndUnfinishedParts() throws {
    let cases: [(String, Int, InstallerSourceError)] = [
        ("setup_game-3.bin", 3, .missingPart),
        ("setup_game-01.bin", 3, .missingPart),
        ("setup_game-2.bin", 0, .incompleteDownload("setup_game-2.bin")),
        ("setup_game-2.bin.crdownload", 3, .incompleteDownload("setup_game-2.bin.crdownload"))
    ]
    for (name, bytes, expected) in cases {
        let fixture = try InstallerFixture(); defer { fixture.clean() }
        _ = try fixture.file("setup_game.exe")
        _ = try fixture.file("setup_game-1.bin")
        _ = try fixture.file(name, bytes: bytes)
        #expect(throws: expected) { try InstallerSource.resolve(fixture.root) }
    }
}

@Test func installerFolderRequiresAnUnambiguousSetupButAllowsExplicitSelection() throws {
    let fixture = try InstallerFixture(); defer { fixture.clean() }
    #expect(throws: InstallerSourceError.noInstaller) { try InstallerSource.resolve(fixture.root) }
    let main = try fixture.file("setup_game.exe")
    _ = try fixture.file("setup_patch.exe")
    #expect(throws: InstallerSourceError.multipleInstallers) { try InstallerSource.resolve(fixture.root) }
    #expect(try InstallerSource.resolve(main).executable == main)
}

@Test func standaloneInstallerDoesNotPreflightUnrelatedFilesAndGalaxyDownloaderIsRejected() throws {
    let fixture = try InstallerFixture(); defer { fixture.clean() }
    let standalone = try fixture.file("openttd-installer.exe")
    _ = try fixture.file("openttd-installer-1.bin.crdownload")
    #expect(try InstallerSource.resolve(standalone).dataFiles.isEmpty)
    let galaxy = try fixture.file("GOG_Galaxy_The_Witcher_3.exe")
    #expect(throws: InstallerSourceError.galaxyDownloader) { try InstallerSource.resolve(galaxy) }
    let wrong = try fixture.file("readme.txt")
    #expect(throws: LauncherError.self) { try InstallerSource.resolve(wrong) }
}
