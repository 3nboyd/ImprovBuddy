import Foundation

struct TheoryNotationEngine {
    private let letters = ["C", "D", "E", "F", "G", "A", "B"]
    private let naturalPitchClassByLetter: [String: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
    ]

    func displayKey(from context: TheoryContext) -> TheoryKey {
        let base = context.concertKey.rootPitchClass + context.instrument.writtenSemitoneOffset
        let prefersSharps = context.concertKeyName.contains("#")
        return TheoryKey.byPitchClass(base, preferSharps: prefersSharps)
    }

    func spellScale(
        scale: TheoryScaleDefinition,
        context: TheoryContext,
        rootPitchClass: Int,
        startingOctave: Int = 4
    ) -> [SpelledNote] {
        spell(
            intervals: scale.intervals,
            degreeSteps: scale.degreeSteps,
            context: context,
            rootPitchClass: rootPitchClass,
            startingOctave: startingOctave
        )
    }

    func spellArpeggio(
        arpeggio: TheoryArpeggioDefinition,
        context: TheoryContext,
        rootPitchClass: Int,
        startingOctave: Int = 4
    ) -> [SpelledNote] {
        spell(
            intervals: arpeggio.intervals,
            degreeSteps: arpeggio.degreeSteps,
            context: context,
            rootPitchClass: rootPitchClass,
            startingOctave: startingOctave
        )
    }

    func spellIntervals(
        intervals: [Int],
        degreeSteps: [Int],
        context: TheoryContext,
        rootPitchClass: Int,
        startingOctave: Int = 4
    ) -> [SpelledNote] {
        spell(
            intervals: intervals,
            degreeSteps: degreeSteps,
            context: context,
            rootPitchClass: rootPitchClass,
            startingOctave: startingOctave
        )
    }

    func toStaffNotes(_ notes: [SpelledNote], clef: TheoryClef) -> [StaffRenderedNote] {
        notes.map { note in
            StaffRenderedNote(
                spelled: note,
                staffStep: staffStep(for: note, clef: clef)
            )
        }
    }

    private func spell(
        intervals: [Int],
        degreeSteps: [Int],
        context: TheoryContext,
        rootPitchClass: Int,
        startingOctave: Int
    ) -> [SpelledNote] {
        guard !intervals.isEmpty else { return [] }

        let transposedRootPC = Chord.normalizePitchClass(rootPitchClass + context.instrument.writtenSemitoneOffset)
        let display = displayKey(from: context)
        guard let rootLetterIndex = letters.firstIndex(of: display.rootLetter) else {
            return []
        }

        let normalizedSteps: [Int] = degreeSteps.count == intervals.count
            ? degreeSteps
            : Array(0..<intervals.count)

        let spelled = intervals.enumerated().map { index, interval in
            let degreeStep = normalizedSteps[index]
            let letterIndex = (rootLetterIndex + degreeStep) % letters.count
            let letter = letters[letterIndex]
            let octaveShift = (rootLetterIndex + degreeStep) / letters.count
            let naturalPC = naturalPitchClassByLetter[letter] ?? 0
            let targetPC = Chord.normalizePitchClass(transposedRootPC + interval)
            let accidentalInt = accidentalDistance(from: naturalPC, to: targetPC)
            let accidental = accidentalString(accidentalInt)

            // Keep notes around a practical register for the chosen clef.
            let midi = 12 * (startingOctave + octaveShift + 1) + targetPC
            let noteName = "\(letter)\(accidental)"
            return SpelledNote(name: noteName, midi: midi, pitchClass: targetPC, accidental: accidental)
        }

        return rebalanceOctaveForClef(spelled, clef: context.clef)
    }

    private func rebalanceOctaveForClef(_ notes: [SpelledNote], clef: TheoryClef) -> [SpelledNote] {
        guard !notes.isEmpty else { return notes }

        var adjusted = notes
        var attempts = 0

        while attempts < 6 {
            let steps = adjusted.map { staffStep(for: $0, clef: clef) }
            guard let minStep = steps.min(), let maxStep = steps.max() else {
                break
            }

            if maxStep > 8 {
                adjusted = adjusted.map {
                    SpelledNote(
                        name: $0.name,
                        midi: $0.midi - 12,
                        pitchClass: $0.pitchClass,
                        accidental: $0.accidental
                    )
                }
                attempts += 1
                continue
            }

            if minStep < -8 {
                adjusted = adjusted.map {
                    SpelledNote(
                        name: $0.name,
                        midi: $0.midi + 12,
                        pitchClass: $0.pitchClass,
                        accidental: $0.accidental
                    )
                }
                attempts += 1
                continue
            }

            break
        }

        return adjusted
    }

    private func accidentalDistance(from naturalPC: Int, to targetPC: Int) -> Int {
        var diff = targetPC - naturalPC
        while diff <= -6 { diff += 12 }
        while diff > 6 { diff -= 12 }

        if diff < -2 { return -2 }
        if diff > 2 { return 2 }
        return diff
    }

    private func accidentalString(_ value: Int) -> String {
        switch value {
        case -2: return "bb"
        case -1: return "b"
        case 0: return ""
        case 1: return "#"
        case 2: return "##"
        default: return ""
        }
    }

    private func staffStep(for note: SpelledNote, clef: TheoryClef) -> Int {
        let centerName: String
        switch clef {
        case .treble:
            centerName = "B4"
        case .alto:
            centerName = "C4"
        case .bass:
            centerName = "D3"
        }

        let noteStep = diatonicStep(of: note.name, midi: note.midi)
        let centerStep = diatonicStep(of: centerName, midi: midiValue(from: centerName))
        return noteStep - centerStep
    }

    private func diatonicStep(of noteName: String, midi: Int) -> Int {
        guard let first = noteName.first else { return 0 }
        let letter = String(first)
        let letterIndex = letters.firstIndex(of: letter) ?? 0
        let octave = (midi / 12) - 1
        return octave * 7 + letterIndex
    }

    private func midiValue(from note: String) -> Int {
        guard let first = note.first else { return 60 }
        let letter = String(first)
        let octave = Int(String(note.suffix(1))) ?? 4
        let basePC = naturalPitchClassByLetter[letter] ?? 0
        return 12 * (octave + 1) + basePC
    }
}
