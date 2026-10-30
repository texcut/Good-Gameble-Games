import Foundation

/// Derived from saved data so returning users do not repeat onboarding.
public struct SetupProgress: Equatable, Sendable {
    public let runtimeReady: Bool
    public let environmentReady: Bool
    public let gameReady: Bool

    public init(library: Library) {
        // An existing environment carries its own runtime even without a default.
        runtimeReady = library.runtime != nil || !library.bottles.isEmpty
        environmentReady = !library.bottles.isEmpty
        gameReady = !library.games.isEmpty
    }

    public var isComplete: Bool { runtimeReady && environmentReady && gameReady }
    public var completedSteps: Int {
        [runtimeReady, environmentReady, gameReady].filter { $0 }.count
    }
}
