<p align="center">
  <img src="ImprovBuddy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" alt="Jade app icon">
</p>

# Jade

[![CI](https://github.com/3nboyd/ImprovBuddy/actions/workflows/ci.yml/badge.svg)](https://github.com/3nboyd/ImprovBuddy/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue.svg)](https://developer.apple.com/ios/)

Jade is a local-first SwiftUI workspace for live musicians. It combines song and chart organization, practice tools, audio ideas, and music theory in one iPhone and iPad app.

The repository and Xcode target retain the original `ImprovBuddy` name. The product name shown in the app is **Jade: The Live Musician's Best Friend**.

## Features

- Songs workspace with PDF and image import, paging, tags, and lightweight markup
- Metronome with count-in, meter, subdivisions, swing, tap tempo, and sound selection
- Tuner and pitch guidance powered by live microphone analysis
- Audio idea recorder with local playback and transport controls
- Theory library with scale, chord, staff, and piano visualizations
- MIDI and microphone input pipeline with a unified event bus
- Rules-based coaching, harmony analysis, tempo analysis, and form tracking
- SwiftData persistence for songs, practice sessions, library items, and settings
- Responsive iPhone and iPad layouts, plus Mac Catalyst support

## Requirements

- Xcode 16 or later with an iOS simulator runtime
- iOS or iPadOS 17 or later
- Swift 6
- XcodeGen 2.40 or later only when regenerating the project from `project.yml`

## Getting started

```bash
git clone https://github.com/3nboyd/ImprovBuddy.git
cd ImprovBuddy
open ImprovBuddy.xcodeproj
```

Select the `ImprovBuddy` scheme and run it on an iPhone or iPad simulator. Microphone, MIDI, and document-import behavior is best tested on a physical device.

The checked-in Xcode project is ready to open. To regenerate it after editing `project.yml`:

```bash
xcodegen generate
```

## Build and test

Build for an iOS simulator:

```bash
xcodebuild \
  -project ImprovBuddy.xcodeproj \
  -scheme ImprovBuddy \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the unit tests with Mac Catalyst:

```bash
xcodebuild \
  -project ImprovBuddy.xcodeproj \
  -scheme ImprovBuddy \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## SwiftPM app package

`Jade.swiftpm` is a synchronized SwiftPM app package for workflows that accept an app playground or `.swiftpm` submission. Open `Jade.swiftpm` in Xcode or Swift Playgrounds and run the `Jade` scheme.

The application source directories in `ImprovBuddy/` and `Jade.swiftpm/` are intentionally mirrored. Changes to app code should update both copies in the same pull request.

## Repository structure

```text
.
├── ImprovBuddy/             Main application source and resources
├── ImprovBuddyTests/        Unit tests
├── ImprovBuddy.xcodeproj/   Checked-in Xcode project
├── Jade.swiftpm/            Mirrored SwiftPM app package
├── docs/                    Architecture documentation
├── project.yml              XcodeGen project definition
└── tools/                   Dataset-generation utilities
```

See [Architecture](docs/ARCHITECTURE.md) for a guide to the app layers and runtime data flow.

## Privacy

Jade does not include analytics, advertising, accounts, or a network client. Imported charts, recordings, and app data remain on the device unless the user exports or shares them through system features. The microphone is used for recording, tuning, tempo, and pitch analysis.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Security and privacy concerns should follow [SECURITY.md](SECURITY.md).

## License

Jade is available under the [MIT License](LICENSE).
