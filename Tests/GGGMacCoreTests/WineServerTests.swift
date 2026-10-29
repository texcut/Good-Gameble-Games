import Foundation
import Testing
@testable import GGGMacCore

private struct ServerStopScenario: Sendable {
    let kill: Int
    var wait: Int = 0
    var check: Int = 1
    var killError = ""
    var checkError = ""
    var waitScript = ""
    let succeeds: Bool
    var calls = ["-k", "-w", "-k0"]
}

private struct ServerFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac server tests \(UUID().uuidString)")
    var prefix: URL { root.appendingPathComponent("prefix with spaces") }
    var runtime: WineRuntime { WineRuntime(executable: root.appendingPathComponent("wine"), version: "test") }
    var log: URL { root.appendingPathComponent("stop.log") }
    init(_ scenario: ServerStopScenario) throws {
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try Data().write(to: prefix.appendingPathComponent("system.reg"))
        let script = """
        #!/bin/sh
        printf '%s\\n' "$1" >> "$WINEPREFIX/calls"
        case "$1" in
          -k) printf '%s' '\(scenario.killError)' >&2; exit \(scenario.kill) ;;
          -w) \(scenario.waitScript.isEmpty ? "exit \(scenario.wait)" : scenario.waitScript) ;;
          -k0) printf '%s' '\(scenario.checkError)' >&2; exit \(scenario.check) ;;
          *) exit 9 ;;
        esac
        """
        let server = root.appendingPathComponent("wineserver")
        try script.write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test(arguments: [
    ServerStopScenario(kill: 1, succeeds: true), // already stopped: original regression
    ServerStopScenario(kill: 0, succeeds: true), // running server stopped normally
    ServerStopScenario(kill: 1, killError: "permission denied", succeeds: false, calls: ["-k"]),
    ServerStopScenario(kill: 2, succeeds: false, calls: ["-k"]),
    ServerStopScenario(kill: 0, wait: 1, succeeds: false, calls: ["-k", "-w"]),
    ServerStopScenario(kill: 1, check: 0, succeeds: false), // old server still present
    ServerStopScenario(kill: 0, check: 2, succeeds: false),
    ServerStopScenario(kill: 1, checkError: "invalid lock", succeeds: false)
])
private func serverStopRequiresConfirmedAbsence(_ scenario: ServerStopScenario) async throws {
    let fixture = try ServerFixture(scenario); defer { fixture.clean() }
    do {
        try await WineServer.stop(runtime: fixture.runtime, prefix: fixture.prefix, logURL: fixture.log)
        #expect(scenario.succeeds)
    } catch {
        #expect(!scenario.succeeds)
        #expect(error.localizedDescription.contains("Settings were not saved"))
    }
    let calls = try String(contentsOf: fixture.prefix.appendingPathComponent("calls"), encoding: .utf8)
    #expect(calls.split(separator: "\n").map(String.init) == scenario.calls)
}

@Test private func serverStopTimesOutInsteadOfSavingWhileServerRemains() async throws {
    let fixture = try ServerFixture(ServerStopScenario(kill: 1, waitScript: "exec /bin/sleep 20", succeeds: false))
    defer { fixture.clean() }
    do {
        try await WineServer.stop(runtime: fixture.runtime, prefix: fixture.prefix, logURL: fixture.log,
                                  timeout: .seconds(1))
        Issue.record("A live server wait must prevent saving a new synchronization mode")
    } catch let error as LauncherError {
        guard case .commandTimedOut = error else { Issue.record("Unexpected error: \(error)"); return }
    }
    let calls = try String(contentsOf: fixture.prefix.appendingPathComponent("calls"), encoding: .utf8)
    #expect(calls == "-k\n-w\n")
}

/// Test mode changes in one disposable prefix, without stopping the user's game.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GGGMAC_SERVER_TEST_RUNTIME"] != nil))
func realWineServerIdleAndMSyncTransitions() async throws {
    let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GGGMAC_SERVER_TEST_RUNTIME"]))
    try D3DMetalRuntime.validate(executable: executable)
    let runtime = WineRuntime(executable: executable, version: "server transition test")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GGGMac real server \(UUID().uuidString)")
    let prefix = root.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let runner = ProcessRunner()
    do {
        let boot = try await runner.run(WineCommand(executable: executable, arguments: ["wineboot", "--init"],
            prefix: prefix), logURL: root.appendingPathComponent("boot.log"), timeout: .seconds(180))
        try #require(boot.exitCode == 0, "Logs: \(root.path)")
        for (index, msync) in [true, false, true].enumerated() {
            try await WineServer.stop(runtime: runtime, prefix: prefix, logURL: root.appendingPathComponent("stop-\(index).log"))
            let idleLog = root.appendingPathComponent("idle-\(index).log")
            try await WineServer.stop(runtime: runtime, prefix: prefix, logURL: idleLog)
            #expect(LogReader.tail(idleLog).isEmpty)
            var bottle = Bottle(name: "Transition", runtime: runtime)
            bottle.d3dMetalOptions = D3DMetalOptions(msyncEnabled: msync)
            let result = try await runner.run(WineCommand.smokeTest(bottle: bottle, prefix: prefix),
                logURL: root.appendingPathComponent("smoke-\(index).log"), timeout: .seconds(90))
            try #require(result.exitCode == 0, "Logs: \(root.path)")
            let output = LogReader.tail(result.logURL)
            #expect(output.contains(WineCommand.smokeMarker))
            #expect(output.contains("msync: up and running") == msync)
        }
        try await WineServer.stop(runtime: runtime, prefix: prefix, logURL: root.appendingPathComponent("cleanup.log"))
        print("Real Wine server idle/transition checks passed. Logs:", root.path)
    } catch {
        try? await WineServer.stop(runtime: runtime, prefix: prefix, logURL: root.appendingPathComponent("cleanup-error.log"))
        throw error
    }
}
