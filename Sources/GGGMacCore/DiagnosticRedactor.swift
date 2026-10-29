import Foundation

/// Best-effort redaction for an explicit export; on-disk logs remain unchanged.
public enum DiagnosticRedactor {
    public static func redact(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var result = homeDirectory.isEmpty ? text : text.replacingOccurrences(of: homeDirectory, with: "~")
        let rules: [(String, String)] = [
            (#"/Users/[^/\s\"']+"#, "/Users/<user>"),
            (#"(?i)([A-Z]:\\users\\)[^\\\s\"']+"#, "$1<user>"),
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED]"),
            (
                #"(?i)(\b(?:password|access[_-]?token|refresh[_-]?token|api[_-]?key|client[_-]?secret|secret)\b[\"']?\s*(?:=|:|\s)\s*[\"']?)([^\s\"'&;,}]+)"#,
                "$1[REDACTED]"
            ),
            (#"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b"#, "[REDACTED]"),
        ]
        for (pattern, replacement) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        return result
    }
}
