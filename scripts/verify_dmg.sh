#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /path/to/Clippy-version.dmg [expected-version]"
  exit 1
fi

DMG_INPUT="$1"
EXPECTED_VERSION="${2:-}"

if [[ ! -f "$DMG_INPUT" ]]; then
  echo "A Clippy DMG is required:"
  echo "  $DMG_INPUT"
  exit 1
fi

DMG="$(cd "$(dirname "$DMG_INPUT")" && pwd)/$(basename "$DMG_INPUT")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clippy-dmg-verify.XXXXXX")"
MOUNT_POINT="$WORK_DIR/mount"
ATTACHED=false

cleanup() {
  if [[ "$ATTACHED" == true ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$MOUNT_POINT"
hdiutil verify "$DMG" >/dev/null
hdiutil attach \
  -readonly \
  -noverify \
  -noautoopen \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$DMG" >/dev/null
ATTACHED=true

APP="$MOUNT_POINT/Clippy.app"
BACKGROUND="$MOUNT_POINT/.background/background.tiff"
VOLUME_ICON="$MOUNT_POINT/.VolumeIcon.icns"
APPLICATIONS_LINK="$MOUNT_POINT/Applications"

for required_path in "$APP" "$BACKGROUND" "$VOLUME_ICON" "$APPLICATIONS_LINK"; do
  if [[ ! -e "$required_path" && ! -L "$required_path" ]]; then
    echo "DMG validation failed: missing $(basename "$required_path")."
    exit 1
  fi
done

VISIBLE_ENTRIES="$(
  find "$MOUNT_POINT" \
    -mindepth 1 \
    -maxdepth 1 \
    ! -name '.*' \
    -exec basename {} \; |
    LC_ALL=C sort
)"
EXPECTED_ENTRIES=$'Applications\nClippy.app'
if [[ "$VISIBLE_ENTRIES" != "$EXPECTED_ENTRIES" ]]; then
  echo "DMG validation failed: unexpected visible top-level entries:"
  echo "$VISIBLE_ENTRIES"
  exit 1
fi

if [[ ! -L "$APPLICATIONS_LINK" || "$(readlink "$APPLICATIONS_LINK")" != "/Applications" ]]; then
  echo "DMG validation failed: Applications is not a link to /Applications."
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/Clippy")"
for architecture in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
    echo "DMG validation failed: missing $architecture slice ($ARCHITECTURES)."
    exit 1
  fi
done

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
if [[ -n "$EXPECTED_VERSION" && "$VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "DMG validation failed: expected $EXPECTED_VERSION, found $VERSION."
  exit 1
fi

TIFF_INFO="$(tiffutil -info "$BACKGROUND")"
if ! grep -Fq "Image Width: 720 Image Length: 450" <<<"$TIFF_INFO"; then
  echo "DMG validation failed: the 1x background representation is missing."
  exit 1
fi
if ! grep -Fq "Image Width: 1440 Image Length: 900" <<<"$TIFF_INFO"; then
  echo "DMG validation failed: the Retina background representation is missing."
  exit 1
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
ATTACHED=false

echo "Verified Clippy $VERSION DMG ($ARCHITECTURES)."
