#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT/Resources/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
IINA_VERSION="1.3.0"
IINA_URL="https://github.com/iina/iina/releases/download/v1.3.0/IINA.v1.3.0.dmg"
IINA_SHA256="b50c416828005e1eec0dc8066c961efcc389e6be1a5a595541ea62d48d31a391"
OUTPUT_DIR="$ROOT/dist"
APP=""
BUILD_SUCCEEDED=0

for tool in swiftc codesign curl hdiutil shasum lipo python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required macOS build tool not found: $tool (install Xcode Command Line Tools)." >&2
    exit 1
  fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/denbox-private-build.XXXXXX")"
IINA_MOUNT="$WORK/iina-mount"
KEYS_MOUNT="$WORK/keys-mount"
IINA_MOUNTED=0
KEYS_MOUNTED=0
mkdir -p "$IINA_MOUNT" "$KEYS_MOUNT"

cleanup() {
  if [[ "$KEYS_MOUNTED" == "1" ]]; then
    hdiutil detach -quiet "$KEYS_MOUNT" >/dev/null 2>&1 || true
  fi
  if [[ "$IINA_MOUNTED" == "1" ]]; then
    hdiutil detach -quiet "$IINA_MOUNT" >/dev/null 2>&1 || true
  fi
  if [[ "$BUILD_SUCCEEDED" != "1" && -n "$APP" && "$APP" == "$OUTPUT_DIR"/Denbox-*.app ]]; then
    /bin/rm -rf "$APP"
  fi
  /bin/rm -rf "$WORK"
}
trap cleanup EXIT

installed_iina="${IINA_APP_PATH:-/Applications/IINA.app}"
iina_app=""
if [[ -d "$installed_iina" ]]; then
  installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_iina/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$installed_version" == "$IINA_VERSION" ]]; then
    iina_app="$installed_iina"
  elif [[ -n "${IINA_APP_PATH:-}" ]]; then
    echo "IINA_APP_PATH must point to IINA $IINA_VERSION because this build is pinned to its libmpv runtime." >&2
    exit 1
  fi
fi

if [[ -z "$iina_app" ]]; then
  echo "IINA $IINA_VERSION was not found locally; downloading its official verified release libraries."
  iina_dmg="$WORK/IINA.v${IINA_VERSION}.dmg"
  curl --fail --location --silent --show-error --max-time 300 "$IINA_URL" --output "$iina_dmg"
  printf '%s  %s\n' "$IINA_SHA256" "$iina_dmg" | shasum -a 256 -c >/dev/null
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$IINA_MOUNT" "$iina_dmg"
  IINA_MOUNTED=1
  iina_app="$(find "$IINA_MOUNT" -maxdepth 2 -type d -name 'IINA.app' -print -quit)"
  if [[ -z "$iina_app" ]]; then
    echo "The verified IINA DMG did not contain IINA.app." >&2
    exit 1
  fi
fi

IINA_FRAMEWORKS="$iina_app/Contents/Frameworks"
MPV_LIBRARY="$IINA_FRAMEWORKS/libmpv.1.dylib"
if [[ ! -f "$MPV_LIBRARY" ]]; then
  echo "IINA's libmpv runtime was not found at $MPV_LIBRARY." >&2
  exit 1
fi
MPV_ARCHS="$(lipo -archs "$MPV_LIBRARY")"
for architecture in arm64 x86_64; do
  if ! printf '%s\n' "$MPV_ARCHS" | tr ' ' '\n' | grep -qx "$architecture"; then
    echo "The selected IINA libmpv library must contain both arm64 and x86_64 slices (found: $MPV_ARCHS)." >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"
APP="$OUTPUT_DIR/Denbox-${APP_VERSION}-build${BUILD_NUMBER}.app"
if [[ -e "$APP" ]]; then
  APP="$OUTPUT_DIR/Denbox-${APP_VERSION}-build${BUILD_NUMBER}-$(date +%Y%m%d-%H%M%S).app"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fa.lproj" \
  "$APP/Contents/Resources/Fonts" "$APP/Contents/Frameworks"

cp "$INFO_PLIST" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Denbox-Icon.png" "$APP/Contents/Resources/Denbox-Icon.png"
cp "$ROOT/Resources/TMDB-Logo.png" "$APP/Contents/Resources/TMDB-Logo.png"
cp "$ROOT/Resources/Fonts/"*.ttf "$APP/Contents/Resources/Fonts/"
cp "$ROOT/Resources/fa.lproj/Localizable.strings" \
  "$APP/Contents/Resources/fa.lproj/Localizable.strings"
for library in "$IINA_FRAMEWORKS/"*.dylib; do
  [[ -e "$library" ]] || continue
  cp "$library" "$APP/Contents/Frameworks/"
done

if ! python3 "$ROOT/Scripts/embed-private-api-keys.py" "$APP"; then
  echo "Required Simba keys are not in this Mac's Keychain; fetching the approved private bootstrap."
  key_dmg="$WORK/Denbox-private-api-bootstrap.dmg"
  python3 "$ROOT/Scripts/download-private-build-keys.py" "$key_dmg"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$KEYS_MOUNT" "$key_dmg"
  KEYS_MOUNTED=1
  source_keys="$KEYS_MOUNT/Denbox.app/Contents/Resources/DenboxPrivateAPIKeys.plist"
  if [[ ! -f "$source_keys" ]]; then
    echo "The private release did not contain the expected API bootstrap resource." >&2
    exit 1
  fi
  cp "$source_keys" "$APP/Contents/Resources/DenboxPrivateAPIKeys.plist"
fi

APP_SOURCES=(
  "$ROOT/Sources/SimbaMac.swift"
  "$ROOT/Sources/DenboxLanguage.swift"
  "$ROOT/Sources/DiscoveryFeeds.swift"
  "$ROOT/Sources/MPVPlayback.swift"
  "$ROOT/Sources/IINAPlaybackMonitor.swift"
  "$ROOT/Sources/PublicTitleMetadata.swift"
  "$ROOT/Sources/PublicMetadataDiscovery.swift"
  "$ROOT/Sources/PublicTitlePageImportView.swift"
  "$ROOT/Sources/ReferenceMetadata.swift"
  "$ROOT/Sources/SegmentedDownloader.swift"
  "$ROOT/Sources/IMDbMetadata.swift"
  "$ROOT/Sources/ViewingActivity.swift"
  "$ROOT/Sources/OnlineSubtitleSearchView.swift"
  "$ROOT/Sources/OpenSubtitles.swift"
)

for architecture in arm64 x86_64; do
  echo "Compiling Denbox for $architecture (macOS 13+)."
  swiftc -parse-as-library -swift-version 5 -O \
    -target "$architecture-apple-macosx13.0" \
    -I "$ROOT/Sources/MPV" \
    -framework SwiftUI -framework AppKit -framework MediaPlayer -framework OpenGL \
    -framework ImageIO -framework Network -framework Security \
    -framework UniformTypeIdentifiers -framework WebKit -lsqlite3 \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${APP_SOURCES[@]}" "$MPV_LIBRARY" -o "$WORK/Denbox-$architecture"
done

lipo -create "$WORK/Denbox-arm64" "$WORK/Denbox-x86_64" \
  -output "$APP/Contents/MacOS/Denbox"
APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/Denbox")"
for architecture in arm64 x86_64; do
  if ! printf '%s\n' "$APP_ARCHS" | tr ' ' '\n' | grep -qx "$architecture"; then
    echo "The built Denbox executable is missing the $architecture slice (found: $APP_ARCHS)." >&2
    exit 1
  fi
done

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" >/dev/null
if ! /usr/bin/plutil -lint "$APP/Contents/Resources/DenboxPrivateAPIKeys.plist" >/dev/null; then
  echo "The app's private API bootstrap plist is invalid." >&2
  exit 1
fi

BUILD_SUCCEEDED=1
echo "Built and verified $APP (Universal: Apple Silicon + Intel, macOS 13 Ventura+)."
echo "This private build contains extractable shared API keys; restrict access to trusted recipients."
