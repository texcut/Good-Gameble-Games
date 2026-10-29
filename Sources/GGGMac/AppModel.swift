import AppKit
import GGGMacCore
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    let store: LibraryStore
    var library = Library()
    var busy = false
    var operation = ""
    var activeGameID: UUID?
    var activePrefix: URL?
    var activeRuntime: WineRuntime?
    var discoveredRuntimes: [RuntimeCandidate] = []
    var lastRuntimeScan: Date?
    var runtimeScanCount = 0
    var runtimeInstallStage: String?
    var runtimeInstallInProgress = false
    var testGameDownloadInProgress = false
    var installedGamesBottle: Bottle?
    var graphicsBottle: Bottle?
    var logURL: URL?
    var logText = ""
    var notice = "Welcome. Set up a Wine runtime to get started."
    var error: String?
    var loadFailed = false
    var stopping = false
    private let runner = ProcessRunner()
    private var logTask: Task<Void, Never>?
    private var runtimeInstallTask: Task<Void, Never>?
    private var testGameInstallTask: Task<Void, Never>?
    var activeRendererReport: GameRendererReport?
    private var engineLogURL: URL?

    init(store: LibraryStore = .standard) {
        self.store = store
        do {
            library = try store.load()
            if library.runtime != nil { notice = "Ready when you are." }
        } catch { self.error = error.localizedDescription; loadFailed = true }
        refreshRuntimes(announce: false)
        if !loadFailed, let prepared = try? PreparedD3DMetalGame.load(root: store.root), !prepared.isConnected(in: library) {
            Task { await connectPreparedD3DMetal() }
        }
    }

    private func connectPreparedD3DMetal() async {
        guard !busy, !loadFailed else { return }
        begin("Connecting D3DMetal environment")
        defer { finish() }
        do {
            let prepared = try PreparedD3DMetalGame.load(root: store.root)
            if prepared.isConnected(in: library) { return }
            let snapshot = library, root = store.root
            let updated = try await Task.detached {
                try prepared.connecting(to: snapshot, root: root)
            }.value
            let backup = root.appendingPathComponent("library-before-d3dmetal.backup.json")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try Data(contentsOf: store.libraryURL).write(to: backup, options: .atomic)
            }
            try commit(updated)
            notice = "Graphics environment connected. Launch the game from Library."
        } catch { self.error = error.localizedDescription }
    }

    func commit(_ updated: Library) throws {
        guard !loadFailed else { throw LauncherError.damagedLibrary("Reopen the app after restoring library.json.") }
        try store.save(updated)
        library = updated
    }

    func refreshRuntimes(announce: Bool = true) {
        discoveredRuntimes = RuntimeDiscovery.discover(in: runtimeSearchLocations)
        lastRuntimeScan = Date()
        runtimeScanCount += 1
        if announce {
            notice = discoveredRuntimes.isEmpty
                ? "Scan complete: no Wine runtime found. Scanning does not install Wine."
                : "Scan complete: found \(discoveredRuntimes.count) Wine runtime\(discoveredRuntimes.count == 1 ? "" : "s")."
        }
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    var runtimeSearchLocations: [RuntimeSearchLocation] {
        [RuntimeSearchLocation(name: "Good Gameble Games managed Wine", directory:
            RuntimeInstaller.directory(root: store.root).appendingPathComponent("Wine/bin"))] + RuntimeDiscovery.standardLocations
    }

    var hasManagedRuntime: Bool { RuntimeInstaller.installedExecutable(root: store.root) != nil }

    func startRuntimeInstall() {
        guard !busy, !loadFailed, runtimeInstallTask == nil else { return }
        runtimeInstallTask = Task { await installManagedRuntime() }
    }

    func cancelRuntimeInstall() {
        runtimeInstallStage = "Cancelling runtime setup…"
        runtimeInstallTask?.cancel()
    }

    private func installManagedRuntime() async {
        begin("Setting up Wine runtime")
        runtimeInstallInProgress = true
        runtimeInstallStage = "Preparing Wine runtime setup…"
        var installed: URL?
        do {
            installed = try await RuntimeInstaller(root: store.root).downloadAndInstall { [weak self] stage in
                self?.runtimeInstallStage = stage
            }
            try Task.checkCancellation()
            refreshRuntimes(announce: false)
        } catch {
            installed = nil
            if Task.isCancelled { notice = "Runtime setup cancelled. Existing environments were not changed." }
            else { self.error = error.localizedDescription }
        }
        runtimeInstallStage = nil
        runtimeInstallInProgress = false
        finish()
        if let installed, !Task.isCancelled { await connectRuntime(installed) }
        runtimeInstallTask = nil
    }

    func pickRuntime(for bottle: Bottle? = nil) {
        guard !busy, !loadFailed else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Wine executable"
        panel.message = bottle.map {
            "Choose Wine for \($0.name). Changing versions can update this environment’s files. Back up its folder first."
        } ?? "Choose wine or wine64 in the bin folder of a trusted macOS Wine runtime."
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await connectRuntime(url, bottleID: bottle?.id) }
    }

    func connectRuntime(_ url: URL, bottleID: UUID? = nil) async {
        guard !busy else { return }
        begin("Checking Wine runtime")
        defer { finish() }
        do {
            try WineCommand.validateRuntime(url)
            let result = try await runner.run(WineCommand(executable: url, arguments: ["--version"]), logURL: newLog("runtime"), timeout: .seconds(15))
            let version = LogReader.tail(result.logURL).trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.exitCode == 0, version.lowercased().contains("wine") else {
                throw LauncherError.commandFailed(result.exitCode, "The selected binary did not report a Wine version.")
            }
            var updated = library
            let runtime = WineRuntime(executable: url, version: String(version.prefix(300)))
            if let bottleID {
                guard let index = updated.bottles.firstIndex(where: { $0.id == bottleID }) else { throw LauncherError.missingBottle }
                guard updated.bottles[index].activeGraphicsBackend == .runtimeDefault else { throw GraphicsError.restoreFirst }
                if updated.bottles[index].runtime != runtime {
                    updated.bottles[index].runtime = runtime
                    updated.bottles[index].lastSmokeTest = nil
                    updated.bottles[index].lastGraphicsCheck = nil
                }
            } else {
                updated.runtime = runtime
            }
            try commit(updated)
            notice = bottleID != nil ? "Environment runtime updated." :
                "Default Wine runtime connected. Existing environments keep their assigned runtime."
        } catch { self.error = error.localizedDescription }
    }

    func createBottle(name: String) async -> Bool {
        guard !busy, let runtime = library.runtime else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = LauncherError.emptyName.localizedDescription; return false }
        begin("Creating \(name)")
        defer { finish() }
        let bottle = Bottle(name: name, runtime: runtime)
        let prefix = store.prefix(for: bottle)
        do {
            try WineCommand.validateRuntime(runtime.executable)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            activePrefix = prefix
            activeRuntime = runtime
            let result = try await runner.run(WineCommand(executable: runtime.executable,
                arguments: ["wineboot", "--init"], prefix: prefix), logURL: newLog("create-environment"), timeout: .seconds(180))
            if stopping { notice = "Environment setup stopped. Incomplete files are preserved."; return false }
            guard result.exitCode == 0 else {
                throw LauncherError.commandFailed(result.exitCode, "See Activity for setup output. The incomplete environment is preserved on disk.")
            }
            try WineCommand.validatePrefix(prefix)
            var updated = library
            updated.bottles.append(bottle)
            try commit(updated)
            notice = "\(name) is ready. Add a Windows executable or run an installer."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func prepareDirect3D12Test() async {
        guard let bottle = await direct3D12Bottle() else { return }
        graphicsBottle = bottle
        await checkGraphics(bottleID: bottle.id)
    }

    private func direct3D12Bottle() async -> Bottle? {
        guard !busy, !loadFailed, let runtime = library.runtime else { return nil }
        let base = "Direct3D 12 test"
        var bottle = library.bottles.first {
            ($0.name == base || $0.name.hasPrefix(base + " ")) && $0.runtime == runtime && $0.activeGraphicsBackend == .runtimeDefault
        }
        if bottle == nil {
            let oldIDs = Set(library.bottles.map(\.id))
            let names = Set(library.bottles.map(\.name))
            var name = base, number = 2
            while names.contains(name) { name = "\(base) \(number)"; number += 1 }
            guard await createBottle(name: name) else { return nil }
            bottle = library.bottles.first { !oldIDs.contains($0.id) }
        }
        return bottle
    }

    func pickEXE() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows executable"
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func addGame(name: String, executable: URL, bottleID: UUID, arguments: [String]) -> Bool {
        do {
            var updated = library
            try updated.registerGame(name: name, executable: executable, bottleID: bottleID, arguments: arguments)
            try commit(updated)
            notice = "\(name) added to your library."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func removeGame(_ game: Game) {
        do {
            var updated = library
            updated.games.removeAll { $0.id == game.id }
            try commit(updated)
        } catch { self.error = error.localizedDescription }
    }

    func saveD3DMetalOptions(_ options: D3DMetalOptions, bottleID: UUID, gameID: UUID) async -> Bool {
        guard !busy, !loadFailed, let bottle = library.bottles.first(where: { $0.id == bottleID }),
              D3DMetalRuntime.isManaged(bottle.runtime.executable) else { return false }
        begin("Applying graphics and performance settings")
        defer { finish() }
        do {
            guard bottle.activeGraphicsBackend == .runtimeDefault else { throw GraphicsError.restoreFirst }
            if options.backend == .metal4,
               !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) {
                throw LauncherError.gameSetupFailed("The Metal 4 backend requires macOS 27 or later. Choose Automatic or Metal 3.")
            }
            let runtime = bottle.runtime
            guard let game = library.games.first(where: { $0.id == gameID && $0.bottleID == bottleID }) else {
                throw LauncherError.invalidExecutable
            }
            try await Task.detached { try D3DMetalRuntime.validate(executable: runtime.executable) }.value
            let previous = bottle.d3dMetalOptions ?? D3DMetalOptions()
            if previous.msyncEnabled != options.msyncEnabled || previous.metalFXEnabled != options.metalFXEnabled ||
                (options.metalFXEnabled && WitcherMetalFXPatch.isCandidate(game.executable)) {
                // Stop this prefix before changing synchronization or preparing
                // its compatibility copy. The Save button names this restart.
                try await WineServer.stop(runtime: runtime, prefix: store.prefix(for: bottle),
                                          logURL: newLog("sync-restart"), runner: runner)
            }
            if options.metalFXEnabled {
                let prefix = store.prefix(for: bottle)
                try await Task.detached {
                    try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: options)
                }.value
            }
            var updated = library
            guard let index = updated.bottles.firstIndex(where: { $0.id == bottleID }) else { throw LauncherError.missingBottle }
            updated.bottles[index].d3dMetalOptions = options
            updated.bottles[index].lastGraphicsCheck = nil
            try commit(updated)
            notice = "Settings saved: \(options.summary). Launch the game to apply them."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult
    func launch(_ game: Game, benchmark: Bool = false) async -> Bool {
        guard !busy, !loadFailed, let bottle = library.bottles.first(where: { $0.id == game.bottleID }) else { return false }
        guard !benchmark || game.launchProfile == .fteDirect3D11 else { return false }
        let runtime = bottle.runtime
        begin(benchmark ? "Benchmarking LibreQuake at 720p…" : "Running \(game.name)")
        activeRendererReport = nil
        activeGameID = game.id
        activePrefix = store.prefix(for: bottle)
        activeRuntime = runtime
        defer { finish() }
        do {
            try await GraphicsBackendManager(prefix: store.prefix(for: bottle)).verifySelection(bottle.activeGraphicsBackend)
            if D3DMetalRuntime.isManaged(runtime.executable) {
                guard bottle.activeGraphicsBackend == .runtimeDefault else { throw GraphicsError.restoreFirst }
                let prefix = store.prefix(for: bottle), options = bottle.d3dMetalOptions ?? D3DMetalOptions()
                try await Task.detached {
                    try D3DMetalRuntime.validate(executable: runtime.executable)
                    try MetalFXGameSetup.prepare(runtime: runtime, game: game, prefix: prefix, options: options)
                }.value
            }
            var launchGame = game
            if game.launchProfile == .fteDirect3D11 {
                launchGame.arguments = GameLaunchProfile.libreQuakeArguments + (benchmark ? GameLaunchProfile.libreQuakeBenchmarkArguments : [])
                engineLogURL = try FTEGameSession.prepare(executable: game.executable)
            }
            let command = try WineCommand.launch(runtime: runtime, game: launchGame, prefix: store.prefix(for: bottle), graphics: bottle.activeGraphicsBackend,
                d3dMetalOptions: bottle.d3dMetalOptions)
            if game.launchProfile == .sdlDirect3D11 {
                try await SopwithCompatibility.prepare(runtime: runtime, prefix: store.prefix(for: bottle), logDirectory: store.logsDirectory)
            }
            let launchLog = newLog(benchmark ? "benchmark" : "launch")
            if D3DMetalRuntime.isManaged(runtime.executable) {
                let keys: Set<String> = ["D3DM_SUPPORT_DXR", "ROSETTA_ADVERTISE_AVX", "WINEMSYNC", "D3DM_MTL4", "MTL_HUD_ENABLED",
                                         "D3DM_ENABLE_METALFX", "WINEDLLOVERRIDES"]
                try JSONEncoder().encode(command.environment.filter { keys.contains($0.key) })
                    .write(to: launchLog.deletingPathExtension().appendingPathExtension("environment.json"), options: .atomic)
            }
            let result = try await runner.run(command, logURL: launchLog, timeout: benchmark ? .seconds(180) : nil)
            let output = latestOutput()
            let renderer = GameRendererReport.parse(output, profile: game.launchProfile) ?? activeRendererReport
            let expectedExit = game.launchProfile?.expectsExitCode(result.exitCode, output: output) ?? (result.exitCode == 0)
            let measurement = benchmark && !stopping && expectedExit && renderer?.usesDirect3D11 == true
                ? GameBenchmark.parse(output, runtimeVersion: runtime.version) : nil
            if let engineLogURL {
                try? Data(LogReader.tail(engineLogURL).utf8).write(to: result.logURL.deletingPathExtension().appendingPathExtension("engine.log"), options: .atomic)
            }
            var updated = library
            if let index = updated.games.firstIndex(where: { $0.id == game.id }) {
                updated.games[index].lastPlayed = Date()
                if game.launchProfile != nil { updated.games[index].lastRendererReport = renderer }
                if let measurement { updated.games[index].lastBenchmark = measurement }
            }
            try commit(updated)
            if !expectedExit && !stopping {
                throw LauncherError.commandFailed(result.exitCode, "Open Activity to inspect the log.")
            }
            notice = stopping ? "Environment stopped." : "\(game.name) exited (code \(result.exitCode))."
            if game.launchProfile != nil, !stopping {
                notice += renderer.map { " Renderer: \($0.renderer)." } ?? " Renderer could not be confirmed; see Activity."
            }
            if benchmark && !stopping {
                notice = measurement.map { "LibreQuake timedemo: \(String(format: "%.1f", $0.framesPerSecond)) FPS · 720p preset · DXMT." }
                    ?? "Benchmark did not produce a verified Direct3D 11 result. See Activity."
            }
            return !stopping
        } catch { self.error = error.localizedDescription; return false }
    }

    func runInstaller(in bottle: Bottle) {
        chooseInstaller(in: bottle)
    }

    func installIntoDirect3D12Environment() { chooseInstaller(in: nil) }

    private func chooseInstaller(in selectedBottle: Bottle?) {
        guard !busy, !loadFailed else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows installer or its folder"
        panel.message = "For a multipart GOG installer, select its folder so all numbered .bin files are accessible. You will complete the installer’s license and installation steps."
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selection = panel.url else { return }
        let accessed = selection.startAccessingSecurityScopedResource()
        Task {
            defer { if accessed { selection.stopAccessingSecurityScopedResource() } }
            guard !busy, !loadFailed else { return }
            do {
                let source = try InstallerSource.resolve(selection)
                let bottle: Bottle
                if let selectedBottle { bottle = selectedBottle }
                else {
                    guard let prepared = await direct3D12Bottle() else { return }
                    bottle = prepared
                }
                let size = ByteCountFormatter.string(fromByteCount: source.dataBytes, countStyle: .file)
                notice = source.dataFiles.isEmpty ? "Installer selected. It will check any required game data." :
                    "Found \(source.dataFiles.count) numbered data parts (\(size)), with no numbering gaps. The installer checks completeness and integrity."
                let installer = Game(name: source.executable.deletingPathExtension().lastPathComponent,
                    executable: source.executable, bottleID: bottle.id)
                if await launch(installer) { installedGamesBottle = bottle }
            } catch { self.error = error.localizedDescription }
        }
    }

    func startTestGameInstall(in bottle: Bottle) {
        guard !busy, !loadFailed, testGameInstallTask == nil else { return }
        testGameInstallTask = Task {
            begin("Downloading OpenTTD Windows installer…")
            testGameDownloadInProgress = true
            var executable: URL?
            do {
                executable = try await TestGameDownload.download(root: store.root)
                try Task.checkCancellation()
            } catch {
                executable = nil
                if Task.isCancelled { notice = "Game download cancelled." }
                else { self.error = error.localizedDescription }
            }
            testGameDownloadInProgress = false
            finish()
            if let executable, !Task.isCancelled {
                let installer = Game(name: "OpenTTD installer", executable: executable, bottleID: bottle.id)
                if await launch(installer) { installedGamesBottle = bottle }
            }
            testGameInstallTask = nil
        }
    }

    func cancelTestGameDownload() { testGameInstallTask?.cancel() }

    func startDirect3DGameInstall(in bottle: Bottle, threeD: Bool = false) {
        guard !busy, !loadFailed, testGameInstallTask == nil else { return }
        testGameInstallTask = Task {
            let name = threeD ? "LibreQuake" : "SDL Sopwith"
            begin("Downloading and setting up \(name)…")
            testGameDownloadInProgress = true
            defer { testGameDownloadInProgress = false; testGameInstallTask = nil; finish() }
            do {
                guard bottle.activeGraphicsBackend == .dxmt else {
                    throw LauncherError.gameSetupFailed("Choose DXMT in this environment’s Windows graphics settings first.")
                }
                try await GraphicsBackendManager(prefix: store.prefix(for: bottle)).verifySelection(.dxmt)
                let executable: URL
                if threeD { executable = try await ThreeDTestGame().install(root: store.root, prefix: store.prefix(for: bottle)) }
                else {
                    executable = try await PortableTestGame().install(root: store.root, prefix: store.prefix(for: bottle))
                    try await SopwithCompatibility.prepare(runtime: bottle.runtime, prefix: store.prefix(for: bottle), logDirectory: store.logsDirectory)
                }
                try Task.checkCancellation()
                var updated = library
                if !updated.games.contains(where: { $0.bottleID == bottle.id && ExecutableIdentity.matches($0.executable, executable) }) {
                    try updated.registerGame(name: name, executable: executable, bottleID: bottle.id,
                        arguments: threeD ? GameLaunchProfile.libreQuakeArguments : [])
                }
                if let index = updated.games.firstIndex(where: { $0.bottleID == bottle.id && ExecutableIdentity.matches($0.executable, executable) }) {
                    updated.games[index].launchProfile = threeD ? .fteDirect3D11 : .sdlDirect3D11
                }
                try commit(updated)
                notice = "\(name) added to your library."
            } catch {
                if Task.isCancelled { notice = "Game setup cancelled." }
                else { self.error = error.localizedDescription }
            }
        }
    }

    func applyGraphics(_ backend: GraphicsBackend, bottleID: UUID) async {
        guard !busy, !loadFailed, let bottle = library.bottles.first(where: { $0.id == bottleID }) else { return }
        begin("Applying graphics configuration")
        defer { finish() }
        let manager = GraphicsBackendManager(prefix: store.prefix(for: bottle))
        var deployed = false
        do {
            if backend == .dxmt {
                guard let payload = GraphicsBackendManager.payload(for: bottle.runtime) else { throw GraphicsError.unavailable }
                deployed = try await manager.enableDXMT(payload: payload)
            } else { try await manager.restore() }
            var updated = library
            guard let index = updated.bottles.firstIndex(where: { $0.id == bottleID }) else { throw LauncherError.missingBottle }
            updated.bottles[index].graphicsBackend = backend == .runtimeDefault ? nil : backend
            updated.bottles[index].lastGraphicsCheck = nil
            try commit(updated)
            notice = "\(bottle.name): \(backend.title) selected. Run Check graphics to validate it."
        } catch {
            let original = error.localizedDescription
            if deployed {
                do { try await manager.restore() }
                catch { self.error = original + " Restore also failed: " + error.localizedDescription; return }
            }
            self.error = original
        }
    }

    func checkGraphics(bottleID: UUID, includePresentation: Bool = false) async {
        guard !busy, !loadFailed, let bottle = library.bottles.first(where: { $0.id == bottleID }) else { return }
        begin("Checking Windows graphics")
        activePrefix = store.prefix(for: bottle)
        activeRuntime = bottle.runtime
        defer { finish() }
        do {
            let report = try await GraphicsProbe.run(bottle: bottle, prefix: store.prefix(for: bottle), logDirectory: store.logsDirectory, includePresentation: includePresentation,
                progress: { [weak self] api, log in
                    self?.operation = switch api {
                    case "opengl": "Checking Windows OpenGL 3.2"
                    case "d3d12": "Checking Direct3D 12 SM 5.0 shaders and readback"
                    case "d3d12-dxil": "Executing Direct3D 12 SM 6.0/DXIL shaders"
                    case "d3d12-present": "Checking 60 Direct3D 12 DXIL window frames"
                    default: "Checking Direct3D 11 hardware readback"
                    }
                    self?.followLog(log)
                }, shouldContinue: { [weak self] in self?.stopping == false })
            if stopping { notice = "Graphics check stopped."; return }
            var updated = library
            guard let index = updated.bottles.firstIndex(where: { $0.id == bottleID }) else { throw LauncherError.missingBottle }
            updated.bottles[index].lastGraphicsCheck = report
            try commit(updated)
            notice = "Graphics check finished. OpenGL 3.2: \(report.openGL.passed ? "passed" : "unavailable"). Direct3D 11: \(report.direct3D.passed ? "passed" : "unavailable"). Direct3D 12: \(report.direct3D12?.passed == true ? "passed" : "not passed")."
            notice += " DXIL: \(report.direct3D12DXIL?.hasVerifiedPass == true ? "passed" : "not passed")."
            if includePresentation { notice += " Window: \(report.direct3D12Presentation?.hasVerifiedPass == true ? "passed" : "not passed")." }
        } catch is CancellationError { notice = "Graphics check stopped." }
        catch { self.error = error.localizedDescription }
    }

    func testEnvironment(_ bottle: Bottle) async {
        guard !busy, !loadFailed else { return }
        begin("Checking \(bottle.name)")
        activePrefix = store.prefix(for: bottle)
        activeRuntime = bottle.runtime
        defer { finish() }
        do {
            let command = try WineCommand.smokeTest(bottle: bottle, prefix: store.prefix(for: bottle))
            let result = try await runner.run(command, logURL: newLog("windows-smoke-test"), timeout: .seconds(30))
            if stopping { notice = "Environment check stopped."; return }
            guard result.exitCode == 0 else {
                throw LauncherError.commandFailed(result.exitCode, "Wine could not complete the environment check. See Activity for details.")
            }
            guard LogReader.tail(result.logURL).contains(WineCommand.smokeMarker) else {
                throw LauncherError.smokeTestFailed
            }
            var updated = library
            guard let index = updated.bottles.firstIndex(where: { $0.id == bottle.id }) else { throw LauncherError.missingBottle }
            updated.bottles[index].lastSmokeTest = Date()
            try commit(updated)
            notice = "\(bottle.name): Wine is responding."
        } catch { self.error = error.localizedDescription }
    }

    func stopEnvironment() async {
        guard !stopping, let prefix = activePrefix, let runtime = activeRuntime else { return }
        stopping = true
        do {
            let stopper = ProcessRunner()
            let options = library.bottles.first(where: { store.prefix(for: $0).path == prefix.path })?.d3dMetalOptions
            let result = try await stopper.run(WineCommand(executable: runtime.executable,
                arguments: ["wineboot", "--end-session", "--force", "--kill"], prefix: prefix, d3dMetalOptions: options),
                logURL: store.logsDirectory.appendingPathComponent("stop-\(UUID().uuidString).log"), timeout: .seconds(15))
            if result.exitCode != 0 {
                stopping = false
                throw LauncherError.commandFailed(result.exitCode, "The environment could not be stopped. See \(result.logURL.lastPathComponent).")
            }
        } catch { stopping = false; self.error = error.localizedDescription }
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Good-Gameble-Games-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = """
        Good Gameble Games \(appVersion) — diagnostics
        Date: \(Date().ISO8601Format())
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB
        Wine: \(library.runtime?.version ?? "Not configured")
        Runtime: \(library.runtime?.executable.path ?? "None")
        Environments: \(library.bottles.count)
        Library entries: \(library.games.count)
        Status: \(notice)

        Environment runtimes:
        \(library.bottles.map { "\($0.name): \($0.runtime.version) at \($0.runtime.executable.path); last Windows command test: \($0.lastSmokeTest?.ISO8601Format() ?? "not run")" }.joined(separator: "\n"))

        D3DMetal launch settings:
        \(library.bottles.filter { D3DMetalRuntime.isManaged($0.runtime.executable) }.map {
            "\($0.name): \(($0.d3dMetalOptions ?? D3DMetalOptions()).summary)"
        }.joined(separator: "\n"))

        Graphics reports:
        \(library.bottles.map { bottle in
            "\(bottle.name): \(bottle.activeGraphicsBackend.title)\n" + (bottle.lastGraphicsCheck.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? "Not checked")
        }.joined(separator: "\n"))

        Game renderer and benchmark reports:
        \(library.games.map { game in
            "\(game.name):\n" + (game.lastRendererReport.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? "Renderer not checked") + "\n" +
            (game.lastBenchmark.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? "No benchmark")
        }.joined(separator: "\n"))

        Latest output (common personal paths and credentials redacted; review before sharing):
        \(logText)
        """
        do { try DiagnosticRedactor.redact(report).write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }

    var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }

    private func begin(_ title: String) { busy = true; operation = title; stopping = false; error = nil; engineLogURL = nil }
    private func finish() {
        logTask?.cancel()
        if logURL != nil { logText = latestOutput() }
        busy = false; activeGameID = nil; activePrefix = nil; activeRuntime = nil; stopping = false
    }
    private func newLog(_ label: String) -> URL {
        let url = store.logsDirectory.appendingPathComponent("\(label)-\(UUID().uuidString).log")
        followLog(url)
        return url
    }
    private func followLog(_ url: URL) {
        logURL = url
        logText = ""
        logTask?.cancel()
        logTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.logText = self?.latestOutput() ?? ""
                if let self, let game = self.library.games.first(where: { $0.id == self.activeGameID }),
                   game.launchProfile != nil,
                   let report = GameRendererReport.parse(self.logText, profile: game.launchProfile) { self.activeRendererReport = report }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func latestOutput() -> String {
        let wine = logURL.map { LogReader.tail($0) } ?? ""
        return wine + (engineLogURL.map { "\n\nFTE game console:\n" + LogReader.tail($0) } ?? "")
    }
}
