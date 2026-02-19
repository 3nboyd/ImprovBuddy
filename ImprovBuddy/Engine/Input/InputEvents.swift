import Foundation

struct OnsetEvent: Sendable, Hashable {
    var time: TimeInterval
    var confidence: Double
    var source: EventSource
}

struct PitchEvent: Sendable, Hashable {
    var time: TimeInterval
    var midiNote: Double
    var confidence: Double
    var source: EventSource
}
