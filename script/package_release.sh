#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Shuffle Music"
ARTIFACT_NAME="${APP_NAME// /-}"
EXECUTABLE_NAME="ShuffleMusic"
BUNDLE_ID="com.crazyjal.ShuffleMusic"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
MIN_SYSTEM_VERSION="12.0"
ARM_TRIPLE="arm64-apple-macosx$MIN_SYSTEM_VERSION"
INTEL_TRIPLE="x86_64-apple-macosx$MIN_SYSTEM_VERSION"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_ROOT="$ROOT_DIR/release/v$APP_VERSION"
APP_BUNDLE="$RELEASE_ROOT/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
STAGING_DIR="$RELEASE_ROOT/staging"
DMG_PATH="$RELEASE_ROOT/$ARTIFACT_NAME-$APP_VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
APP_ICON_SOURCE="$ROOT_DIR/Sources/ShuffleMusic/Resources/AppIcon.icns"

rm -rf "$RELEASE_ROOT"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --product "$EXECUTABLE_NAME" --triple "$ARM_TRIPLE"
swift build -c release --product "$EXECUTABLE_NAME" --triple "$INTEL_TRIPLE"
ARM_BINARY="$(swift build -c release --product "$EXECUTABLE_NAME" --triple "$ARM_TRIPLE" --show-bin-path)/$EXECUTABLE_NAME"
INTEL_BINARY="$(swift build -c release --product "$EXECUTABLE_NAME" --triple "$INTEL_TRIPLE" --show-bin-path)/$EXECUTABLE_NAME"
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"

/usr/libexec/PlistBuddy -c "Clear dict" "$INFO_PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_BUILD" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$INFO_PLIST"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signing with ad-hoc identity. Set SIGN_IDENTITY='Developer ID Application: ...' for Gatekeeper-ready distribution."
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  echo "Signing with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY." >&2
    exit 2
  fi
  echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" | awk -v filename="$(basename "$DMG_PATH")" '{print $1 "  " filename}' > "$CHECKSUM_PATH"

echo "DMG: $DMG_PATH"
echo "SHA256: $(awk '{print $1}' "$CHECKSUM_PATH")"
lipo -archs "$APP_BINARY"
