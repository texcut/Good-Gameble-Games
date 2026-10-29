import Testing
@testable import GGGMacCore

@Test func diagnosticExportRedactsPersonalPathsAndCredentialsWithoutChangingMeasurements() {
    let token = "ghp_" + String(repeating: "x", count: 36)
    let input = """
    Runtime: /Users/Ada/Library/Wine/bin/wine
    Other: /Users/Guest/game.exe
    Save: C:\\users\\Ada\\Documents\\Witcher
    Authorization: Bearer abc.secret.123
    {"access_token":"privateValue"}
    --password swordfish
    API_KEY=hidden
    \(token)
    FPS: 48.1; GPU: 20.79 ms; D3D12 feature level 12.2
    """
    let result = DiagnosticRedactor.redact(input, homeDirectory: "/Users/Ada")
    for secret in ["/Users/Ada", "/Users/Guest", "users\\Ada", "abc.secret.123", "privateValue", "swordfish", "hidden", token] {
        #expect(!result.contains(secret))
    }
    #expect(result.contains("~/Library/Wine/bin/wine"))
    #expect(result.contains("FPS: 48.1; GPU: 20.79 ms; D3D12 feature level 12.2"))
    #expect(result.contains("[REDACTED]"))
}
