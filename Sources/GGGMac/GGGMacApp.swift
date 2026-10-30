import AppKit
import SwiftUI

// Select the property-wrapper type explicitly. Some prerelease SDKs also export
// a State macro without shipping its plugin in the standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct GGGMacApp: App {
    @ViewState private var model: AppModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        #if DEBUG
            if let path = ProcessInfo.processInfo.environment["GGGMAC_PREVIEW_ROOT"], path.hasPrefix("/") {
                _model = ViewState(initialValue: AppModel(store: .init(root: URL(fileURLWithPath: path))))
            } else {
                _model = ViewState(initialValue: AppModel())
            }
        #else
            _model = ViewState(initialValue: AppModel())
        #endif
    }

    var body: some Scene {
        WindowGroup("Good Gameble Games") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 780, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Show Logs") { openLogs() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Export Diagnostics…") { model.exportDiagnostics() }
            }
        }
        Window("Logs", id: "logs") {
            LogsView(model: model).preferredColorScheme(.dark)
        }.defaultSize(width: 880, height: 640)
    }

    @Environment(\.openWindow) private var openWindow
    private func openLogs() { openWindow(id: "logs") }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url)
        {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Leave Wine applications alive when the launcher closes, as a regular game launcher does.
        .terminateNow
    }
}
