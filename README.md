# Shuffle Music

Shuffle Music is a standalone macOS menu bar music player extracted from Companion.

The first version keeps the Companion random-playback engine and mini player panel, but runs as its own accessory app with an independent status bar icon and inline previous / play-pause / next controls.

## Run

```bash
./script/build_and_run.sh
```

## Compatibility

Shuffle Music requires macOS 12.0 or later.

Release builds are universal macOS apps containing both `arm64` and `x86_64` slices. They write `LSMinimumSystemVersion=12.0` in the app bundle and compile through the SwiftPM macOS 12 deployment target declared in `Package.swift`.

## Package

```bash
./script/package_release.sh
```

## Test

```bash
./script/run_tests.sh
```

Core tests are intentionally implemented as a SwiftPM executable runner instead of `swift test`. The local Command Line Tools Swift environment can build XCTest-shaped targets without running any test cases, which creates a false-green result. Use `./script/run_tests.sh` as the release-check test command.

For a Gatekeeper-ready public build, sign and notarize with:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-notarytool-profile" \
./script/package_release.sh
```

Without those environment variables the package is ad-hoc signed for local testing.
