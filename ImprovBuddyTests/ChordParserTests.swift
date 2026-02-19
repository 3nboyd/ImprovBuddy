import XCTest
@testable import ImprovBuddy

final class ChordParserTests: XCTestCase {
    func testBasicMajorChord() {
        let chord = ChordParser.parse(symbol: "Cmaj7")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.rootPitchClass, 0)
        XCTAssertEqual(chord?.quality, .major)
        XCTAssertTrue(chord?.extensions.contains(7) == true)
    }

    func testMinorSevenFlatFive() {
        let chord = ChordParser.parse(symbol: "Bm7b5")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.rootPitchClass, 11)
        XCTAssertEqual(chord?.quality, .halfDiminished)
        XCTAssertTrue(chord?.alterations.contains(.flat5) == true)
    }

    func testSlashChord() {
        let chord = ChordParser.parse(symbol: "D/F#")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.rootPitchClass, 2)
        XCTAssertEqual(chord?.bassPitchClass, 6)
    }

    func testAlteredDominant() {
        let chord = ChordParser.parse(symbol: "G7b9#11")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.quality, .dominant)
        XCTAssertTrue(chord?.alterations.contains(.flat9) == true)
        XCTAssertTrue(chord?.alterations.contains(.sharp11) == true)
    }

    func testTextChartImport() {
        let chart = "Dm7 | G7\nCmaj7 | Cmaj7"
        let measures = ChordParser.parseTextChart(chart)
        XCTAssertEqual(measures.count, 4)
        XCTAssertEqual(measures[0].chordSymbol, "Dm7")
        XCTAssertEqual(measures[2].chordSymbol, "Cmaj7")
    }
}
