import GGGMacCore
import SwiftUI

struct GraphicsSettingsSheet: View {
    @Bindable var model: AppModel
    let bottleID: UUID
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selected = GraphicsBackend.runtimeDefault
    private var bottle: Bottle? { model.library.bottles.first { $0.id == bottleID } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                settingsContent.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if model.busy { ProgressView(model.operation).controlSize(.small) }
                HStack {
                    if model.activePrefix != nil {
                        Button(model.stopping ? "Stopping…" : "Stop environment") {
                            Task { await model.stopEnvironment() }
                        }
                        .disabled(model.stopping)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                }
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }.frame(width: 660, height: 600)
            .onAppear { selected = bottle?.activeGraphicsBackend ?? .runtimeDefault }
            .interactiveDismissDisabled(model.busy)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Windows graphics", systemImage: "display").font(.title2).fontWeight(.semibold)
            if let bottle {
                Text(bottle.name).foregroundStyle(.secondary)
                Text(
                    "DXMT translates Direct3D 10/11 to Metal. For Direct3D 12, use a separate environment with Runtime default or a compatible external runtime. Check graphics measures the selected configuration."
                )
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Backend", selection: $selected) {
                    Text(GraphicsBackend.runtimeDefault.title).tag(GraphicsBackend.runtimeDefault)
                    Text(GraphicsBackend.dxmt.title).tag(GraphicsBackend.dxmt)
                        .disabled(GraphicsBackendManager.payload(for: bottle.runtime) == nil)
                }.disabled(model.busy)
                Text(
                    "Close Windows programs in this environment before applying a change. DXMT files are installed only in this environment, with original DLLs backed up. Applying Runtime default restores those files."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Current: \(bottle.activeGraphicsBackend.title)").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Apply") {
                        Task {
                            await model.applyGraphics(selected, bottleID: bottleID)
                        }
                    }
                    .fixedSize().disabled(model.busy || model.loadFailed)
                }
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                DisclosureGroup("Graphics diagnostics") {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Measured capabilities").font(.headline)
                            Spacer()
                            Button("Run window test") {
                                Task { await model.checkGraphics(bottleID: bottleID, includePresentation: true) }
                            }
                            .disabled(model.busy || model.loadFailed)
                            Button("Check graphics") { Task { await model.checkGraphics(bottleID: bottleID) } }
                                .disabled(model.busy || model.loadFailed)
                        }
                        Text(
                            "Check graphics runs offscreen tests, including SM 6.0/DXIL execution. Run window test also opens a blue window for 60 verified DXIL frames and closes it automatically."
                        )
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let report = bottle.lastGraphicsCheck {
                            Text(
                                "\(report.checkedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.runtimeVersion) · \(report.backend.title)"
                            )
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            resultRow("OpenGL 3.2 · Windows-style request", result: report.openGL)
                            resultRow("Direct3D 11 clear/readback", result: report.direct3D)
                            if let result = report.direct3D12 {
                                resultRow("Direct3D 12 · SM 5.0 draw/readback", result: result)
                            } else {
                                Text("Direct3D 12 has not been checked. Run Check graphics to measure it.").font(
                                    .caption
                                ).foregroundStyle(.secondary)
                            }
                            if let result = report.direct3D12DXIL {
                                resultRow("Direct3D 12 · SM 6.0/DXIL execution", result: result)
                            } else {
                                Text("DXIL execution has not been checked.").font(.caption).foregroundStyle(.secondary)
                            }
                            if let result = report.direct3D12Presentation {
                                resultRow("Direct3D 12 · DXIL window presentation", result: result)
                            } else {
                                Text("Window presentation has not been checked. Use Run window test.").font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if report.direct3D12BaselinePassed {
                                Label("Direct3D 12 diagnostics passed", systemImage: "checkmark.circle")
                                    .font(.caption).foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
                            }
                            if report.backend == .dxmt, report.direct3D12?.passed == false {
                                Text(
                                    "Additional checks are available in the Logs window under Diagnostics."
                                )
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(
                                "No graphics check recorded. The diagnostic creates hidden Windows drawing surfaces and checks a pixel readback. It does not touch game saves."
                            )
                            .foregroundStyle(.secondary).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(
                            "Diagnostics check basic graphics features. Game compatibility and performance depend on the game, runtime and Mac."
                        )
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 12)
                }
            }
        }
    }
    private func resultRow(_ title: String, result: GraphicsAPIResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                "\(title): \(result.hasVerifiedPass ? "passed" : "not passed")",
                systemImage: result.hasVerifiedPass ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.subheadline).fontWeight(.medium).foregroundStyle(result.hasVerifiedPass ? Color.green : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
            if !result.renderer.isEmpty {
                Text(
                    "\(result.api.hasPrefix("d3d12") ? "Reported Windows adapter: " : "")\(result.renderer) · \(result.version)"
                ).font(.caption).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if result.api.hasPrefix("d3d12") {
                    Text("Windows may report a compatibility adapter name instead of the physical GPU model.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let implementation = result.implementation {
                Text(implementation).font(.caption).foregroundStyle(.secondary)
            }
            if let shaderModel = result.shaderModel {
                Text("Advertised shader model: \(shaderModel)").font(.caption)
            }
            if let target = result.shaderTarget { Text("Shader target: \(target)").font(.caption) }
            if let frames = result.completedPresents { Text("Successful presents: \(frames) of 60").font(.caption) }
            if let tier = result.resourceBindingTier { Text("Resource binding tier: \(tier)").font(.caption) }
            if let tier = result.rayTracingTier { Text("Reported ray tracing: \(tier)").font(.caption) }
            Text(result.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}
