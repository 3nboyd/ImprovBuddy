import SwiftUI

struct PianoStripView: View {
    var highlightedPitchClasses: Set<Int>

    private let pitchClassNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private let blackKeyPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Piano")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { pitchClass in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(keyColor(for: pitchClass))
                            .frame(height: blackKeyPitchClasses.contains(pitchClass) ? 40 : 62)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        Text(pitchClassNames[pitchClass])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func keyColor(for pitchClass: Int) -> Color {
        if highlightedPitchClasses.contains(pitchClass) {
            return .cyan
        }

        if blackKeyPitchClasses.contains(pitchClass) {
            return Color(red: 0.14, green: 0.14, blue: 0.16)
        }
        return Color(red: 0.92, green: 0.92, blue: 0.95)
    }
}
