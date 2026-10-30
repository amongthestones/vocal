#!/usr/bin/env bash
# Builds Vocal.app and installs it to /Applications. Re-run after code changes.
# Same approach as Faro's package script.
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
INSTALL=1

VERSION="$(git -C "$ROOT" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VOCAL_VERSION:-${VERSION:-0.1.0}}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-install]"
      echo "  Builds dist/Vocal.app and copies it to $INSTALL_DIR"
      echo "  VOCAL_SIGN_IDENTITY overrides the signing certificate."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

# Converts the square PNG master into AppIcon.icns. Same as Faro's script.
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

# Sign with a real certificate when there is one. macOS ties the microphone,
# Input Monitoring and Accessibility permissions to the signature, and an
# ad-hoc signature changes on every build, so permissions would reset each time.
IDENTITY="${VOCAL_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [[ -n "$IDENTITY" ]]; then
  # The hardened runtime blocks the microphone unless the entitlement asks for it.
  codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ROOT/scripts/Vocal.entitlements" --timestamp=none "$APP"
  echo "Signed with: $IDENTITY"
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
