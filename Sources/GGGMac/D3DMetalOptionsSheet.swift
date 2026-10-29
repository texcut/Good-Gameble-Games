import GGGMacCore
import SwiftUI

struct D3DMetalOptionsSheet: View {
    @Bindable var model: AppModel
    let bottle: Bottle
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @ViewState private var options: D3DMetalOptions
    @ViewState private var verifiedWitcher: Bool?

    init(model: AppModel, bottle: Bottle, game: Game) {
        self.model = model
        self.bottle = bottle
        self.game = game
        _options = ViewState(initialValue: bottle.d3dMetalOptions ?? D3DMetalOptions())
    }
    private var restartsEnvironment: Bool {
        let previous = bottle.d3dMetalOptions ?? D3DMetalOptions()
        return options.msyncEnabled != previous.msyncEnabled || options.metalFXEnabled != previous.metalFXEnabled
            || (options.metalFXEnabled && WitcherMetalFXPatch.isCandidate(game.executable))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Graphics and performance", systemImage: "slider.horizontal.3").font(.title2).fontWeight(.semibold)
            Text(bottle.name).foregroundStyle(.secondary)
            Toggle("Use MetalFX (DLSS)", isOn: $options.metalFXEnabled)
                .disabled(
                    WitcherMetalFXPatch.isCandidate(game.executable) && verifiedWitcher != true
                        && !options.metalFXEnabled)
            Text("Uses Apple's upscaling through the game's DLSS option. Select DLSS in the game after saving.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if WitcherMetalFXPatch.isCandidate(game.executable) {
                Text(
                    verifiedWitcher == nil
                        ? "Checking this Witcher executable…"
                        : verifiedWitcher == true
                            ? "Compatible Witcher build. MetalFX uses a separate compatibility copy and preserves the original executable. Turning it off returns to the original."
                            : "This Witcher build is not supported by the MetalFX workaround. Keep MetalFX off to launch the original."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Allow ray tracing", isOn: $options.rayTracingEnabled)
            Text(
                "After restarting the game, enable ray tracing in its graphics menu. Feature support and performance depend on the game and Mac."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Use MSync", isOn: $options.msyncEnabled)
            Text("An alternative synchronization method. Performance varies by game.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Metal backend", selection: $options.backend) {
                ForEach(D3DMetalBackend.allCases, id: \.self) { backend in
                    Text(backend.title).tag(backend).disabled(
                        backend == .metal4
                            && !ProcessInfo.processInfo.isOperatingSystemAtLeast(
                                OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                    )
                }
            }
            Toggle("Show FPS and frame times", isOn: $options.showPerformanceHUD)
            Text(
                "Displays Apple's Metal performance overlay while playing. These settings apply to this environment; the game keeps its resolution and quality settings."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if restartsEnvironment {
                Text("Applying these settings stops Windows programs in this environment. Save any Windows work first.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if model.busy { ProgressView(model.operation).controlSize(.small) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(restartsEnvironment ? "Save and restart environment" : "Save") {
                    Task {
                        if await model.saveD3DMetalOptions(options, bottleID: bottle.id, gameID: game.id) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 540).disabled(model.busy).interactiveDismissDisabled(model.busy)
            .task {
                guard WitcherMetalFXPatch.isCandidate(game.executable) else { return }
                verifiedWitcher = await Task.detached {
                    (try? RuntimeInstaller.checksum(of: game.executable)) == WitcherMetalFXPatch.originalSHA256
                }.value
            }
    }
}
