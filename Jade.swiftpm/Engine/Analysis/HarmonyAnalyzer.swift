import Foundation

struct HarmonyClassification {
    var state: HarmonyClass
    var pitchClass: Int
}

final class HarmonyAnalyzer {
    private struct OutsideCandidate {
        var time: TimeInterval
        var pitchClass: Int
    }

    private var counts: [HarmonyClass: Int] = [:]
    private var totalNotes = 0
    private var downbeatTotal = 0
    private var downbeatChordToneHits = 0
    private var rootHits = 0

    private var pendingOutside: [OutsideCandidate] = []
    private var resolvedOutsideCount = 0
    private var totalOutsideCount = 0

    private(set) var harmonyTimeline: [HarmonyTracePoint] = []

    func reset() {
        counts.removeAll(keepingCapacity: true)
        totalNotes = 0
        downbeatTotal = 0
        downbeatChordToneHits = 0
        rootHits = 0
        pendingOutside.removeAll(keepingCapacity: true)
        resolvedOutsideCount = 0
        totalOutsideCount = 0
        harmonyTimeline.removeAll(keepingCapacity: true)
    }

    func process(
        pitchEvent: PitchEvent,
        chord: Chord,
        nearestStrongBeatTime: TimeInterval?,
        strongBeatTolerance: TimeInterval = 0.08,
        allowedScalePitchClasses: Set<Int>? = nil
    ) -> HarmonyClassification {
        let pitchClass = Chord.normalizePitchClass(Int(round(pitchEvent.midiNote)) % 12)
        let chordTones = chord.chordTonePitchClasses()
        let extensionTones = chord.extensionPitchClasses()

        let state: HarmonyClass
        if chordTones.contains(pitchClass) {
            state = .chordTone
        } else if extensionTones.contains(pitchClass) || (allowedScalePitchClasses?.contains(pitchClass) ?? false) {
            state = .tension
        } else if minSemitoneDistance(from: pitchClass, toAnyOf: chordTones) <= 1 {
            state = .approach
        } else {
            state = .outside
        }

        totalNotes += 1
        counts[state, default: 0] += 1
        harmonyTimeline.append(HarmonyTracePoint(time: pitchEvent.time, state: state))

        if pitchClass == chord.rootPitchClass {
            rootHits += 1
        }

        if let nearestStrongBeatTime,
           abs(pitchEvent.time - nearestStrongBeatTime) <= strongBeatTolerance {
            downbeatTotal += 1
            if state == .chordTone {
                downbeatChordToneHits += 1
            }
        }

        if state == .outside {
            totalOutsideCount += 1
            pendingOutside.append(OutsideCandidate(time: pitchEvent.time, pitchClass: pitchClass))
        } else if state == .chordTone {
            resolvePendingOutside(with: pitchClass, at: pitchEvent.time)
        }

        return HarmonyClassification(state: state, pitchClass: pitchClass)
    }

    func summaryStats() -> HarmonyStats {
        let total = max(1, totalNotes)
        let chordTonePct = Double(counts[.chordTone, default: 0]) / Double(total)
        let extensionPct = Double(counts[.tension, default: 0]) / Double(total)
        let approachPct = Double(counts[.approach, default: 0]) / Double(total)
        let outsidePct = Double(counts[.outside, default: 0]) / Double(total)

        let downbeatPct = downbeatTotal == 0 ? 0 : Double(downbeatChordToneHits) / Double(downbeatTotal)
        let resolutionRate = totalOutsideCount == 0 ? 0 : Double(resolvedOutsideCount) / Double(totalOutsideCount)
        let rootOverusePct = Double(rootHits) / Double(total)

        return HarmonyStats(
            chordTonePct: chordTonePct,
            extensionPct: extensionPct,
            approachPct: approachPct,
            outsidePct: outsidePct,
            downbeatChordTonePct: downbeatPct,
            resolutionRate: resolutionRate,
            rootOverusePct: rootOverusePct
        )
    }

    private func resolvePendingOutside(with chordTonePitchClass: Int, at time: TimeInterval) {
        guard !pendingOutside.isEmpty else { return }

        var survivors: [OutsideCandidate] = []
        for item in pendingOutside {
            let delta = time - item.time
            if delta < 0.3 {
                survivors.append(item)
                continue
            }
            if delta > 1.0 {
                continue
            }

            let semitoneDistance = minSemitoneDistance(from: item.pitchClass, to: chordTonePitchClass)
            if semitoneDistance <= 2 {
                resolvedOutsideCount += 1
            } else {
                survivors.append(item)
            }
        }

        pendingOutside = survivors
    }

    private func minSemitoneDistance(from source: Int, toAnyOf targets: Set<Int>) -> Int {
        guard !targets.isEmpty else { return 12 }
        return targets.map { minSemitoneDistance(from: source, to: $0) }.min() ?? 12
    }

    private func minSemitoneDistance(from a: Int, to b: Int) -> Int {
        let diff = abs(a - b)
        return min(diff, 12 - diff)
    }
}
