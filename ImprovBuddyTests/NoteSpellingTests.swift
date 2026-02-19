import XCTest
@testable import ImprovBuddy

final class NoteSpellingTests: XCTestCase {
    private let notationEngine = TheoryNotationEngine()

    func testIonianSpellingInFlatKeyUsesFlats() throws {
        let scale = try requireScale(id: "ionian")
        var context = TheoryContext.default
        context.concertKeyName = "Bb"
        context.instrument = .concert

        let notes = notationEngine.spellScale(
            scale: scale,
            context: context,
            rootPitchClass: 10
        )

        XCTAssertEqual(notes.map(\.name), ["Bb", "C", "D", "Eb", "F", "G", "A"])
    }

    func testGuideToneSpellingForDominantChord() {
        let chord = ChordParser.parse(symbol: "G7")!
        let guideToneNames = TheoryTestSupport.resolver().guideToneNames(chord: chord, context: .default)
        XCTAssertEqual(guideToneNames, ["B", "F"])
    }

    private func requireScale(id: String) throws -> TheoryScaleDefinition {
        guard let scale = TheoryTestSupport.knowledgeBase().scalesByID[id] else {
            throw XCTSkip("Missing scale \(id)")
        }
        return scale
    }
}
