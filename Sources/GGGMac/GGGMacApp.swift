import SwiftUI
import AppKit

// Select the property-wrapper type explicitly. Some prerelease SDKs also export
// a State macro without shipping its plugin in the standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct GGGMacApp: App {
    @ViewState private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Good Gameble Games") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Export Diagnostics…") { model.exportDiagnostics() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
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
