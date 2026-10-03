import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PianoStripView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var highlightedPitchClasses: Set<Int>
    var displayNamesByPitchClass: [Int: String] = [:]
    var showsTitle: Bool = true
    var compact: Bool = false

    private let whitePitchClasses = [0, 2, 4, 5, 7, 9, 11]
    private let whiteKeyLabels = ["C", "D", "E", "F", "G", "A", "B"]
    private let blackPitchClasses = [1, 3, 6, 8, 10]
    private let blackKeyOffsetByPitchClass: [Int: Int] = [
        1: 0,
        3: 1,
        6: 3,
        8: 4,
        10: 5
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if showsTitle {
                Text("Piano")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let whiteKeySpacing: CGFloat = compact ? 2 : 3
                let whiteHeight: CGFloat = compact ? 42 : 62
                let whiteWidth = (proxy.size.width - (CGFloat(whitePitchClasses.count - 1) * whiteKeySpacing)) / CGFloat(whitePitchClasses.count)
                let blackWidth = whiteWidth * 0.62
                let blackHeight = whiteHeight * 0.62

                ZStack(alignment: .topLeading) {
                    HStack(spacing: whiteKeySpacing) {
                        ForEach(whitePitchClasses, id: \.self) { pitchClass in
                            let isHighlighted = highlightedPitchClasses.contains(pitchClass)
                            RoundedRectangle(cornerRadius: compact ? 4 : 5)
                                .fill(isHighlighted ? highlightedWhiteKeyColor : whiteKeyBaseColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: compact ? 4 : 5)
                                        .strokeBorder(
                                            isHighlighted ? highlightedWhiteKeyStrokeColor : Color.secondary.opacity(0.28),
                                            lineWidth: isHighlighted ? 1.2 : 1
                                        )
                                )
                                .frame(width: whiteWidth, height: whiteHeight)
                        }
                    }

                    ForEach(blackPitchClasses, id: \.self) { pitchClass in
                        if let offsetIndex = blackKeyOffsetByPitchClass[pitchClass] {
                            let isHighlighted = highlightedPitchClasses.contains(pitchClass)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: compact ? 3 : 4)
                                    .fill(isHighlighted ? highlightedBlackKeyColor : blackKeyBaseColor)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: compact ? 3 : 4)
                                            .strokeBorder(
                                                isHighlighted ? highlightedBlackKeyStrokeColor : Color.white.opacity(0.08),
                                                lineWidth: isHighlighted ? 1.2 : 1
                                            )
                                    )

                                if !compact {
                                    Text(label(for: pitchClass))
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(isHighlighted ? Color.white : Color.white.opacity(0.45))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                        .padding(.bottom, 3)
                                }
                            }
                            .frame(width: blackWidth, height: blackHeight)
                            .offset(
                                x: CGFloat(offsetIndex + 1) * whiteWidth + CGFloat(offsetIndex) * whiteKeySpacing - (blackWidth / 2),
                                y: 0
                            )
                        }
                    }
                }
            }
            .frame(height: compact ? 42 : 62)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 6 : 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 10 : 12))

            if !compact {
                HStack(spacing: 0) {
                    ForEach(Array(zip(whitePitchClasses, whiteKeyLabels)), id: \.0) { pair in
                        Text(label(for: pair.0, fallback: pair.1))
                            .font(.caption2)
                            .foregroundStyle(highlightedPitchClasses.contains(pair.0) ? accentColor : .secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var whiteKeyBaseColor: Color { Color(red: 0.92, green: 0.92, blue: 0.95) }
    private var blackKeyBaseColor: Color { Color(red: 0.12, green: 0.12, blue: 0.14) }
    private var accentColor: Color { appEnvironment.accentColor }
    private var highlightedWhiteKeyColor: Color { accentColor }
    private var highlightedWhiteKeyStrokeColor: Color { accentColor }
    private var highlightedBlackKeyColor: Color {
#if os(iOS)
        let ui = UIColor(accentColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            return Color(
                hue: Double(hue),
                saturation: Double(min(1, saturation)),
                brightness: Double(max(0, brightness * 0.82)),
                opacity: Double(alpha)
            )
        }
#endif
        return accentColor.opacity(0.88)
    }
    private var highlightedBlackKeyStrokeColor: Color { accentColor.opacity(0.92) }

    private var prefersFlatFallback: Bool {
        let values = displayNamesByPitchClass.values
        let hasFlat = values.contains { $0.contains("♭") || $0.contains("b") }
        let hasSharp = values.contains { $0.contains("♯") || $0.contains("#") }
        return hasFlat && !hasSharp
    }

    private func label(for pitchClass: Int, fallback: String? = nil) -> String {
        if let provided = displayNamesByPitchClass[pitchClass], !provided.isEmpty {
            return TheoryDisplayFormatter.displaySymbol(provided)
        }

        let sharpFallback: [Int: String] = [1: "C#", 3: "D#", 6: "F#", 8: "G#", 10: "A#"]
        let flatFallback: [Int: String] = [1: "Db", 3: "Eb", 6: "Gb", 8: "Ab", 10: "Bb"]

        if let fallback {
            return TheoryDisplayFormatter.displaySymbol(fallback)
        }

        if prefersFlatFallback, let name = flatFallback[pitchClass] {
            return TheoryDisplayFormatter.displaySymbol(name)
        }
        if let name = sharpFallback[pitchClass] {
            return TheoryDisplayFormatter.displaySymbol(name)
        }
        return TheoryDisplayFormatter.displaySymbol(Chord.pitchClassNames[pitchClass])
    }
}
