import Foundation

struct LiveCoachingState {
    var tempo: TempoSnapshot
    var harmony: HarmonyStats
}

final class CoachPromptGenerator {
    private var lastPromptTime: TimeInterval = -10
    private let minPromptInterval: TimeInterval

    init(minPromptInterval: TimeInterval = 5) {
        self.minPromptInterval = minPromptInterval
    }

    func reset() {
        lastPromptTime = -10
    }

    func nextPromptIfNeeded(at time: TimeInterval, state: LiveCoachingState) -> String? {
        guard time - lastPromptTime >= minPromptInterval else { return nil }

        let prompt = prioritizePrompt(for: state)
        if prompt != nil {
            lastPromptTime = time
        }
        return prompt
    }

    private func prioritizePrompt(for state: LiveCoachingState) -> String? {
        if state.tempo.isDrifting && state.tempo.medianErrorMs > 28 {
            return "Tempo is drifting. Lock to quarter-note pulse for 2 bars."
        }

        if state.tempo.signedBiasMs < -14 {
            return "You are rushing. Let the beat come to you."
        }

        if state.tempo.signedBiasMs > 14 {
            return "You are dragging. Keep your line moving forward."
        }

        if state.harmony.downbeatChordTonePct < 0.45 {
            return "Next change: target the 3rd or 7th on beat 1."
        }

        if state.harmony.rootOverusePct > 0.45 {
            return "Move off the root. Aim for guide tones this chorus."
        }

        if state.harmony.resolutionRate < 0.4 && state.harmony.outsidePct > 0.2 {
            return "Nice tension colors. Resolve by step into a chord tone."
        }

        return "Keep breathing through the form."
    }
}
