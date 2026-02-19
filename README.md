# ImprovBuddy

ImprovBuddy is a SwiftUI iOS/iPadOS jazz practice studio focused on real-time rhythm + harmony coaching.

## Project status

This repository now contains a full Xcode project generated via `xcodegen` with:

- SwiftUI app target: `ImprovBuddy`
- Unit test target: `ImprovBuddyTests`
- SwiftData models for songs, sessions, and library items
- MIDI + microphone input pipeline with unified event bus
- DSP modules (onset, tempo/pocket, swing ratio, pitch detection, chord parsing, harmonic classification, form tracking)
- Rules-based AI Jazz Coach (live prompts + post-session report)
- Tabs: Coach, Songs, Tools, Library, Settings
- Tools: metronome, tuner, BPM detector, practice sandbox
- Library: idea recorder, theory library, Labs feature gate
- Debug Test Lab screen + unit tests

## Build

```bash
xcodegen generate
xcodebuild -project ImprovBuddy.xcodeproj -scheme ImprovBuddy -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' build
```

## Test

```bash
xcodebuild -project ImprovBuddy.xcodeproj -scheme ImprovBuddy -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' test
```

## Notes

- The app is designed for iOS/iPadOS. Mac Catalyst support is enabled here to compile/test in this environment.
- iOS runtime installation may still be required locally if your Xcode lacks the iOS platform component.
