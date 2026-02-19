import XCTest
@testable import ImprovBuddy

final class StaffMappingTests: XCTestCase {
    private let notationEngine = TheoryNotationEngine()

    func testMiddleCMapsPerClefAnchor() {
        let context = TheoryContext.default
        let middleC = notationEngine.spellIntervals(
            intervals: [0],
            degreeSteps: [0],
            context: context,
            rootPitchClass: 0
        )

        XCTAssertEqual(notationEngine.toStaffNotes(middleC, clef: .treble).first?.staffStep, -6)
        XCTAssertEqual(notationEngine.toStaffNotes(middleC, clef: .alto).first?.staffStep, 0)
        XCTAssertEqual(notationEngine.toStaffNotes(middleC, clef: .bass).first?.staffStep, 6)
    }

    func testStaffStepsIncreaseWithAscendingScale() throws {
        guard let ionian = TheoryTestSupport.knowledgeBase().scalesByID["ionian"] else {
            throw XCTSkip("Missing ionian scale")
        }

        let notes = notationEngine.spellScale(
            scale: ionian,
            context: .default,
            rootPitchClass: 0
        )
        let staff = notationEngine.toStaffNotes(notes, clef: .treble)
        let steps = staff.map(\.staffStep)

        for index in 1..<steps.count {
            XCTAssertGreaterThan(steps[index], steps[index - 1])
        }
    }
}
