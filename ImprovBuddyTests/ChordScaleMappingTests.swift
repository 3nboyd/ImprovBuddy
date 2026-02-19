import XCTest
@testable import ImprovBuddy

final class ChordScaleMappingTests: XCTestCase {
    func testDeterministicPrimaryMappingsForCoreChords() {
        let resolver = TheoryTestSupport.resolver()
        let context = TheoryContext.default

        let expected: [String: String] = [
            "maj7": "Ionian",
            "min7": "Dorian",
            "dom7": "Mixolydian",
            "dom7alt": "Altered",
            "m7b5": "Locrian"
        ]

        for (chordID, scaleName) in expected {
            let option = resolver.options(forChordID: chordID, context: context).first
            XCTAssertNotNil(option, chordID)
            XCTAssertEqual(option?.primaryScale.name, scaleName, chordID)
        }
    }

    func testTierFilteringIncludesExtendedWhenEnabled() {
        let resolver = TheoryTestSupport.resolver()

        var coreContext = TheoryContext.default
        coreContext.preferredTier = .core
        XCTAssertTrue(resolver.options(forChordID: "min6", context: coreContext).isEmpty)

        var extendedContext = TheoryContext.default
        extendedContext.preferredTier = .extended
        XCTAssertEqual(
            resolver.options(forChordID: "min6", context: extendedContext).first?.primaryScale.name,
            "Melodic Minor"
        )
    }

    func testFunctionFilterExcludesMismatchedRecommendations() {
        let resolver = TheoryTestSupport.resolver()
        let context = TheoryContext.default

        let dominantFiltered = resolver.options(
            forChordID: "dom7alt",
            context: context,
            functionFilter: .dominant
        )
        XCTAssertTrue(dominantFiltered.isEmpty)

        let alteredFiltered = resolver.options(
            forChordID: "dom7alt",
            context: context,
            functionFilter: .alteredDominant
        )
        XCTAssertEqual(alteredFiltered.first?.primaryScale.id, "altered")
    }
}
