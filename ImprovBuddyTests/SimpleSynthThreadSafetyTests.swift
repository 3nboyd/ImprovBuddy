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

final class TunerTemperamentTests: XCTestCase {
    func testEqualTemperamentOffsetIsZero() {
        for pitchClass in 0..<12 {
            XCTAssertEqual(
                TunerEngine.temperamentOffset(temperament: .equal, relativePitchClass: pitchClass),
                0,
                accuracy: 0.0001
            )
        }
    }

    func testJustTemperamentContainsExpectedMajorThirdOffset() {
        let offset = TunerEngine.temperamentOffset(temperament: .just, relativePitchClass: 4)
        XCTAssertEqual(offset, -13.69, accuracy: 0.05)
    }

    func testPythagoreanTemperamentContainsExpectedTritoneOffset() {
        let offset = TunerEngine.temperamentOffset(temperament: .pythagorean, relativePitchClass: 6)
        XCTAssertEqual(offset, 11.73, accuracy: 0.05)
    }

    func testA4OffsetIsZeroAt440() {
        XCTAssertEqual(TunerEngine.a4SemitoneOffset(referenceHz: 440), 0, accuracy: 0.000001)
    }
}

final class TunerSensitivityTests: XCTestCase {
    func testToneLatchMarginShrinksWithHigherSensitivity() {
        let low = TunerEngine.toneLatchSemitoneMargin(for: 0)
        let medium = TunerEngine.toneLatchSemitoneMargin(for: 0.5)
        let high = TunerEngine.toneLatchSemitoneMargin(for: 1)

        XCTAssertGreaterThan(low, medium)
        XCTAssertGreaterThan(medium, high)
    }
}

final class GroovePatternGeneratorTests: XCTestCase {
    func testGeneratesPatternForOddMeterInEighths() {
        let generator = GroovePatternGenerator()
        let pattern = generator.generate(
            style: .funk,
            meter: MeterSignature(top: 7, bottom: 8),
            subdivision: .eighth,
            intensity: 0.7
        )

        XCTAssertEqual(pattern.stepsPerBar, 14)
        XCTAssertFalse(pattern.events.isEmpty)
        XCTAssertTrue(pattern.events.contains(where: { $0.voice == .kick }))
        XCTAssertTrue(pattern.events.contains(where: { $0.voice == .snare }))
        XCTAssertTrue(pattern.events.contains(where: { $0.voice == .hihat }))
    }
}

@MainActor
final class MetronomeSchedulerTests: XCTestCase {
    func testApplySettingsAndExportRoundTrip() {
        let engine = MetronomeEngine(enableAudioIO: false)
        let settings = MetronomeSettings(
            bpm: 153,
            meter: MeterSignature(top: 13, bottom: 8),
            subdivision: .triplet,
            countInBars: 2,
            soundSet: .rim,
            masterVolume: 0.7,
            swingAmount: 0.4,
            grooveEnabled: true,
            grooveStyle: .funk,
            grooveIntensity: 0.9,
            humanizeMs: 8,
            hapticsEnabled: true
        )

        engine.apply(settings: settings)
        let exported = engine.exportSettings()

        XCTAssertEqual(exported.bpm, 153, accuracy: 0.0001)
        XCTAssertEqual(exported.meter, MeterSignature(top: 13, bottom: 8))
        XCTAssertEqual(exported.subdivision, .triplet)
        XCTAssertEqual(exported.countInBars, 2)
        XCTAssertEqual(exported.soundSet, .rim)
        XCTAssertEqual(exported.masterVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(exported.swingAmount, 0.4, accuracy: 0.0001)
        XCTAssertTrue(exported.grooveEnabled)
        XCTAssertEqual(exported.grooveStyle, .funk)
        XCTAssertEqual(exported.grooveIntensity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(exported.humanizeMs, 8, accuracy: 0.0001)
        XCTAssertTrue(exported.hapticsEnabled)
    }

    func testRepeatedStartStopKeepsEngineStable() async {
        let engine = MetronomeEngine(enableAudioIO: false)
        engine.apply(
            settings: MetronomeSettings(
                bpm: 120,
                meter: MeterSignature(top: 4, bottom: 4),
                subdivision: .eighth,
                countInBars: 0,
                soundSet: .woodblock,
                masterVolume: 0.6,
                swingAmount: 0,
                grooveEnabled: false,
                grooveStyle: .rock,
                grooveIntensity: 0.5,
                humanizeMs: 0,
                hapticsEnabled: false
            )
        )

        for _ in 0..<3 {
            engine.start()
            try? await Task.sleep(nanoseconds: 30_000_000)
            engine.stop()
            XCTAssertFalse(engine.isRunning)
        }
    }

    func testAudioRenderCallbackIsolationDoesNotCrash() async throws {
        let engine = MetronomeEngine(enableAudioIO: true)
        engine.apply(
            settings: MetronomeSettings(
                bpm: 120,
                meter: MeterSignature(top: 4, bottom: 4),
                subdivision: .eighth,
                countInBars: 0,
                soundSet: .woodblock,
                masterVolume: 0.25,
                swingAmount: 0,
                grooveEnabled: false,
                grooveStyle: .rock,
                grooveIntensity: 0.5,
                humanizeMs: 0,
                hapticsEnabled: false
            )
        )

        engine.start()
        guard engine.isRunning else {
            throw XCTSkip("Simulator audio engine unavailable in this environment.")
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertGreaterThan(engine.currentStep, 0, "Metronome should schedule steps while running.")
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func testAllSoundSetsStartAndAdvanceWithoutCrashing() async throws {
        let engine = MetronomeEngine(enableAudioIO: true)

        for soundSet in MetronomeSoundSet.allCases {
            engine.apply(
                settings: MetronomeSettings(
                    bpm: 110,
                    meter: MeterSignature(top: 4, bottom: 4),
                    subdivision: .quarter,
                    countInBars: 0,
                    soundSet: soundSet,
                    masterVolume: 0.3,
                    swingAmount: 0,
                    grooveEnabled: false,
                    grooveStyle: .rock,
                    grooveIntensity: 0.5,
                    humanizeMs: 0,
                    hapticsEnabled: false
                )
            )

            engine.start()
            guard engine.isRunning else {
                throw XCTSkip("Simulator audio engine unavailable in this environment.")
            }

            try? await Task.sleep(nanoseconds: 90_000_000)
            XCTAssertGreaterThan(engine.currentStep, 0, "Expected scheduler progress for \(soundSet.displayName).")

            engine.stop()
            XCTAssertFalse(engine.isRunning)
        }
    }
}

@MainActor
final class LiveTempoAnalyzerTests: XCTestCase {
    func testMidiPriorityDedupeDropsNearMicOnset() {
        let bus = UnifiedEventBus()
        let analyzer = LiveTempoAnalyzerEngine(eventBus: bus)

        analyzer.inputMode = .both
        analyzer.targetBPM = 120
        analyzer.start()

        let base = ProcessInfo.processInfo.systemUptime
        bus.publish(onset: OnsetEvent(time: base + 0.5, confidence: 1, source: .midi))
        bus.publish(onset: OnsetEvent(time: base + 0.58, confidence: 1, source: .mic))

        let expectation = expectation(description: "Onset processed on main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(analyzer.onsetCount, 1)
        XCTAssertEqual(analyzer.lastOnsetSource, .midi)
    }
}

@MainActor
final class ToolsSettingsPersistenceTests: XCTestCase {
    func testPersistAndReloadSettings() {
        let suiteName = "ToolsSettingsPersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected test user defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)

        let first = ToolsSettingsStore(defaults: defaults)
        first.tuner = TunerSettings(
            a4Hz: 442,
            temperament: .pythagorean,
            temperamentRootPitchClass: 9,
            toneChangeSensitivity: 0.8,
            confidenceGate: 0.62
        )

        first.metronome = MetronomeSettings(
            bpm: 145,
            meter: MeterSignature(top: 11, bottom: 8),
            subdivision: .triplet,
            countInBars: 2,
            soundSet: .hihat,
            masterVolume: 0.64,
            swingAmount: 0.25,
            grooveEnabled: true,
            grooveStyle: .swing,
            grooveIntensity: 0.77,
            humanizeMs: 6,
            hapticsEnabled: true
        )

        let second = ToolsSettingsStore(defaults: defaults)
        XCTAssertEqual(second.tuner, first.tuner)
        XCTAssertEqual(second.metronome, first.metronome)
    }
}

@MainActor
final class SongsTagFilteringTests: XCTestCase {
    func testSongTagNormalizationAndMutationHelpers() {
        let song = Song(
            title: "Autumn Leaves",
            composer: "Kosma",
            styleTags: [" Swing ", "bebop", "swing"],
            defaultTempoBPM: 140,
            feel: .swing,
            timeSignatureTop: 4,
            timeSignatureBottom: 4,
            form: [Measure(index: 0, sectionLabel: "A", chordSymbol: "Cm7")]
        )

        XCTAssertEqual(song.tags, ["swing", "bebop"])
        XCTAssertTrue(song.hasTag("SWING"))

        song.addTag(" latin ")
        XCTAssertTrue(song.hasTag("latin"))

        song.renameTag(from: "bebop", to: "hard bop")
        XCTAssertFalse(song.hasTag("bebop"))
        XCTAssertTrue(song.hasTag("hard bop"))

        song.renameTag(from: "hard bop", to: "")
        XCTAssertFalse(song.hasTag("hard bop"))

        song.removeTag("latin")
        XCTAssertFalse(song.hasTag("latin"))
    }
}

final class PDFSongMetadataExtractorTests: XCTestCase {
    func testUsesDocumentMetadataWhenPresent() {
        let metadata = PDFSongMetadataExtractor.extract(
            documentMetadataTitle: "Blue Bossa",
            documentMetadataAuthor: "Kenny Dorham",
            firstPageText: nil,
            fileName: "ignored"
        )

        XCTAssertEqual(metadata.source, .documentAttributes)
        XCTAssertEqual(metadata.title, "Blue Bossa")
        XCTAssertEqual(metadata.author, "Kenny Dorham")
        XCTAssertGreaterThan(metadata.confidence, 0.9)
    }

    func testFallsBackToFirstPageHeuristic() {
        let metadata = PDFSongMetadataExtractor.extract(
            documentMetadataTitle: nil,
            documentMetadataAuthor: nil,
            firstPageText: "Stella By Starlight\nBy Victor Young\nLead Sheet",
            fileName: "stella"
        )

        XCTAssertEqual(metadata.source, .firstPageHeuristic)
        XCTAssertEqual(metadata.title, "Stella By Starlight")
        XCTAssertEqual(metadata.author, "Victor Young")
    }

    func testFallsBackToFilenameWhenNoMetadataOrText() {
        let metadata = PDFSongMetadataExtractor.extract(
            documentMetadataTitle: nil,
            documentMetadataAuthor: nil,
            firstPageText: nil,
            fileName: "all_the-things_you_are"
        )

        XCTAssertEqual(metadata.source, .fileNameFallback)
        XCTAssertEqual(metadata.title, "all the things you are")
        XCTAssertNil(metadata.author)
    }
}

@MainActor
final class GlobalToolOverlayStateTests: XCTestCase {
    func testOverlayPreferencePersistenceRoundTrip() {
        let suiteName = "GlobalToolOverlayStateTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected dedicated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = ToolOverlayPreferencesStore(defaults: defaults)
        first.tuner = ToolOverlayPreferences(
            corner: .bottomRight,
            offsetX: 12,
            offsetY: -9,
            isExpanded: true,
            isVisible: true
        )
        first.bpm = ToolOverlayPreferences(
            corner: .topLeft,
            offsetX: -4,
            offsetY: 6,
            isExpanded: false,
            isVisible: false
        )

        let second = ToolOverlayPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.tuner.corner, .bottomRight)
        XCTAssertEqual(second.tuner.offsetX, 12, accuracy: 0.0001)
        XCTAssertEqual(second.tuner.offsetY, -9, accuracy: 0.0001)
        XCTAssertTrue(second.tuner.isExpanded)
        XCTAssertTrue(second.tuner.isVisible)

        XCTAssertEqual(second.bpm.corner, .topLeft)
        XCTAssertEqual(second.bpm.offsetX, -4, accuracy: 0.0001)
        XCTAssertEqual(second.bpm.offsetY, 6, accuracy: 0.0001)
        XCTAssertFalse(second.bpm.isVisible)
    }
}

@MainActor
final class RecorderMetronomeReferenceTests: XCTestCase {
    func testCaptureStoresCurrentMetronomeState() {
        let metronome = MetronomeEngine(enableAudioIO: false)
        metronome.apply(
            settings: MetronomeSettings(
                bpm: 173,
                meter: MeterSignature(top: 7, bottom: 8),
                subdivision: .triplet,
                countInBars: 1,
                soundSet: .woodblock,
                masterVolume: 0.4,
                swingAmount: 0.1,
                grooveEnabled: false,
                grooveStyle: .rock,
                grooveIntensity: 0.5,
                humanizeMs: 0,
                hapticsEnabled: false
            )
        )
        metronome.start()

        let recorder = IdeaRecorderEngine()
        recorder.captureMetronomeReference(from: metronome)

        let reference = recorder.lastMetronomeReference
        XCTAssertNotNil(reference)
        XCTAssertEqual(reference?.bpm ?? 0, 173, accuracy: 0.0001)
        XCTAssertEqual(reference?.meterTop, 7)
        XCTAssertEqual(reference?.meterBottom, 8)
        XCTAssertEqual(reference?.subdivision, .triplet)
        XCTAssertTrue(reference?.metronomeRunningAtStart ?? false)
        XCTAssertNotNil(reference?.startUptime)

        metronome.stop()
    }
}
