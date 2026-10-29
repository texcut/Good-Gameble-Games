import Foundation

public enum WineServer {
    /// Stop only this prefix, including the normal case where it is already idle.
    /// Settings may be committed only after both the wait and absence check pass.
    public static func stop(runtime: WineRuntime, prefix: URL, logURL: URL,
                            runner: ProcessRunner = ProcessRunner(), timeout: Duration = .seconds(20)) async throws {
        try WineCommand.validatePrefix(prefix)
        let server = runtime.executable.deletingLastPathComponent().appendingPathComponent("wineserver")
        func run(_ argument: String, log: URL) async throws -> ProcessResult {
            try await runner.run(WineCommand(executable: server, arguments: [argument], prefix: prefix),
                                 logURL: log, timeout: timeout)
        }
        func failure(_ result: ProcessResult) -> LauncherError {
            let detail = LogReader.tail(result.logURL, maxBytes: 1024).trimmingCharacters(in: .whitespacesAndNewlines)
            return .commandFailed(result.exitCode,
                "The environment could not stop. Settings were not saved. See \(result.logURL.lastPathComponent). \(detail)")
        }

        let stop = try await run("-k", log: logURL)
        // Wine's kill command returns 1 silently when there is no lock owner.
        // A reported error, signal termination or another exit status still fails.
        guard stop.exitCode == 0 || (stop.exitCode == 1 && LogReader.tail(stop.logURL).isEmpty) else {
            throw failure(stop)
        }
        let base = logURL.deletingPathExtension()
        let wait = try await run("-w", log: base.appendingPathExtension("wait.log"))
        guard wait.exitCode == 0 else { throw failure(wait) }
        // Signal 0 checks for a server without stopping or starting anything.
        // Do not save a new MSync mode if the old server is still present.
        let check = try await run("-k0", log: base.appendingPathExtension("verify.log"))
        guard check.exitCode == 1 && LogReader.tail(check.logURL).isEmpty else {
            throw LauncherError.gameSetupFailed(
                "The environment could not be confirmed stopped. Settings were not saved. See \(check.logURL.lastPathComponent).")
        }
    }
}
