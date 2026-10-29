import SwiftUI
import GGGMacCore

struct InstalledGamesSheet: View {
    @Bindable var model: AppModel
    let bottle: Bottle
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var scan: ExecutableScan?
    @ViewState private var scanError: String?
    @ViewState private var scanning = false
    @ViewState private var search = ""
    @ViewState private var showUtilities = false
    @ViewState private var selected: InstalledExecutable?
    @ViewState private var name = ""
    @ViewState private var scanNumber = 0

    private var visible: [InstalledExecutable] {
        (scan?.executables ?? []).filter {
            (showUtilities || !$0.isUtility) &&
            (search.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(search))
        }
    }
    private func alreadyAdded(_ entry: InstalledExecutable) -> Bool {
        model.library.games.contains {
            $0.bottleID == bottle.id && ExecutableIdentity.matches($0.executable, entry.executable)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Find installed games", systemImage: "magnifyingglass").font(.title2).fontWeight(.semibold)
            Text("\(bottle.name) · Choose an executable to add to your library.").foregroundStyle(.secondary)
            HStack {
                TextField("Search executable names or folders", text: $search).textFieldStyle(.roundedBorder)
                Button("Scan again") { scanNumber += 1 }.disabled(scanning)
            }
            Toggle("Show installers and utilities", isOn: $showUtilities).font(.caption)
            if scanning { ProgressView("Looking for installed Windows software…").controlSize(.small) }
            if let scanError { Text(scanError).foregroundStyle(.orange).font(.caption) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if visible.isEmpty && !scanning {
                        Text(scan?.executables.isEmpty == true
                             ? "No installed executables found. Run an installer first, or use Add game to choose an .exe outside this environment."
                             : "No matching executables. Try another search or show installers and utilities.")
                            .foregroundStyle(.secondary).padding(20)
                    }
                    ForEach(visible) { entry in
                        Button {
                            selected = entry
                            name = entry.suggestedName
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected?.id == entry.id ? "checkmark.circle.fill" : "app.dashed")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.suggestedName).fontWeight(.medium)
                                    Text(entry.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if alreadyAdded(entry) { Text("In library").font(.caption).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == entry.id ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(alreadyAdded(entry))
                    }
                }
            }.frame(height: 280).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            if let scan {
                Text("\(scan.executables.count) executables found\(scan.truncated ? " · scan limit reached; use Choose .exe for another path" : "")\(scan.unreadableFolders > 0 ? " · \(scan.unreadableFolders) folders could not be read" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let selected {
                TextField("Library name", text: $name).textFieldStyle(.roundedBorder)
                Text(selected.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Choose .exe…") {
                    if let url = model.pickEXE() {
                        selected = InstalledExecutable(executable: url, relativePath: url.path,
                                                       suggestedName: url.deletingPathExtension().lastPathComponent, isUtility: false)
                        name = url.deletingPathExtension().lastPathComponent
                    }
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add to library") {
                    if let selected, model.addGame(name: name, executable: selected.executable, bottleID: bottle.id, arguments: []) {
                        dismiss(); onAdded()
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
        }.padding(28).frame(width: 620)
        .task(id: scanNumber) {
            scanning = true; scanError = nil
            defer { scanning = false }
            do { scan = try await InstalledExecutableScanner.scan(prefix: model.store.prefix(for: bottle)) }
            catch is CancellationError {}
            catch { scanError = error.localizedDescription }
        }
    }
}

private enum TestGameChoice: String, CaseIterable, Identifiable {
    case libreQuake, sopwith, openTTD
    var id: Self { self }
    var title: String {
        switch self {
        case .libreQuake: "LibreQuake · 3D Direct3D 11"
        case .sopwith: "SDL Sopwith · 2D Direct3D 11"
        case .openTTD: "OpenTTD"
        }
    }
    var version: String {
        switch self {
        case .libreQuake: "LibreQuake 0.09 beta + FTE 6202"
        case .sopwith: "SDL Sopwith 2.9.0"
        case .openTTD: "OpenTTD 15.3"
        }
    }
    var detail: String {
        switch self {
        case .libreQuake: "A free 3D first-person game. Downloads the official Lite game data and Windows FTE engine (about 60 MB combined), verifies both checksums, and adds it to your library. No Quake purchase or store account is needed."
        case .sopwith: "A small, free 2D flying game. Downloads the official Windows 64-bit ZIP (1.1 MB), verifies its checksum, and adds it to your library."
        case .openTTD: "Build a transport network of trains, roads, ships and aircraft. Downloads and verifies the official Windows 64-bit installer."
        }
    }
    var instructions: String {
        switch self {
        case .libreQuake: "Click Play in Library. Press Esc for the menu and start a single-player game. Move with WASD and the mouse; Space jumps. For a repeatable performance check, use the game card’s … menu → Run 3D benchmark (720p). It plays a recorded demo and exits when finished."
        case .sopwith: "After setup, open Library and click Play. Choose a single-player mode, play briefly, quit, and launch again. The game card shows SDL’s actual renderer, including any fallback."
        case .openTTD: "Follow the installer’s steps and keep the default folder. After it finishes, select openttd.exe, add it to your library, and click Play. Choose the free OpenGFX download if prompted."
        }
    }
    var note: String {
        switch self {
        case .libreQuake: "Runs windowed with a 720p preset. Timedemo FPS describes this scene and may be limited by the display or driver. It does not predict other games’ performance."
        case .sopwith: "Windows compatibility settings are applied automatically for this game."
        case .openTTD: "OpenGFX provides free base graphics; the game can download them on first launch."
        }
    }
    var source: URL {
        switch self {
        case .libreQuake: ThreeDTestGame.source
        case .sopwith: PortableTestGame.source
        case .openTTD: TestGameDownload.source
        }
    }
    var requiresDXMT: Bool { self != .openTTD }
}

struct TestGameSheet: View {
    @Bindable var model: AppModel
    let initialBottleID: UUID?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var bottleID: UUID?
    @ViewState private var choice = TestGameChoice.libreQuake
    private var selectedBottle: Bottle? { model.library.bottles.first { $0.id == bottleID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Try a free Windows game", systemImage: "gamecontroller").font(.title2).fontWeight(.semibold)
            Picker("Game", selection: $choice) {
                ForEach(TestGameChoice.allCases) { Text($0.title).tag($0) }
            }
            Text(choice.version).font(.headline)
            Text(choice.detail)
                .foregroundStyle(.secondary)
            Picker("Install into", selection: $bottleID) {
                ForEach(model.library.bottles) { Text($0.name).tag(Optional($0.id)) }
            }
            Text(choice.instructions)
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
            if choice.requiresDXMT && selectedBottle?.activeGraphicsBackend != .dxmt {
                Text("Enable DXMT first: Environments → Actions → Graphics. Then return here.")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Link("Official game and download details ↗", destination: choice.source)
            if choice == .libreQuake { Link("Official FTE engine download ↗", destination: ThreeDTestGame.engineSource) }
            Text(choice.note)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(choice == .openTTD ? "Download and run installer" : "Download and add to library") {
                    if let bottle = model.library.bottles.first(where: { $0.id == bottleID }) {
                        dismiss()
                        if choice == .openTTD { model.startTestGameInstall(in: bottle) }
                        else { model.startDirect3DGameInstall(in: bottle, threeD: choice == .libreQuake) }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(bottleID == nil || model.busy || model.loadFailed || (choice.requiresDXMT && selectedBottle?.activeGraphicsBackend != .dxmt))
            }
        }.padding(30).frame(width: 570)
        .onAppear { bottleID = initialBottleID ?? model.library.bottles.first?.id }
    }
}
