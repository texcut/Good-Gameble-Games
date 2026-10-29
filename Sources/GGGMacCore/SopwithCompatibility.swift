import Foundation

/// SDL2 skips its unsupported DXGI rotation call in Windows 7 mode.
/// Wine's AppDefaults entry affects sopwith.exe only in this prefix.
public enum SopwithCompatibility {
    private static let key = #"HKCU\Software\Wine\AppDefaults\sopwith.exe"#

    public static func prepare(runtime: WineRuntime, prefix: URL, logDirectory: URL) async throws {
        try WineCommand.validateRuntime(runtime.executable)
        try WineCommand.validatePrefix(prefix)
        let runner = ProcessRunner()
        func command(_ args: [String], label: String) async throws -> ProcessResult {
            try await runner.run(WineCommand(executable: runtime.executable, arguments: ["reg.exe"] + args, prefix: prefix),
                logURL: logDirectory.appendingPathComponent("sopwith-\(label)-\(UUID().uuidString).log"), timeout: .seconds(30))
        }
        let query = try await command(["query", key, "/v", "Version"], label: "query")
        if query.exitCode == 0 {
            guard hasWindows7Value(LogReader.tail(query.logURL)) else {
                throw LauncherError.gameSetupFailed("Sopwith has a different Windows version override. It was preserved; choose a separate environment for this test.")
            }
            return
        }
        try Task.checkCancellation()
        // No /f: reg.exe must not overwrite a value that appeared since the query.
        let write = try await command(["add", key, "/v", "Version", "/t", "REG_SZ", "/d", "win7"], label: "configure")
        guard write.exitCode == 0 else { throw LauncherError.gameSetupFailed("Sopwith's Windows 7 compatibility setting could not be saved. See Activity logs.") }
        let verify = try await command(["query", key, "/v", "Version"], label: "verify")
        guard verify.exitCode == 0, hasWindows7Value(LogReader.tail(verify.logURL)) else {
            throw LauncherError.gameSetupFailed("Sopwith's Windows version setting could not be verified.")
        }
    }

    static func hasWindows7Value(_ output: String) -> Bool {
        output.range(of: #"(?m)^\s*Version\s+REG_SZ\s+win7\s*$"#, options: .regularExpression) != nil
    }
}
