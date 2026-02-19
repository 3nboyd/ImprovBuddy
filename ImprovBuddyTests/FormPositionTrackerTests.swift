import XCTest
@testable import ImprovBuddy

final class FormPositionTrackerTests: XCTestCase {
    private func makeTracker() -> FormPositionTracker {
        let measures = [
            Measure(index: 0, sectionLabel: "A", chordSymbol: "Cmaj7"),
            Measure(index: 1, sectionLabel: "A", chordSymbol: "Dm7"),
            Measure(index: 2, sectionLabel: "B", chordSymbol: "G7"),
            Measure(index: 3, sectionLabel: "B", chordSymbol: "Cmaj7")
        ]
        return FormPositionTracker(measures: measures, timeSignatureTop: 4, targetBPM: 120)
    }

    func testAutoAdvanceMeasureIndex() {
        let tracker = makeTracker()

        // 120 BPM, 4/4 => 2 sec per measure
        XCTAssertEqual(tracker.currentPosition(at: 0.1).measureIndex, 0)
        XCTAssertEqual(tracker.currentPosition(at: 2.1).measureIndex, 1)
        XCTAssertEqual(tracker.currentPosition(at: 4.1).measureIndex, 2)
        XCTAssertEqual(tracker.currentPosition(at: 8.2).measureIndex, 0)
    }

    func testJumpToBar() {
        let tracker = makeTracker()
        tracker.jumpToBar(3, at: 4.0)

        let position = tracker.currentPosition(at: 4.0)
        XCTAssertEqual(position.measureIndex, 2)
    }

    func testRestartChorus() {
        let tracker = makeTracker()
        tracker.restartChorus(at: 6.5)

        let position = tracker.currentPosition(at: 6.5)
        XCTAssertEqual(position.measureIndex, 0)
    }
}
