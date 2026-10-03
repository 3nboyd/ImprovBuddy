# Architecture

Jade is a SwiftUI application organized around services, feature views, analysis engines, and SwiftData models.

## Application layer

- `ImprovBuddyApp` creates the SwiftData model container and launches the root interface.
- `AppEnvironment` and `ServiceContainer` hold shared application services.
- `RootTabView` coordinates the Songs, Recorder, Tools, Library, and Settings areas.

## Data and persistence

SwiftData models represent songs, measures, practice sessions, theory entries, drills, and library items. `ModelContainerFactory` creates the persistent store and provides recovery and in-memory fallback paths when initialization fails.

Imported documents and audio recordings are handled through Apple platform APIs. The project does not include a remote data service or account layer.

## Audio and MIDI pipeline

`AudioEngineManager` and `MIDIManager` convert device input into normalized events on `UnifiedEventBus`. Analysis components consume those events for onset, pitch, tempo, swing, harmony, and form estimates. Tool-specific engines power the metronome, tuner, BPM detector, synthesizer, and idea recorder.

```text
Microphone / MIDI
        |
        v
Input managers -> Unified event bus -> Analysis engines
                                           |
                                           v
                                Coach and tool features
```

## User-interface features

- `Features/Songs` manages charts, imported files, and song editing.
- `Features/Tools` provides metronome, tuner, BPM, and sandbox experiences.
- `Features/Library` contains recordings and theory reference views.
- `Features/Coach` coordinates live analysis prompts and reports.
- `Features/Settings` contains app information and preferences.

## Distribution layouts

The primary Xcode project uses `ImprovBuddy/`. `Jade.swiftpm/` mirrors the application code for SwiftPM app-package workflows. The two copies must remain synchronized, with the SwiftPM package carrying only its package-specific manifest, plist, and accent-color resources.
