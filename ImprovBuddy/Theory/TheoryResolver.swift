import Foundation

final class TheoryResolver {
    let knowledgeBase: TheoryKnowledgeBase
    let notationEngine = TheoryNotationEngine()

    init(knowledgeBase: TheoryKnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    func options(
        for chord: Chord,
        context: TheoryContext,
        functionFilter: TheoryFunctionTag? = nil,
        sortMode: TheorySortMode = .relevance
    ) -> [TheoryResolvedOption] {
        guard let chordID = knowledgeBase.chordID(for: chord) else { return [] }
        return options(forChordID: chordID, context: context, functionFilter: functionFilter, sortMode: sortMode)
    }

    func options(
        forChordID chordID: String,
        context: TheoryContext,
        functionFilter: TheoryFunctionTag? = nil,
        sortMode: TheorySortMode = .relevance
    ) -> [TheoryResolvedOption] {
        guard let chordDefinition = knowledgeBase.chordDefinition(id: chordID) else { return [] }

        let tierOrder: [TheoryTier: Int] = [.core: 0, .extended: 1, .advanced: 2]
        let targetTierRank = tierOrder[context.preferredTier, default: 0]

        let recs = knowledgeBase
            .recommendations(chordID: chordID)
            .filter { tierOrder[$0.tier, default: 0] <= targetTierRank }
            .filter { functionFilter == nil || $0.functionTag == functionFilter }

        let resolved: [TheoryResolvedOption] = recs.compactMap { rec in
            guard let primaryScale = knowledgeBase.scalesByID[rec.primaryScaleID] else { return nil }
            let alternatives = rec.alternativeScaleIDs.compactMap { knowledgeBase.scalesByID[$0] }
            let arpeggios = rec.arpeggioIDs.compactMap { knowledgeBase.arpeggiosByID[$0] }
            let guideTone = rec.guideToneRuleID.flatMap { knowledgeBase.guideToneRulesByID[$0] }
            let avoidTones = rec.avoidToneRuleIDs.compactMap { knowledgeBase.avoidToneRulesByID[$0] }
            let voiceLeading = rec.voiceLeadingRuleIDs.compactMap { knowledgeBase.voiceLeadingRulesByID[$0] }
            return TheoryResolvedOption(
                recommendation: rec,
                chord: chordDefinition,
                primaryScale: primaryScale,
                alternatives: alternatives,
                arpeggios: arpeggios,
                guideToneRule: guideTone,
                avoidToneRules: avoidTones,
                voiceLeadingRules: voiceLeading
            )
        }

        return sort(options: resolved, mode: sortMode)
    }

    func availableChordDefinitions(
        tier: TheoryTier,
        functionFilter: TheoryFunctionTag? = nil,
        familyFilter: String? = nil
    ) -> [TheoryChordDefinition] {
        let tierOrder: [TheoryTier: Int] = [.core: 0, .extended: 1, .advanced: 2]
        let targetTierRank = tierOrder[tier, default: 0]

        return knowledgeBase.chordsByID.values
            .filter { tierOrder[$0.tier, default: 0] <= targetTierRank }
            .filter { functionFilter == nil || !$0.functionHints.filter { $0 == functionFilter! }.isEmpty }
            .filter { familyFilter == nil || familyFilter == "All" || $0.family == familyFilter }
            .sorted { $0.name < $1.name }
    }

    func availableFamilies() -> [String] {
        let names = Set(knowledgeBase.chordsByID.values.map(\.family))
        return ["All"] + names.sorted()
    }

    func noteNames(
        for scale: TheoryScaleDefinition,
        rootPitchClass: Int,
        context: TheoryContext
    ) -> [String] {
        notationEngine
            .spellScale(scale: scale, context: context, rootPitchClass: rootPitchClass)
            .map(\.name)
    }

    func renderedScaleNotes(
        scale: TheoryScaleDefinition,
        rootPitchClass: Int,
        context: TheoryContext
    ) -> [StaffRenderedNote] {
        let spelled = notationEngine.spellScale(
            scale: scale,
            context: context,
            rootPitchClass: rootPitchClass
        )
        return notationEngine.toStaffNotes(spelled, clef: context.clef)
    }

    func renderedArpeggioNotes(
        arpeggio: TheoryArpeggioDefinition,
        rootPitchClass: Int,
        context: TheoryContext
    ) -> [StaffRenderedNote] {
        let spelled = notationEngine.spellArpeggio(
            arpeggio: arpeggio,
            context: context,
            rootPitchClass: rootPitchClass
        )
        return notationEngine.toStaffNotes(spelled, clef: context.clef)
    }

    func pitchClassesForPrimaryScale(
        chord: Chord,
        context: TheoryContext
    ) -> Set<Int> {
        guard
            context.scoringUsesScaleAwareness,
            let first = options(for: chord, context: context).first
        else {
            return []
        }
        return Set(first.primaryScale.intervals.map { Chord.normalizePitchClass(chord.rootPitchClass + $0) })
    }

    func guideToneNames(
        chord: Chord,
        context: TheoryContext
    ) -> [String] {
        guard let option = options(for: chord, context: context).first else {
            return []
        }

        let intervals = option.guideToneRule?.intervals ?? [2, 6].map {
            switch $0 {
            case 2: return chord.quality == .minor ? 3 : 4
            case 6:
                switch chord.quality {
                case .major: return 11
                case .diminished: return 9
                default: return 10
                }
            default: return 0
            }
        }

        return intervals.map { interval in
            let writtenPitchClass = Chord.normalizePitchClass(
                chord.rootPitchClass + interval + context.instrument.writtenSemitoneOffset
            )
            return TheoryDisplayFormatter.displaySymbol(Chord.pitchClassNames[writtenPitchClass])
        }
    }

    func recommendationText(
        chord: Chord,
        context: TheoryContext
    ) -> String? {
        guard let option = options(for: chord, context: context).first else { return nil }
        let guideTones = guideToneNames(chord: chord, context: context)
        if guideTones.count >= 2 {
            return "Target \(guideTones[0]) and \(guideTones[1]) on the next change."
        }
        return "Try \(option.primaryScale.name) color, then resolve to a chord tone."
    }

    private func sort(options: [TheoryResolvedOption], mode: TheorySortMode) -> [TheoryResolvedOption] {
        switch mode {
        case .relevance:
            return options.sorted {
                if $0.recommendation.relevance != $1.recommendation.relevance {
                    return $0.recommendation.relevance > $1.recommendation.relevance
                }
                if $0.recommendation.tensionLevel != $1.recommendation.tensionLevel {
                    return $0.recommendation.tensionLevel < $1.recommendation.tensionLevel
                }
                return $0.primaryScale.name < $1.primaryScale.name
            }
        case .tension:
            return options.sorted {
                if $0.recommendation.tensionLevel != $1.recommendation.tensionLevel {
                    return $0.recommendation.tensionLevel < $1.recommendation.tensionLevel
                }
                return $0.primaryScale.name < $1.primaryScale.name
            }
        case .alphabetical:
            return options.sorted { $0.primaryScale.name < $1.primaryScale.name }
        }
    }
}
