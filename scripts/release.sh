#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT/dist/DerivedData-Distribution"
ARCHIVE_PATH="$ROOT/dist/Clippy.xcarchive"
OUTPUT_DIR="$ROOT/dist/release"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "SIGN_IDENTITY is required."
  echo 'Example: SIGN_IDENTITY="Developer ID Application: Evan Pluchart (TEAMID)"'
  exit 1
fi

if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "SIGN_IDENTITY must be a Developer ID Application identity."
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required."
  echo "Create one with: xcrun notarytool store-credentials <profile-name>"
  exit 1
fi

if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "DEVELOPMENT_TEAM must be the 10-character Apple Developer Team ID."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  echo "The requested signing identity is not installed in this keychain:"
  echo "  $SIGN_IDENTITY"
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  echo "The notarytool keychain profile could not be used:"
  echo "  $NOTARY_PROFILE"
  exit 1
fi

cd "$ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release validation failed: the Git working tree is not clean."
  exit 1
fi

ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- Clippy.xcodeproj
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

rm -rf "$ARCHIVE_PATH" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project Clippy.xcodeproj \
  -scheme Clippy \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean archive

APP="$ARCHIVE_PATH/Products/Applications/Clippy.app"
DSYM="$ARCHIVE_PATH/dSYMs/Clippy.app.dSYM"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
SUBMISSION_ZIP="$OUTPUT_DIR/Clippy-$VERSION-notarization.zip"
FINAL_DMG="$OUTPUT_DIR/Clippy-$VERSION.dmg"
DSYM_ZIP="$OUTPUT_DIR/Clippy-$VERSION-dSYM.zip"
CASK="$OUTPUT_DIR/clippy.rb"

codesign --verify --deep --strict --verbose=2 "$APP"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/Clippy")"
for architecture in arm64 x86_64; do
  if [[ " $ARCHITECTURES " != *" $architecture "* ]]; then
    echo "Release validation failed: missing $architecture slice ($ARCHITECTURES)."
    exit 1
  fi
done

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>&1)"
if grep -q "com.apple.security.app-sandbox" <<<"$ENTITLEMENTS"; then
  echo "Release validation failed: App Sandbox prevents Clippy's accessibility workflow."
  exit 1
fi
if grep -q "com.apple.security.get-task-allow" <<<"$ENTITLEMENTS"; then
  echo "Release validation failed: get-task-allow is present."
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

"$ROOT/scripts/create_dmg.sh" "$APP" "$FINAL_DMG" "Clippy $VERSION"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"
"$ROOT/scripts/verify_dmg.sh" "$FINAL_DMG" "$VERSION"

if [[ -d "$DSYM" ]]; then
  ditto -c -k --keepParent "$DSYM" "$DSYM_ZIP"
fi
rm -f "$SUBMISSION_ZIP"

SHA256="$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')"
printf "%s  %s\n" "$SHA256" "$(basename "$FINAL_DMG")" > "$FINAL_DMG.sha256"
sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__SHA256__/$SHA256/g" \
  Packaging/Casks/clippy.rb.template > "$CASK"

echo
echo "Clippy $VERSION ($BUILD) is signed, notarized, stapled, and packaged."
echo "Release DMG:     $FINAL_DMG"
echo "SHA-256:         $SHA256"
echo "Homebrew cask:   $CASK"
