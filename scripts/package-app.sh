#!/usr/bin/env bash
# Builds Vocal.app and installs it to /Applications. Re-run after code changes.
# Same approach as Faro's and Canteiro's package scripts.
#
# It's signed with your Developer ID when the keychain has one (an Apple
# Development certificate otherwise), so macOS sees each build as the same app
# and keeps the microphone, Input Monitoring and Accessibility permissions.
# With neither it signs ad hoc, and the permissions reset on every build.
#
# --release also puts the speech model inside the app, has Apple notarize it,
# and leaves dist/Vocal-<version>.zip for GitHub Releases. It needs a
# "Developer ID Application" certificate and notarytool credentials saved once:
#   xcrun notarytool store-credentials vocal-notary --apple-id <email> --team-id <team>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vocal"
BUNDLE_ID="com.amongthestones.vocal"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="${VOCAL_INSTALL_DIR:-/Applications}"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SOURCE_ICON="$ROOT/Resources/AppIcon.png"
ENTITLEMENTS="$ROOT/scripts/Vocal.entitlements"
MODEL="$HOME/Library/Application Support/Vocal/Models/parakeet-ultra"
INSTALL=1
RELEASE=0
SIGN_ID="${VOCAL_SIGN_ID:-}"
NOTARY_PROFILE="${VOCAL_NOTARY_PROFILE:-vocal-notary}"

VERSION="$(git -C "$ROOT" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VOCAL_VERSION:-${VERSION:-0.1.0}}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --release) RELEASE=1; INSTALL=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-install] [--release]"
      echo "  Builds dist/Vocal.app and copies it to $INSTALL_DIR"
      echo "  --release: model inside, Developer ID, notarized, dist/Vocal-<version>.zip; doesn't install."
      echo "  VOCAL_SIGN_ID and VOCAL_NOTARY_PROFILE pick the certificate and credentials."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

# Converts the square PNG master into AppIcon.icns.
build_icns() {
  local src="$1" dest="$2" work iconset size
  work="$(mktemp -d "${TMPDIR:-/tmp}/vocal-icon.XXXXXX")"
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$src" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$src" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$dest"
  rm -rf "$work"
}

cd "$ROOT"
swift build -c release --product "$APP_NAME"
BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$APP_NAME"

# Stamp the SDK it was built with, so macOS doesn't run it in compatibility mode.
SDK_VERSION="$(xcrun --show-sdk-version)"
MIN_VERSION="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' "$ROOT/Package.swift").0"
xcrun vtool -set-build-version macos "$MIN_VERSION" "$SDK_VERSION" -replace \
  -output "$MACOS/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

if [[ -f "$SOURCE_ICON" ]]; then
  build_icns "$SOURCE_ICON" "$RESOURCES/AppIcon.icns"
else
  echo "warning: no Resources/AppIcon.png (swift scripts/make-icon.swift makes it)" >&2
fi

if [[ "$RELEASE" -eq 1 ]]; then
  # A downloaded copy has no install script, so the model travels inside the
  # app and Vocal never needs the network.
  if [[ ! -d "$MODEL/Encoder.mlmodelc" ]]; then
    "$ROOT/scripts/install-model.sh"
  fi
  mkdir -p "$RESOURCES/Models"
  cp -R "$MODEL" "$RESOURCES/Models/parakeet-ultra"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_VERSION}</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Vocal records your voice while you hold the dictation key and turns it into text on this Mac. Nothing is sent anywhere.</string>
</dict>
</plist>
EOF

if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

if [[ "$RELEASE" -eq 1 ]]; then
  if [[ -z "$SIGN_ID" ]]; then
    echo "error: no Developer ID Application certificate in the keychain" >&2
    exit 1
  fi
  # The hardened runtime, which notarizing requires. It blocks the microphone
  # unless the entitlement asks for it.
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Signed: $APP with $SIGN_ID"

  ZIP="$DIST/$APP_NAME-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarizing (this usually takes a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # Attach Apple's ticket to the app so it opens offline too, then zip the
  # stapled app for release.
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
  echo "Ready: $ZIP (version $VERSION, build $BUILD_NUMBER, $(du -h "$ZIP" | cut -f1))"
  exit 0
fi

if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
if [[ -n "$SIGN_ID" ]]; then
  # The same signature as a release, without the timestamp server, so it
  # works offline. Not notarized, which only matters on other Macs.
  codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
  echo "Signed with: $SIGN_ID"
else
  codesign --force --sign - --timestamp=none "$APP"
  echo "warning: ad-hoc signed; permissions will reset after each rebuild" >&2
fi

echo "Built: $APP (version $VERSION, build $BUILD_NUMBER)"

if [[ "$INSTALL" -eq 1 ]]; then
  if pgrep -xq "$APP_NAME" >/dev/null 2>&1; then
    echo "Quitting running Vocal…"
    pkill -x "$APP_NAME" || true
    sleep 0.5
  fi
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  # Nudge Finder and Spotlight to pick up the icon.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
  echo "Installed: $INSTALL_DIR/$APP_NAME.app"
fi
