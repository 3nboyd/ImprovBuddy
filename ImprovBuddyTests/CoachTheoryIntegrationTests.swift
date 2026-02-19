import XCTest
@testable import ImprovBuddy

final class CoachTheoryIntegrationTests: XCTestCase {
    func testScaleAwareClassificationDiffersFromNonScaleAware() {
        let resolver = TheoryTestSupport.resolver()
        let chord = ChordParser.parse(symbol: "G7")!
        let event = PitchEvent(time: 1.0, midiNote: 69, confidence: 1.0, source: .midi) // A natural

        let nonScaleAwareAnalyzer = HarmonyAnalyzer()
        let nonScaleAware = nonScaleAwareAnalyzer.process(
            pitchEvent: event,
            chord: chord,
            nearestStrongBeatTime: nil,
            allowedScalePitchClasses: nil
        )
        XCTAssertEqual(nonScaleAware.state, .outside)

        let allowedScalePitchClasses = resolver.pitchClassesForPrimaryScale(chord: chord, context: .default)
        let scaleAwareAnalyzer = HarmonyAnalyzer()
        let scaleAware = scaleAwareAnalyzer.process(
            pitchEvent: event,
            chord: chord,
            nearestStrongBeatTime: nil,
            allowedScalePitchClasses: allowedScalePitchClasses
        )
        XCTAssertEqual(scaleAware.state, .tension)
    }

    func testRecommendationTextReflectsTheoryTargets() {
        let resolver = TheoryTestSupport.resolver()
        let chord = ChordParser.parse(symbol: "G7")!
        let text = resolver.recommendationText(chord: chord, context: .default)

        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("B") == true, text ?? "")
        XCTAssertTrue(text?.contains("F") == true, text ?? "")
    }

    func testScaleAwarenessCanBeDisabledInContext() {
        let resolver = TheoryTestSupport.resolver()
        let chord = ChordParser.parse(symbol: "G7")!
        var context = TheoryContext.default
        context.scoringUsesScaleAwareness = false

        XCTAssertTrue(resolver.pitchClassesForPrimaryScale(chord: chord, context: context).isEmpty)
    }
}
