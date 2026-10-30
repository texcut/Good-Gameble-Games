import Foundation
import Testing

@testable import GGGMacCore

@Test func newLibraryStartsWithNoSetupStepsComplete() {
    let state = SetupProgress(library: Library())
    #expect(state.completedSteps == 0)
    #expect(!state.isComplete)
}

@Test func runtimeOnlyLibraryStillNeedsEnvironmentAndGame() {
    var library = Library()
    library.runtime = WineRuntime(executable: URL(fileURLWithPath: "/fixture/wine"), version: "Fixture Wine")
    let state = SetupProgress(library: library)
    #expect(state.runtimeReady)
    #expect(!state.environmentReady)
    #expect(!state.gameReady)
    #expect(state.completedSteps == 1)
}

@Test func existingEnvironmentCountsItsOwnRuntimeWithoutADefault() {
    var library = Library()
    let runtime = WineRuntime(executable: URL(fileURLWithPath: "/fixture/wine"), version: "Fixture Wine")
    library.bottles = [Bottle(name: "Existing environment", runtime: runtime)]
    let state = SetupProgress(library: library)
    #expect(state.runtimeReady)
    #expect(state.environmentReady)
    #expect(!state.gameReady)
    #expect(state.completedSteps == 2)
    #expect(library.runtime == nil)
}

@Test func restoredLibraryOpensCompactAndRemovingLastEntryRestoresGuidance() throws {
    var library = Library()
    let runtime = WineRuntime(executable: URL(fileURLWithPath: "/fixture/wine"), version: "Fixture Wine")
    let bottle = Bottle(name: "Existing environment", runtime: runtime)
    library.bottles = [bottle]
    library.games = [
        Game(name: "Existing game", executable: URL(fileURLWithPath: "/fixture/game.exe"), bottleID: bottle.id)
    ]
    let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
    #expect(SetupProgress(library: restored).isComplete)
    #expect(SetupProgress(library: restored).completedSteps == 3)
    library.games.removeAll()
    #expect(!SetupProgress(library: library).isComplete)
    #expect(SetupProgress(library: library).completedSteps == 2)
}
