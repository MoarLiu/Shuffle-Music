# Changelog

## 0.1.0 - 2026-06-22

- Initial standalone Shuffle Music macOS menu bar release.
- Added independent menu bar controls for player, previous, play/pause, and next.
- Added floating mini player panel extracted from Companion.
- Added random playback catalog from fixed NetEase Music playlist/chart sources.

Compatibility:

- Requires macOS 12.0 or later.
- Universal macOS build with Apple Silicon `arm64` and Intel `x86_64` slices.
- Release packaging supports Developer ID signing and notarization through `SIGN_IDENTITY` and `NOTARY_PROFILE`; without those values, local packages are ad-hoc signed.
