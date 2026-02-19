import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID
    var songID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var inputMode: InputMode
    var targetTempoBPM: Double
    var feel: FeelType
    var timeSignatureTop: Int
    var timeSignatureBottom: Int
    var audioFilePath: String?

    var onsetTimesData: Data = Data()
    var estimatedBPMOverTimeData: Data = Data()
    var timingErrorOverTimeMsData: Data = Data()
    var swingRatioOverTimeData: Data = Data()
    var detectedPitchOverTimeData: Data = Data()
    var chordMatchStateOverTimeData: Data = Data()
    var summaryData: Data = Data()
    var theoryContextData: Data = Data()

    var onsetTimes: [TimeInterval] {
        get { CodableBlob.decode([TimeInterval].self, from: onsetTimesData, default: []) }
        set { onsetTimesData = CodableBlob.encode(newValue) }
    }

    var estimatedBPMOverTime: [TimeValuePair] {
        get { CodableBlob.decode([TimeValuePair].self, from: estimatedBPMOverTimeData, default: []) }
        set { estimatedBPMOverTimeData = CodableBlob.encode(newValue) }
    }

    var timingErrorOverTimeMs: [TimeValuePair] {
        get { CodableBlob.decode([TimeValuePair].self, from: timingErrorOverTimeMsData, default: []) }
        set { timingErrorOverTimeMsData = CodableBlob.encode(newValue) }
    }

    var swingRatioOverTime: [TimeValuePair] {
        get { CodableBlob.decode([TimeValuePair].self, from: swingRatioOverTimeData, default: []) }
        set { swingRatioOverTimeData = CodableBlob.encode(newValue) }
    }

    var detectedPitchOverTime: [PitchTracePoint] {
        get { CodableBlob.decode([PitchTracePoint].self, from: detectedPitchOverTimeData, default: []) }
        set { detectedPitchOverTimeData = CodableBlob.encode(newValue) }
    }

    var chordMatchStateOverTime: [HarmonyTracePoint] {
        get { CodableBlob.decode([HarmonyTracePoint].self, from: chordMatchStateOverTimeData, default: []) }
        set { chordMatchStateOverTimeData = CodableBlob.encode(newValue) }
    }

    var summary: SessionSummaryMetrics {
        get { CodableBlob.decode(SessionSummaryMetrics.self, from: summaryData, default: .empty) }
        set { summaryData = CodableBlob.encode(newValue) }
    }

    var theoryContext: TheoryContext {
        get { CodableBlob.decode(TheoryContext.self, from: theoryContextData, default: .default) }
        set { theoryContextData = CodableBlob.encode(newValue) }
    }

    init(
        id: UUID = UUID(),
        songID: UUID? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        inputMode: InputMode,
        targetTempoBPM: Double,
        feel: FeelType,
        timeSignatureTop: Int,
        timeSignatureBottom: Int,
        audioFilePath: String? = nil,
        onsetTimes: [TimeInterval] = [],
        estimatedBPMOverTime: [TimeValuePair] = [],
        timingErrorOverTimeMs: [TimeValuePair] = [],
        swingRatioOverTime: [TimeValuePair] = [],
        detectedPitchOverTime: [PitchTracePoint] = [],
        chordMatchStateOverTime: [HarmonyTracePoint] = [],
        summary: SessionSummaryMetrics = .empty,
        theoryContext: TheoryContext = .default
    ) {
        self.id = id
        self.songID = songID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.inputMode = inputMode
        self.targetTempoBPM = targetTempoBPM
        self.feel = feel
        self.timeSignatureTop = timeSignatureTop
        self.timeSignatureBottom = timeSignatureBottom
        self.audioFilePath = audioFilePath

        self.onsetTimesData = CodableBlob.encode(onsetTimes)
        self.estimatedBPMOverTimeData = CodableBlob.encode(estimatedBPMOverTime)
        self.timingErrorOverTimeMsData = CodableBlob.encode(timingErrorOverTimeMs)
        self.swingRatioOverTimeData = CodableBlob.encode(swingRatioOverTime)
        self.detectedPitchOverTimeData = CodableBlob.encode(detectedPitchOverTime)
        self.chordMatchStateOverTimeData = CodableBlob.encode(chordMatchStateOverTime)
        self.summaryData = CodableBlob.encode(summary)
        self.theoryContextData = CodableBlob.encode(theoryContext)
    }
}
