import XCTest
@testable import ImprovBuddy

final class SimpleSynthThreadSafetyTests: XCTestCase {
    func testRepeatedSynthLifecycleAndPlaybackCallsDoNotCrash() {
        for _ in 0..<10 {
            let synth = SimpleSynth()
            synth.play(frequency: 440, amplitude: 0.2)
            synth.playMIDINotes([60, 64, 67], noteDuration: 0.01)
            synth.stopTone()
        }
    }
}
