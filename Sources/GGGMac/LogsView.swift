import AppKit
import GGGMacCore
import SwiftUI

struct LogsView: View {
    @Bindable var model: AppModel
    @ViewState private var bottleID: UUID?
    private var selectedBottle: Bottle? {
        model.library.bottles.first { $0.id == bottleID } ?? model.library.bottles.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("Logs", systemImage: "terminal").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Open logs folder") { openLogsFolder() }
                Button("Export diagnostics…") { model.exportDiagnostics() }
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.busy ? model.operation : "No active operation").foregroundStyle(.secondary)
                Spacer()
                if model.runtimeInstallInProgress {
                    Button("Cancel download") { model.cancelRuntimeInstall() }
                }
                if model.activePrefix != nil {
                    Button(model.stopping ? "Stopping…" : "Stop environment", role: .destructive) {
                        Task { await model.stopEnvironment() }
                    }.disabled(model.stopping)
                }
            }
            if let log = model.logURL {
                Text(log.lastPathComponent).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(model.logText.isEmpty ? "No process output yet." : model.logText)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading).padding(16)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            Text("Latest 64 KB. Full logs remain in the logs folder. Review diagnostic exports before sharing them.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            DisclosureGroup("Diagnostics") { diagnostics.padding(.top, 10) }
                .disabled(model.loadFailed)
        }.padding(24).frame(minWidth: 700, minHeight: 540)
            .onChange(of: model.library.bottles.map(\.id), initial: true) { _, ids in
                if let id = bottleID, ids.contains(id) { return }
                bottleID = ids.first
            }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.library.bottles.isEmpty {
                Text("Create an environment on the setup page first.").foregroundStyle(.secondary)
            } else {
                Picker("Environment", selection: $bottleID) {
                    ForEach(model.library.bottles) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(model.busy)
                if let bottle = selectedBottle {
                    HStack {
                        Button("Check Wine") { Task { await model.testEnvironment(bottle) } }
                        Button("Check graphics") { Task { await model.checkGraphics(bottleID: bottle.id) } }
                        Button("Run window test") {
                            Task { await model.checkGraphics(bottleID: bottle.id, includePresentation: true) }
                        }
                    }.disabled(model.busy)
                    if let checked = bottle.lastSmokeTest {
                        Text("Wine responded \(checked.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let report = bottle.lastGraphicsCheck {
                        Text(
                            "Last graphics check: \(report.checkedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.backend.title)"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                            "Direct3D 11: \(report.direct3D.hasVerifiedPass ? "passed" : "not passed") · Direct3D 12 baseline: \(report.direct3D12BaselinePassed ? "passed" : "not passed")"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Checks basic Wine and graphics operations. The window test opens a temporary drawing window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openLogsFolder() {
        do {
            try model.store.prepare()
            NSWorkspace.shared.open(model.store.logsDirectory)
        } catch { model.error = error.localizedDescription }
    }
}
