import Foundation

public enum ExecutableIdentity {
    public static func matches(_ first: URL, _ second: URL) -> Bool {
        if first.resolvingSymlinksInPath().standardizedFileURL.path == second.resolvingSymlinksInPath().standardizedFileURL.path { return true }
        // macOS can spell the same temporary path with /var or /private/var.
        // Compare filesystem identifiers as well, without conflating files that
        // merely have identical contents.
        guard let firstID = try? first.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject,
              let secondID = try? second.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject else { return false }
        return firstID.isEqual(secondID)
    }
}
