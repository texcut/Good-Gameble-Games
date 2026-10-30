import AppKit
import GGGMacCore
import SwiftUI

private let accent = Color(red: 0.69, green: 0.79, blue: 0.40)
private let surface = Color(red: 0.10, green: 0.115, blue: 0.12)

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ViewState private var showSetup = false
    @ViewState private var showGame = false
    @ViewState private var performanceGame: Game?
    @ViewState private var search = ""
    @ViewState private var environmentName = "Game environment"
    @ViewState private var selectedBottleID: UUID?
    @ViewState private var showNewEnvironment = false

    private var setup: SetupProgress { SetupProgress(library: model.library) }
    private var editingDisabled: Bool { model.busy || model.loadFailed }
    private var selectedBottle: Bottle? {
        model.library.bottles.first { $0.id == selectedBottleID } ?? model.library.bottles.first
    }
    private var connectedRuntime: WineRuntime? {
        model.library.runtime ?? model.library.bottles.first?.runtime
    }
    private var visibleGames: [Game] {
        model.library.games.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.loadFailed {
                        Label(
                            "The library could not be loaded. Your saved files have been preserved.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                    if !setup.isComplete {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Setup").font(.title2).fontWeight(.semibold)
                            Spacer()
                            Text("\(setup.completedSteps) of 3 complete").font(.caption).foregroundStyle(.secondary)
                        }
                        setupSections
                    } else if showSetup {
                        HStack {
                            Text("Setup").font(.title2).fontWeight(.semibold)
                            Spacer()
                            Button("Done") { showSetup = false }
                        }
                        setupSections
                    }
                    if !model.library.games.isEmpty { gamesSection }
                }
                .padding(28).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }
            if model.busy || !model.notice.isEmpty { operationBar }
        }
        .background(Color(red: 0.065, green: 0.075, blue: 0.08))
        .tint(accent)
        .sheet(isPresented: $showGame) { GameSheet(model: model, initialBottleID: selectedBottle?.id) }
        .sheet(item: $model.installedGamesBottle) { bottle in
            InstalledGamesSheet(model: model, bottle: bottle) {}
        }
        .sheet(item: $model.graphicsBottle) { bottle in
            GraphicsSettingsSheet(model: model, bottleID: bottle.id)
        }
        .sheet(item: $performanceGame) { game in
            if let bottle = model.library.bottles.first(where: { $0.id == game.bottleID }) {
                D3DMetalOptionsSheet(model: model, bottle: bottle, game: game)
            }
        }
        .alert(
            "Could not complete the operation",
            isPresented: Binding(
                get: { model.error != nil }, set: { if !$0 { model.error = nil } }
            )
        ) {
            Button("Open Logs") { openWindow(id: "logs") }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .onChange(of: setup.isComplete) { _, complete in
            if complete { showSetup = false }
        }
        .onChange(of: model.library.bottles.map(\.id), initial: true) { _, ids in
            if let id = selectedBottleID, ids.contains(id) { return }
            selectedBottleID = ids.first
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
            Text("Good Gameble Games").font(.system(size: 19, weight: .semibold))
            Spacer()
            if setup.isComplete {
                Button {
                    showSetup.toggle()
                } label: {
                    Label("Setup", systemImage: "gearshape")
                }
                .help("Manage runtimes and environments")
            }
            Button {
                openWindow(id: "logs")
            } label: {
                Label("Logs", systemImage: "terminal")
            }
            if setup.isComplete {
                Button {
                    showGame = true
                } label: {
                    Label("Add game", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).disabled(editingDisabled)
            }
        }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 18)
    }

    private var setupSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupSection(number: 1, title: "Connect a runtime", done: setup.runtimeReady) { runtimeSection }
            setupSection(number: 2, title: "Create an environment", done: setup.environmentReady) {
                environmentsSection
            }
            setupSection(number: 3, title: "Install or add a game", done: setup.gameReady) { installSection }
        }
    }

    private func setupSection<Content: View>(
        number: Int, title: String, done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? accent.opacity(0.14) : Color.white.opacity(0.08)).frame(width: 26, height: 26)
                    if done {
                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(accent)
                    } else {
                        Text("\(number)").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }.accessibilityLabel(done ? "Step \(number) complete" : "Step \(number)")
                Text(title).font(.headline)
            }
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let runtime = connectedRuntime {
                HStack {
                    Text(runtime.version).font(.subheadline).textSelection(.enabled)
                    Spacer()
                    Button("Change default…") { model.pickRuntime() }.disabled(editingDisabled)
                }
                if !setup.gameReady && !D3DMetalRuntime.isManaged(runtime.executable) {
                    Text(
                        "For Witcher 3, connect a prepared D3DMetal runtime. The standard Wine download supports Direct3D 10/11."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(
                    "Wine runs Windows programs. Select the wine or wine64 executable from a compatible macOS runtime."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Witcher 3 needs a prepared D3DMetal runtime. Its Direct3D 12 setup is still manual.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Connect runtime…") { model.pickRuntime() }
                        .buttonStyle(.borderedProminent).disabled(editingDisabled)
                    Link(
                        "DX12 setup details",
                        destination: URL(
                            string:
                                "https://github.com/texcut/Good-Gameble-Games/blob/main/docs/GRAPHICS.md#d3dmetal-advanced-setup"
                        )!)
                }
            }
            DisclosureGroup("Runtime options") {
                VStack(alignment: .leading, spacing: 16) {
                    if let runtime = connectedRuntime {
                        Text(runtime.executable.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(
                            "The default applies to new environments. Existing environments keep their assigned runtime."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    installedRuntimes
                    Divider()
                    managedRuntime
                }.padding(.top, 12)
            }.font(.subheadline)
        }
    }

    private var installedRuntimes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installed runtimes").fontWeight(.medium)
                Spacer()
                Button("Scan again") { model.refreshRuntimes() }.disabled(model.busy)
            }
            if let scanned = model.lastRuntimeScan {
                Text(
                    "Scanned \(scanned.formatted(date: .omitted, time: .shortened)) · \(model.discoveredRuntimes.count) found"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if model.discoveredRuntimes.isEmpty {
                Text("No runtime found in the standard folders. Use Connect runtime to select one elsewhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.discoveredRuntimes) { candidate in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.name)
                        Text(candidate.executable.path).font(.caption).foregroundStyle(.secondary).textSelection(
                            .enabled)
                    }
                    Spacer()
                    Button("Connect") { Task { await model.connectRuntime(candidate.executable) } }.disabled(
                        editingDisabled)
                }
            }
        }
    }

    private var managedRuntime: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wine for Direct3D 10/11").fontWeight(.medium)
            Text(
                "Wine 11.0 · 332 MB download · macOS 15+ and Rosetta 2 on Apple Silicon. This download does not include the Direct3D 12 setup for Witcher 3."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let issue = RuntimeInstaller.requirementIssue, !model.hasManagedRuntime {
                Text(issue).font(.caption).foregroundStyle(.orange)
            }
            if let stage = model.runtimeInstallStage { ProgressView(stage).controlSize(.small) }
            HStack {
                if model.runtimeInstallInProgress {
                    Button("Cancel download") { model.cancelRuntimeInstall() }
                } else {
                    Button(model.hasManagedRuntime ? "Use downloaded runtime" : "Download Wine") {
                        model.startRuntimeInstall()
                    }
                    .disabled(editingDisabled || (!model.hasManagedRuntime && RuntimeInstaller.requirementIssue != nil))
                }
                Spacer()
                Link(
                    "Download details",
                    destination: URL(string: "https://github.com/frankea/Whisky/releases/tag/v3.1.1")!
                )
                .font(.caption)
            }
        }
    }

    private var environmentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.library.bottles.isEmpty {
                Text(
                    "An environment holds the Windows files and settings for your game. Connect a runtime first, then create one."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.library.bottles) { bottle in environmentRow(bottle) }
            if model.library.bottles.isEmpty {
                createEnvironment
            } else {
                DisclosureGroup("Add another environment", isExpanded: $showNewEnvironment) {
                    createEnvironment.padding(.top, 10)
                }.font(.subheadline)
            }
        }
    }

    private var createEnvironment: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Environment name", text: $environmentName).textFieldStyle(.roundedBorder)
                    .disabled(editingDisabled || model.library.runtime == nil)
                Button("Create environment") {
                    Task {
                        if await model.createBottle(name: environmentName) { showNewEnvironment = false }
                    }
                }.disabled(
                    editingDisabled || model.library.runtime == nil
                        || environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.library.runtime == nil && setup.environmentReady {
                Text("Choose a default runtime in step 1 to create another environment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func environmentRow(_ bottle: Bottle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(bottle.name).fontWeight(.medium)
                Text("\(bottle.runtime.version) · \(bottle.activeGraphicsBackend.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Graphics…") { model.graphicsBottle = bottle }.disabled(editingDisabled)
            Menu {
                Button("Find installed games…") { model.installedGamesBottle = bottle }.disabled(editingDisabled)
                Button("Change runtime…") { model.pickRuntime(for: bottle) }.disabled(editingDisabled)
                Button("Open folder") { NSWorkspace.shared.open(model.store.prefix(for: bottle)) }
            } label: {
                Image(systemName: "ellipsis")
            }.menuStyle(.borderlessButton).frame(width: 24)
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !setup.gameReady {
                Text(
                    "Run your local installer, or add an already installed .exe. For a GOG offline installer, keep the setup .exe and every numbered .bin file in the same folder and select that folder."
                )
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.library.bottles.count > 1 {
                Picker("Environment", selection: $selectedBottleID) {
                    ForEach(model.library.bottles) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(editingDisabled)
            }
            HStack {
                Button("Run installer…") {
                    if let bottle = selectedBottle { model.runInstaller(in: bottle) }
                }.buttonStyle(.borderedProminent).disabled(editingDisabled || selectedBottle == nil)
                Button("Add installed game…") { showGame = true }.disabled(editingDisabled || selectedBottle == nil)
                if let bottle = selectedBottle {
                    Button("Find installed games…") { model.installedGamesBottle = bottle }.disabled(editingDisabled)
                }
            }
            if !setup.environmentReady {
                Text("Create an environment in step 2 to continue.").font(.caption).foregroundStyle(.secondary)
            } else if !setup.gameReady {
                Text("After the installer closes, select the game's executable in the list, add it, then press Play.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Games").font(.title2).fontWeight(.semibold)
                Text("\(model.library.games.count)").foregroundStyle(.secondary)
                Spacer()
                TextField("Search games", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                Menu("Install…") {
                    ForEach(model.library.bottles) { bottle in
                        Button(bottle.name) { model.runInstaller(in: bottle) }
                    }
                }.disabled(editingDisabled || model.library.bottles.isEmpty)
            }
            if visibleGames.isEmpty {
                Text("No games match “\(search)”.").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            LazyVStack(spacing: 10) {
                ForEach(visibleGames) { game in gameRow(game) }
            }
        }
    }

    private func gameRow(_ game: Game) -> some View {
        let bottle = model.library.bottles.first { $0.id == game.bottleID }
        return HStack(spacing: 16) {
            Image(systemName: "gamecontroller").font(.title2).foregroundStyle(accent)
                .frame(width: 40, height: 40).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name).font(.headline)
                Text(bottle?.name ?? "Missing environment").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let bottle {
                Button {
                    if D3DMetalRuntime.isManaged(bottle.runtime.executable) {
                        performanceGame = game
                    } else {
                        model.graphicsBottle = bottle
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Graphics and performance").accessibilityLabel("Graphics and performance for \(game.name)")
                .disabled(editingDisabled)
            }
            Button {
                Task { await model.launch(game) }
            } label: {
                Label(model.activeGameID == game.id ? "Running" : "Play", systemImage: "play.fill").frame(width: 76)
            }.buttonStyle(.borderedProminent).disabled(editingDisabled || bottle == nil)
            Menu {
                Button("Reveal executable") { NSWorkspace.shared.activateFileViewerSelecting([game.executable]) }
                Button("Environment settings") { showSetup = true }
                Button("Open Logs") { openWindow(id: "logs") }
                Divider()
                Button("Remove from library", role: .destructive) { model.removeGame(game) }.disabled(editingDisabled)
            } label: {
                Image(systemName: "ellipsis")
            }.menuStyle(.borderlessButton).frame(width: 24)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var operationBar: some View {
        HStack(spacing: 10) {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.busy ? model.operation : model.notice).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.runtimeInstallInProgress {
                Button("Cancel download") { model.cancelRuntimeInstall() }
            }
            if model.activePrefix != nil {
                Button(model.stopping ? "Stopping…" : "Stop environment", role: .destructive) {
                    Task { await model.stopEnvironment() }
                }.disabled(model.stopping)
            }
            Button("Logs") { openWindow(id: "logs") }
        }.padding(.horizontal, 28).padding(.vertical, 10).background(surface.opacity(0.6))
    }
}
struct GameSheet: View {
    @Bindable var model: AppModel
    let initialBottleID: UUID?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var executable: URL?
    @ViewState private var bottleID: UUID?
    @ViewState private var arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Add a Windows game", systemImage: "plus.app").font(.title2).fontWeight(.semibold)
            Text("Choose an installed game’s executable. To install a game first, use Run installer on the setup page.")
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
        }.padding(30).frame(width: 480).disabled(model.busy || model.loadFailed)
            .onAppear { bottleID = initialBottleID ?? model.library.bottles.first?.id }
    }
}
