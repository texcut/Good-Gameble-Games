import GGGMacCore
import SwiftUI

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
            (showUtilities || !$0.isUtility)
                && (search.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(search))
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
                        Text(
                            scan?.executables.isEmpty == true
                                ? "No installed executables found. Run an installer first, or use Add game to choose an .exe outside this environment."
                                : "No matching executables. Try another search or show installers and utilities."
                        )
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
                                .background(
                                    selected?.id == entry.id ? Color.primary.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(alreadyAdded(entry))
                    }
                }
            }.frame(height: 280).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            if let scan {
                Text(
                    "\(scan.executables.count) executables found\(scan.truncated ? " · scan limit reached; use Choose .exe for another path" : "")\(scan.unreadableFolders > 0 ? " · \(scan.unreadableFolders) folders could not be read" : "")"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if let selected {
                TextField("Library name", text: $name).textFieldStyle(.roundedBorder)
                Text(selected.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(
                    .enabled)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Choose .exe…") {
                    if let url = model.pickEXE() {
                        selected = InstalledExecutable(
                            executable: url, relativePath: url.path,
                            suggestedName: url.deletingPathExtension().lastPathComponent, isUtility: false)
                        name = url.deletingPathExtension().lastPathComponent
                    }
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add to library") {
                    if let selected,
                        model.addGame(name: name, executable: selected.executable, bottleID: bottle.id, arguments: [])
                    {
                        dismiss()
                        onAdded()
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(
                        selected == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
        }.padding(28).frame(width: 620)
            .task(id: scanNumber) {
                scanning = true
                scanError = nil
                defer { scanning = false }
                do {
                    scan = try await InstalledExecutableScanner.scan(prefix: model.store.prefix(for: bottle))
                } catch is CancellationError {} catch { scanError = error.localizedDescription }
            }
    }
}
