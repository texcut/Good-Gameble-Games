import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let logURL: URL
}

/// One foreground Wine command at a time. File-backed output cannot fill a pipe and deadlock.
public actor ProcessRunner {
    private var active: Process?
    private var timedOut = false
    public init() {}

    public func run(_ command: WineCommand, logURL: URL, timeout: Duration? = nil) async throws -> ProcessResult {
        guard active == nil else { throw LauncherError.alreadyRunning }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        active = process
        timedOut = false
        let watchdog = timeout.map { timeout in
            Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                await self.expire(process)
            }
        }
        defer { watchdog?.cancel(); active = nil; try? output.close() }
        let result: ProcessResult = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: ProcessResult(exitCode: process.terminationStatus, logURL: logURL))
            }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        if timedOut { throw LauncherError.commandTimedOut }
        return result
    }

    private func expire(_ process: Process) async {
        guard active === process, process.isRunning else { return }
        timedOut = true
        process.terminate()
        try? await Task.sleep(for: .seconds(2))
        if active === process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

public enum LogReader {
    public static func tail(_ url: URL, maxBytes: Int = 64 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
            try handle.seek(toOffset: start)
            let bytes = try handle.readToEnd() ?? Data()
            return (start > 0 ? "[Showing the latest log output]\n" : "") + String(decoding: bytes, as: UTF8.self)
        } catch { return "Unable to read log: \(error.localizedDescription)" }
    }
}
