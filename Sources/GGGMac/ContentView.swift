import AppKit
import GGGMacCore
import SwiftUI

private let accent = Color(red: 0.69, green: 0.79, blue: 0.40)
private let surface = Color(red: 0.10, green: 0.115, blue: 0.12)

enum Page: String, CaseIterable, Identifiable {
    case library = "Library"
    case environments = "Environments"
    case runtime = "Runtime"
    case activity = "Activity"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .library: "square.grid.2x2"
        case .environments: "shippingbox"
        case .runtime: "cpu"
        case .activity: "waveform.path"
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @ViewState private var page = Page.library
    @ViewState private var showBottle = false
    @ViewState private var showGame = false
    @ViewState private var showTestGame = false
    @ViewState private var testGameBottleID: UUID?
    @ViewState private var performanceGame: Game?
    @ViewState private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        switch page {
                        case .library: libraryPage
                        case .environments: environmentsPage
                        case .runtime: runtimePage
                        case .activity: activityPage
                        }
                    }.padding(32).frame(maxWidth: 1200, alignment: .leading)
                }
                statusBar
            }
            .background(Color(red: 0.065, green: 0.075, blue: 0.08))
        }
        .tint(accent)
        .sheet(isPresented: $showBottle) { BottleSheet(model: model) }
        .sheet(isPresented: $showGame) { GameSheet(model: model) }
        .sheet(isPresented: $showTestGame) { TestGameSheet(model: model, initialBottleID: testGameBottleID) }
        .sheet(item: $model.installedGamesBottle) { bottle in
            InstalledGamesSheet(model: model, bottle: bottle) { page = .library }
        }
        .sheet(item: $model.graphicsBottle) { bottle in GraphicsSettingsSheet(model: model, bottleID: bottle.id) }
        .sheet(item: $performanceGame) { game in
            if let bottle = model.library.bottles.first(where: { $0.id == game.bottleID }) {
                D3DMetalOptionsSheet(model: model, bottle: bottle, game: game)
            }
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                Text("Good Gameble Games").font(.system(size: 19, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 46).padding(.bottom, 8)
            Text("A new home for Windows games.").font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 35)
            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(.tertiary).padding(.bottom, 12)
            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).frame(width: 19)
                        Text(item.rawValue).fontWeight(page == item ? .semibold : .regular)
                        Spacer()
                        if item == .library {
                            Text("\(model.library.games.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        if item == .activity && model.busy { Circle().fill(accent).frame(width: 6, height: 6) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .foregroundStyle(page == item ? accent : Color.secondary)
                    .background(page == item ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.architecture, systemImage: "desktopcomputer").font(.caption).fontWeight(.medium)
                HStack(spacing: 7) {
                    Circle().fill(model.library.runtime == nil ? .orange : accent).frame(width: 6, height: 6)
                    Text(model.library.runtime == nil ? "Runtime not connected" : "Wine connected").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
                surface, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("GOOD GAMEBLE GAMES").tracking(0.4)
                Spacer()
                Text(model.appVersion)
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).padding(.top, 18).padding(.bottom, 20)
        }.padding(.horizontal, 20).frame(width: 205).background(Color(red: 0.08, green: 0.09, blue: 0.095))
    }

    private var header: some View {
        HStack {
            Label(page.rawValue, systemImage: page.icon).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if page == .library {
                Button("Free games…") {
                    testGameBottleID = nil
                    showTestGame = true
                }
                .disabled(model.library.bottles.isEmpty || model.busy || model.loadFailed)
                TextField("Search your library", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                Button {
                    showGame = true
                } label: {
                    Label("Add game", systemImage: "plus")
                }
                .disabled(model.library.bottles.isEmpty || model.busy || model.loadFailed)
            }
        }.padding(.horizontal, 32).frame(height: 76)
    }

    private var libraryPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("YOUR GAMES. YOUR MAC.")
                Text("Good games belong here.").font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("One library. Isolated environments. A little less setup.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if model.library.games.isEmpty {
                setupCard
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(
                        accent.opacity(0.7))
                    Text("Your next adventure starts here").font(.title3).fontWeight(.medium)
                    Text(
                        "Add an installed Windows game or run a local installer.\nYour games stay on your Mac, in the folders you choose."
                    )
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(5)
                    Button("Add your first game") { showGame = true }.buttonStyle(.borderedProminent)
                        .disabled(model.library.bottles.isEmpty || model.busy || model.loadFailed)
                    Button("Try a free Windows game…") {
                        testGameBottleID = nil
                        showTestGame = true
                    }
                    .disabled(model.library.bottles.isEmpty || model.busy || model.loadFailed)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                HStack {
                    Text("ALL GAMES").font(.caption).fontWeight(.semibold).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.library.games.count) in your library").font(.caption).foregroundStyle(.tertiary)
                }
                let games = model.library.games.filter {
                    search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                }
                if games.isEmpty { Text("No games match “\(search)”.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
                    ForEach(games) { game in gameCard(game) }
                }
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Make yourself at home", systemImage: "sparkles").font(.headline)
                Spacer()
                Text("\(setupProgress) OF 3 READY").font(.system(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(accent)
            }
            HStack(alignment: .top, spacing: 20) {
                setupStep(
                    "01", "Set up Wine", "Download a free runtime or connect your own.",
                    done: model.library.runtime != nil
                ) { page = .runtime }
                setupStep(
                    "02", "Create an environment", "A separate Windows space for games.",
                    done: !model.library.bottles.isEmpty,
                    disabled: model.library.runtime == nil
                ) { showBottle = true }
                setupStep(
                    "03", "Add a game", "Choose a local Windows .exe.", done: !model.library.games.isEmpty,
                    disabled: model.library.bottles.isEmpty
                ) { showGame = true }
            }
        }.padding(24).background(surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06)))
    }

    private var setupProgress: Int {
        (model.library.runtime != nil ? 1 : 0) + (!model.library.bottles.isEmpty ? 1 : 0)
            + (!model.library.games.isEmpty ? 1 : 0)
    }

    private func setupStep(
        _ number: String, _ title: String, _ detail: String, done: Bool, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Text(done ? "✓" : number).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent).padding(8).background(
                        accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled || model.busy || model.loadFailed).opacity(disabled ? 0.4 : 1)
    }

    private func gameCard(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [accent.opacity(0.22), surface], startPoint: .topTrailing, endPoint: .bottomLeading)
                Image(systemName: "gamecontroller.fill").font(.system(size: 48)).foregroundStyle(accent.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("WINDOWS").font(.system(size: 9, weight: .bold)).tracking(2).padding(14).foregroundStyle(accent)
            }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 9))
            Text(game.name).font(.headline).lineLimit(2)
            if let bottle = model.library.bottles.first(where: { $0.id == game.bottleID }),
                D3DMetalRuntime.isManaged(bottle.runtime.executable)
            {
                Text("Direct3D 12 · Apple D3DMetal")
                    .font(.caption).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                Text((bottle.d3dMetalOptions ?? D3DMetalOptions()).summary)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Graphics and performance…") { performanceGame = game }
                    .buttonStyle(.bordered).font(.caption).disabled(model.busy || model.loadFailed)
            }
            Label(
                model.library.bottles.first { $0.id == game.bottleID }?.name ?? "Missing environment",
                systemImage: "shippingbox"
            )
            .font(.caption).foregroundStyle(.secondary)
            if game.launchProfile != nil || game.lastBenchmark != nil {
                DisclosureGroup("Details") {
                    if let profile = game.launchProfile {
                        let report =
                            model.activeGameID == game.id ? model.activeRendererReport : game.lastRendererReport
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Direct3D 11").font(.caption).fontWeight(.medium)
                            if let report {
                                Label(
                                    report.usesDirect3D11
                                        ? "\(profile.rendererLabel) renderer: Direct3D 11"
                                        : "Fallback: \(report.renderer)",
                                    systemImage: report.usesDirect3D11 ? "checkmark.circle" : "exclamationmark.triangle"
                                )
                                .foregroundStyle(report.usesDirect3D11 ? accent : .orange)
                                Text(report.checkedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(
                                    .secondary)
                            } else {
                                Text(
                                    game.lastPlayed == nil
                                        ? "Play to check the renderer" : "Renderer not confirmed; see Activity"
                                ).foregroundStyle(.secondary)
                            }
                        }.font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    if let benchmark = game.lastBenchmark {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last timedemo: \(benchmark.framesPerSecond, specifier: "%.1f") FPS").fontWeight(
                                .medium)
                            Text("720p preset · DXMT · \(benchmark.runtimeVersion)")
                            Text(benchmark.measuredAt.formatted(date: .abbreviated, time: .shortened))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await model.launch(game) }
                } label: {
                    Label(model.activeGameID == game.id ? "Running" : "Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(model.busy || model.loadFailed)
                Menu {
                    if game.launchProfile == .fteDirect3D11 {
                        Button("Run 3D benchmark (720p)") { Task { await model.launch(game, benchmark: true) } }
                            .disabled(model.busy || model.loadFailed)
                    }
                    Button("Reveal executable") { NSWorkspace.shared.activateFileViewerSelecting([game.executable]) }
                    Button("Remove from library", role: .destructive) { model.removeGame(game) }
                        .disabled(model.busy || model.loadFailed)
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).frame(width: 25)
            }
        }.padding(15).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var environmentsPage: some View {
        Group {
            pageTitle(
                "A space for every setup.",
                subtitle: "Environments keep Windows files and settings separate from one another.")
            HStack {
                Text("\(model.library.bottles.count) environment\(model.library.bottles.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showBottle = true
                } label: {
                    Label("New environment", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).disabled(
                    model.library.runtime == nil || model.busy || model.loadFailed)
            }
            if model.library.bottles.isEmpty {
                ContentUnavailableView(
                    "Room to play", systemImage: "shippingbox",
                    description: Text("Connect Wine, then create your first environment."))
            }
            ForEach(model.library.bottles) { bottle in
                HStack(spacing: 18) {
                    Image(systemName: "shippingbox").font(.title).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bottle.name).font(.headline)
                        Text(
                            "Created \(bottle.createdAt.formatted(date: .abbreviated, time: .omitted)) • \(model.library.games.filter { $0.bottleID == bottle.id }.count) games"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(bottle.runtime.version).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("Graphics: \(bottle.activeGraphicsBackend.title)").font(.caption).foregroundStyle(
                            .secondary)
                        if let checked = bottle.lastSmokeTest {
                            Label(
                                "Wine checked \(checked.formatted(date: .abbreviated, time: .shortened))",
                                systemImage: "checkmark.circle"
                            )
                            .font(.caption).foregroundStyle(accent)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("Run installer…") { model.runInstaller(in: bottle) }
                            .disabled(model.busy || model.loadFailed)
                        Menu("Actions") {
                            Button("Graphics…") { model.graphicsBottle = bottle }.disabled(
                                model.busy || model.loadFailed)
                            Button("Find installed games…") { model.installedGamesBottle = bottle }.disabled(
                                model.busy || model.loadFailed)
                            Button("Install a free game…") {
                                testGameBottleID = bottle.id
                                showTestGame = true
                            }.disabled(model.busy || model.loadFailed)
                            Button("Open folder") { NSWorkspace.shared.open(model.store.prefix(for: bottle)) }
                            Button("Check environment") { Task { await model.testEnvironment(bottle) } }.disabled(
                                model.busy || model.loadFailed)
                            Button("Change runtime…") { model.pickRuntime(for: bottle) }.disabled(
                                model.busy || model.loadFailed)
                        }.fixedSize()
                    }
                }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Text(
                "After an installer finishes, choose its executable from the list to add it to your library. You can also use Actions → Find installed games at any time."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var runtimePage: some View {
        Group {
            pageTitle(
                "The engine behind the games.", subtitle: "The launcher manages your library. Wine runs the Windows software."
            )
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "cpu").font(.largeTitle).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.library.runtime?.version ?? "No Wine runtime connected").font(.headline)
                            .textSelection(.enabled)
                        Text(
                            model.library.runtime?.executable.path
                                ?? "Select a macOS Wine distribution’s wine or wine64 executable."
                        )
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                }
                Divider()
                Text(
                    "Set up the free managed runtime below, or connect a trusted runtime you have installed yourself. The app checks its Wine version before saving it."
                )
                .foregroundStyle(.secondary).lineSpacing(4)
                Button(model.library.runtime == nil ? "Connect Wine runtime…" : "Change default runtime…") {
                    model.pickRuntime()
                }
                .buttonStyle(.borderedProminent).disabled(model.busy || model.loadFailed)
                if !model.library.bottles.isEmpty {
                    Text(
                        "The default applies to new environments. Existing environments keep their assigned runtime; change it in Environments → Actions."
                    ).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(26).background(surface, in: RoundedRectangle(cornerRadius: 14))
            DisclosureGroup("Advanced graphics diagnostics") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        "Check Direct3D 12 shader execution and presentation in a separate environment using the selected runtime."
                    )
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Create or check diagnostic environment") { Task { await model.prepareDirect3D12Test() } }
                        .disabled(model.library.runtime == nil || model.busy || model.loadFailed)
                    Button("Run installer in diagnostic environment…") { model.installIntoDirect3D12Environment() }
                        .disabled(model.library.runtime == nil || model.busy || model.loadFailed)
                    Text(
                        "Select the folder containing the offline setup .exe and every numbered .bin part. The installer opens after a source check; complete its installation steps, then choose the installed game executable."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link(
                        "Apple’s Game Porting Toolkit ↗",
                        destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!
                    ).font(.caption)
                }.padding(.top, 12)
            }.padding(26).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                Label("Set up Wine", systemImage: "arrow.down.circle").font(.headline)
                Text("Free Wine 11.0 runtime · Whisky community build 3.1.1")
                    .font(.subheadline).fontWeight(.medium)
                Text(
                    "Downloads 332 MB from the Whisky community project on GitHub, verifies its checksum and installs a separate copy for this app. Existing runtimes and environments keep their files."
                )
                .foregroundStyle(.secondary)
                Text(
                    "Requires macOS 15 or later, Rosetta 2 on Apple Silicon, and 2 GB free space. No CrossOver purchase or game is needed."
                )
                .font(.caption).foregroundStyle(.secondary)
                if let issue = RuntimeInstaller.requirementIssue, !model.hasManagedRuntime {
                    Text(issue).font(.caption).foregroundStyle(.orange)
                }
                if let stage = model.runtimeInstallStage {
                    ProgressView(stage).controlSize(.small)
                }
                HStack {
                    if model.runtimeInstallInProgress {
                        Button("Cancel setup") { model.cancelRuntimeInstall() }
                    } else {
                        Button(model.hasManagedRuntime ? "Use managed Wine runtime" : "Download and set up Wine") {
                            model.startRuntimeInstall()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            model.busy || model.loadFailed
                                || (!model.hasManagedRuntime && RuntimeInstaller.requirementIssue != nil))
                    }
                    Spacer()
                    Link(
                        "Source and release details ↗",
                        destination: URL(string: "https://github.com/frankea/Whisky/releases/tag/v3.1.1")!
                    )
                    .font(.caption)
                }
            }.padding(26).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Installed runtimes").font(.headline)
                    Spacer()
                    Button("Scan again") { model.refreshRuntimes() }.disabled(model.busy)
                }
                if let completed = model.lastRuntimeScan {
                    Label(
                        "Scan \(model.runtimeScanCount) complete at \(completed.formatted(date: .omitted, time: .standard)) · \(model.discoveredRuntimes.count) found",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption).foregroundStyle(accent)
                    .accessibilityLabel(
                        "Runtime scan \(model.runtimeScanCount) complete. \(model.discoveredRuntimes.count) runtimes found."
                    )
                }
                if model.discoveredRuntimes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No Wine runtime found", systemImage: "magnifyingglass").font(.headline)
                        Text(
                            "This app needs Wine to run Windows software. Use Download and set up Wine above, or connect an existing runtime. Scan again only searches for installed files."
                        )
                        .foregroundStyle(.secondary)
                        Text(
                            "If Wine is already installed elsewhere, choose its wine or wine64 executable using Connect Wine runtime above."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Link(
                            "Wine installation information ↗",
                            destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!
                        )
                        .font(.subheadline)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(model.discoveredRuntimes) { candidate in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(candidate.name).fontWeight(.medium)
                            Text(candidate.executable.path).font(.caption).foregroundStyle(.secondary).textSelection(
                                .enabled)
                        }
                        Spacer()
                        Button("Use as default") { Task { await model.connectRuntime(candidate.executable) } }
                            .disabled(model.busy || model.loadFailed)
                    }
                }
                DisclosureGroup("Folders checked (\(model.runtimeSearchLocations.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.runtimeSearchLocations, id: \.directory) { location in
                            Text(location.directory.path).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 8)
                }
                Text("Scanning only looks for files. A runtime runs its version check when you choose it.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                Text("Game compatibility").font(.headline)
                Text(
                    "The managed runtime includes DXMT for Direct3D 10/11. Direct3D 12 requires a compatible Wine runtime and a separate Apple D3DMetal setup. Games are installed from local files; store accounts are managed outside this app."
                )
                .foregroundStyle(.secondary).lineSpacing(5)
                Link("Wine project and documentation ↗", destination: URL(string: "https://www.winehq.org/")!)
            }.padding(26)
        }
    }

    private var activityPage: some View {
        Group {
            pageTitle("See what’s happening.", subtitle: "Live process output, saved locally for troubleshooting.")
            HStack {
                Label(
                    model.busy ? model.operation : "No active operation",
                    systemImage: model.busy ? "circle.dotted" : "checkmark.circle"
                )
                .foregroundStyle(model.busy ? accent : .secondary)
                Spacer()
                if model.testGameDownloadInProgress {
                    Button("Cancel game download") { model.cancelTestGameDownload() }
                }
                if model.activePrefix != nil {
                    Button(model.stopping ? "Stopping…" : "Stop environment", role: .destructive) {
                        Task { await model.stopEnvironment() }
                    }
                    .disabled(model.stopping)
                }
                Button("Export diagnostics…") { model.exportDiagnostics() }
                Button("All logs") {
                    do {
                        try model.store.prepare()
                        NSWorkspace.shared.open(model.store.logsDirectory)
                    } catch { model.error = error.localizedDescription }
                }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(
                    model.logText.isEmpty
                        ? "Process output will appear here.\nConnect a runtime, create an environment, or launch a game to begin."
                        : model.logText
                )
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(20)
            }.frame(height: 350).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            Text(
                "Showing the latest 64 KB. Full logs remain on disk. Diagnostic exports may include local paths and application output; review them before sharing."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.busy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(model.loadFailed ? .orange : accent).frame(width: 5, height: 5)
            }
            Text(
                model.loadFailed
                    ? "Library could not be loaded — saved data preserved" : model.busy ? model.operation : model.notice
            )
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Activity") { page = .activity }.buttonStyle(.plain).font(.caption).foregroundStyle(accent)
        }.padding(.horizontal, 32).frame(height: 43).background(surface.opacity(0.6))
    }
    private func eyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(accent)
    }
    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow(page.rawValue.uppercased())
            Text(title).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

struct BottleSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = "My first environment"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("New environment", systemImage: "shippingbox").font(.title2).fontWeight(.semibold)
            Text("Wine will create a separate Windows filesystem here. The first setup can take a few minutes.")
                .foregroundStyle(.secondary)
            TextField("Environment name", text: $name).textFieldStyle(.roundedBorder)
            if model.busy {
                HStack {
                    ProgressView(model.operation).controlSize(.small)
                    Spacer()
                    if model.activePrefix != nil {
                        Button(model.stopping ? "Stopping…" : "Stop setup") { Task { await model.stopEnvironment() } }
                            .disabled(model.stopping)
                    }
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("Create environment") {
                    Task { if await model.createBottle(name: name) { dismiss() } }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 450).interactiveDismissDisabled(model.busy)
    }
}

struct GameSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var executable: URL?
    @ViewState private var bottleID: UUID?
    @ViewState private var arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Add a Windows game", systemImage: "plus.app").font(.title2).fontWeight(.semibold)
            Text("Choose an installed game’s executable. To install a game first, use Run installer in Environments.")
                .foregroundStyle(.secondary)
            Button {
                if let url = model.pickEXE() {
                    executable = url
                    if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                }
            } label: {
                Label(executable?.lastPathComponent ?? "Choose .exe…", systemImage: "doc.badge.plus")
            }
            if let executable { Text(executable.path).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            TextField("Game name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Environment", selection: $bottleID) {
                Text("Choose an environment").tag(nil as UUID?)
                ForEach(model.library.bottles) { Text($0.name).tag(Optional($0.id)) }
            }
            DisclosureGroup("Launch arguments (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One argument per line. Spaces are preserved; no shell quoting needed.").font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 65)
                }.padding(.top, 8)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add game") {
                    if let executable, let bottleID,
                        model.addGame(
                            name: name, executable: executable, bottleID: bottleID,
                            arguments: arguments.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    {
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(
                        executable == nil || bottleID == nil
                            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 480)
            .onAppear { bottleID = model.library.bottles.first?.id }
    }
}
