import Foundation
import SwiftUI

enum NeonAccent: String, CaseIterable, Identifiable {
    case deepBlue
    case cyan
    case lime
    case magenta
    case amber
    case violet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepBlue: "Deep Blue"
        case .cyan: "Cyan"
        case .lime: "Lime"
        case .magenta: "Magenta"
        case .amber: "Amber"
        case .violet: "Violet"
        }
    }

    var color: Color {
        switch self {
        case .deepBlue:
            return Color(red: 0.07, green: 0.42, blue: 0.86)
        case .cyan:
            return Color(red: 0.0, green: 0.93, blue: 1.0)
        case .lime:
            return Color(red: 0.45, green: 1.0, blue: 0.35)
        case .magenta:
            return Color(red: 1.0, green: 0.25, blue: 0.85)
        case .amber:
            return Color(red: 1.0, green: 0.72, blue: 0.16)
        case .violet:
            return Color(red: 0.62, green: 0.46, blue: 1.0)
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    private enum Keys {
        static let accent = "app.neonAccent"
    }

    @Published var preferredA4: Double = 440
    @Published var analysisSensitivity: Double = 0.6
    @Published var highContrastModeEnabled = false
    @Published var showLabsBeta = false
    @Published var neonAccent: NeonAccent {
        didSet {
            UserDefaults.standard.set(neonAccent.rawValue, forKey: Keys.accent)
        }
    }

    var accentColor: Color { neonAccent.color }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.accent),
           let stored = NeonAccent(rawValue: raw) {
            neonAccent = stored
        } else {
            neonAccent = .deepBlue
        }
    }
}
