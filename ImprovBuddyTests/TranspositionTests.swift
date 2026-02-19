import XCTest
@testable import ImprovBuddy

final class TranspositionTests: XCTestCase {
    private let notationEngine = TheoryNotationEngine()

    func testDisplayKeyOffsetsForInstrumentModes() {
        var context = TheoryContext.default
        context.concertKeyName = "C"

        context.instrument = .concert
        XCTAssertEqual(notationEngine.displayKey(from: context).name, "C")

        context.instrument = .bb
        XCTAssertEqual(notationEngine.displayKey(from: context).name, "D")

        context.instrument = .eb
        XCTAssertEqual(notationEngine.displayKey(from: context).name, "A")
    }

    func testBbInstrumentSpellsWrittenMajorScale() throws {
        guard let ionian = TheoryTestSupport.knowledgeBase().scalesByID["ionian"] else {
            throw XCTSkip("Missing ionian scale")
        }

        var context = TheoryContext.default
        context.concertKeyName = "C"
        context.instrument = .bb

        let names = notationEngine
            .spellScale(scale: ionian, context: context, rootPitchClass: 0)
            .map(\.name)

        XCTAssertEqual(names, ["D", "E", "F#", "G", "A", "B", "C#"])
    }

    func testEbInstrumentSpellsWrittenMajorScale() throws {
        guard let ionian = TheoryTestSupport.knowledgeBase().scalesByID["ionian"] else {
            throw XCTSkip("Missing ionian scale")
        }

        var context = TheoryContext.default
        context.concertKeyName = "C"
        context.instrument = .eb

        let names = notationEngine
            .spellScale(scale: ionian, context: context, rootPitchClass: 0)
            .map(\.name)

        XCTAssertEqual(names, ["A", "B", "C#", "D", "E", "F#", "G#"])
    }
}
