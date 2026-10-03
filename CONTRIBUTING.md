# Contributing

Contributions that improve reliability, accessibility, music-theory correctness, and musician workflows are welcome.

## Development workflow

1. Create a focused branch from `main`.
2. Make the change in the primary `ImprovBuddy/` source tree.
3. Mirror application-source changes into `Jade.swiftpm/`.
4. Add or update tests in `ImprovBuddyTests/`.
5. Run the build and test commands from the README.
6. Update the changelog for user-visible changes.

The source directories `App`, `Debug`, `Engine`, `Features`, `Models`, `Parsing`, and `Theory` should match between the Xcode project and SwiftPM package. Resource differences must be intentional and documented.

## Pull requests

Keep pull requests small enough to review. Explain the user impact, devices or simulators tested, and any audio, MIDI, persistence, or migration implications. Include screenshots or recordings for visual changes.

Do not commit signing credentials, provisioning profiles, personal team settings, user data, recordings, imported charts, build output, or submission archives.

By contributing, you agree that your contribution is licensed under this repository's MIT License.
