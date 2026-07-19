#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/Clippy.app /path/to/Clippy-version.dmg [volume-name]"
  exit 1
fi

APP_INPUT="$1"
DMG_INPUT="$2"
VOLUME_NAME="${3:-Clippy}"

if [[ ! -d "$APP_INPUT" || ! -x "$APP_INPUT/Contents/MacOS/Clippy" ]]; then
  echo "A built Clippy.app is required:"
  echo "  $APP_INPUT"
  exit 1
fi

APP="$(cd "$(dirname "$APP_INPUT")" && pwd)/$(basename "$APP_INPUT")"
mkdir -p "$(dirname "$DMG_INPUT")"
DMG="$(cd "$(dirname "$DMG_INPUT")" && pwd)/$(basename "$DMG_INPUT")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKGROUND_1X="$ROOT/Packaging/DMG/background.png"
BACKGROUND_2X="$ROOT/Packaging/DMG/background@2x.png"
APPLESCRIPT="$ROOT/scripts/configure_dmg.applescript"

if [[ "$DMG" != *.dmg ]]; then
  echo "The output path must end in .dmg:"
  echo "  $DMG"
  exit 1
fi

if [[ -e "$DMG" ]]; then
  echo "The output path already exists:"
  echo "  $DMG"
  exit 1
fi

for required_file in \
  "$APP/Contents/Resources/AppIcon.icns" \
  "$BACKGROUND_1X" \
  "$BACKGROUND_2X" \
  "$APPLESCRIPT"
do
  if [[ ! -f "$required_file" ]]; then
    echo "Required DMG asset is missing:"
    echo "  $required_file"
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clippy-dmg.XXXXXX")"
STAGING="$WORK_DIR/staging"
MOUNT_POINT="$WORK_DIR/mount"
READ_WRITE_DMG="$WORK_DIR/Clippy-read-write.dmg"
ATTACHED=false

cleanup() {
  if [[ "$ATTACHED" == true ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING/.background" "$MOUNT_POINT"
ditto "$APP" "$STAGING/Clippy.app"
ln -s /Applications "$STAGING/Applications"
tiffutil -cathidpicheck \
  "$BACKGROUND_1X" \
  "$BACKGROUND_2X" \
  -out "$STAGING/.background/background.tiff"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$READ_WRITE_DMG"

hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$READ_WRITE_DMG" >/dev/null
ATTACHED=true

xcrun SetFile -a V "$MOUNT_POINT/.background"
osascript "$APPLESCRIPT" "$MOUNT_POINT"
ditto "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
xcrun SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT_POINT"
sync

for attempt in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT_POINT" >/dev/null; then
    ATTACHED=false
    break
  fi
  if [[ "$attempt" == 5 ]]; then
    echo "Unable to detach the temporary DMG cleanly."
    exit 1
  fi
  sleep 1
done

hdiutil convert \
  "$READ_WRITE_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG"

hdiutil verify "$DMG"
echo "Created $DMG"
