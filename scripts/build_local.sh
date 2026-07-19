#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT/dist/DerivedData-Local"
OUTPUT_DIR="$ROOT/dist/local"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Clippy.app"
OUTPUT_APP="$OUTPUT_DIR/Clippy.app"

cd "$ROOT"
ruby scripts/generate_xcodeproj.rb

xcodebuild \
  -project Clippy.xcodeproj \
  -scheme Clippy \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  clean build

rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_DIR"
ditto "$BUILT_APP" "$OUTPUT_APP"

codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
ARCHITECTURES="$(lipo -archs "$OUTPUT_APP/Contents/MacOS/Clippy")"
for architecture in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
    echo "Local build validation failed: missing $architecture slice ($ARCHITECTURES)."
    exit 1
  fi
done

echo
echo "Local build ready:"
echo "  $OUTPUT_APP"
echo
echo "This build is ad-hoc signed and is not notarized by Apple."
echo "It can be used locally or as input to the unsigned release pipeline."
echo "Use scripts/release_unsigned.sh for the current free distribution."
echo "Use scripts/release.sh when Developer ID signing and notarization are available."
