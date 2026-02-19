import XCTest
@testable import ImprovBuddy

final class HarmonyAnalyzerTests: XCTestCase {
    func testChordToneClassification() {
        let analyzer = HarmonyAnalyzer()
        let chord = ChordParser.parse(symbol: "Cmaj7")!

        let event = PitchEvent(time: 1.0, midiNote: 60, confidence: 1.0, source: .midi)
        let result = analyzer.process(pitchEvent: event, chord: chord, nearestStrongBeatTime: 1.0)

        XCTAssertEqual(result.state, .chordTone)
        XCTAssertEqual(analyzer.summaryStats().downbeatChordTonePct, 1.0)
    }

    func testExtensionClassification() {
        let analyzer = HarmonyAnalyzer()
        let chord = ChordParser.parse(symbol: "Cmaj9")!

        let event = PitchEvent(time: 1.2, midiNote: 62, confidence: 1.0, source: .midi)
        let result = analyzer.process(pitchEvent: event, chord: chord, nearestStrongBeatTime: nil)

        XCTAssertEqual(result.state, .tension)
    }

    func testOutsideAndResolutionTracking() {
        let analyzer = HarmonyAnalyzer()
        let chord = ChordParser.parse(symbol: "Cmaj7")!

        let outside = PitchEvent(time: 1.0, midiNote: 69, confidence: 1.0, source: .midi) // A
        _ = analyzer.process(pitchEvent: outside, chord: chord, nearestStrongBeatTime: nil)

        let resolve = PitchEvent(time: 1.45, midiNote: 67, confidence: 1.0, source: .midi) // G
        _ = analyzer.process(pitchEvent: resolve, chord: chord, nearestStrongBeatTime: nil)

        let stats = analyzer.summaryStats()
        XCTAssertGreaterThan(stats.resolutionRate, 0)
    }
}
