#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DERIVED_DATA="$ROOT/dist/DerivedData-Local"
LOCAL_APP="$ROOT/dist/local/Clippy.app"
LOCAL_DSYM="$LOCAL_DERIVED_DATA/Build/Products/Release/Clippy.app.dSYM"
OUTPUT_DIR="$ROOT/dist/release-unsigned"

cd "$ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release validation failed: the Git working tree is not clean."
  exit 1
fi

ruby scripts/generate_xcodeproj.rb
git diff --exit-code -- Clippy.xcodeproj
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

rm -rf "$OUTPUT_DIR"
"$ROOT/scripts/build_local.sh"
mkdir -p "$OUTPUT_DIR"

APP="$LOCAL_APP"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
FINAL_DMG="$OUTPUT_DIR/Clippy-$VERSION.dmg"
DSYM_ZIP="$OUTPUT_DIR/Clippy-$VERSION-dSYM.zip"
CASK="$OUTPUT_DIR/clippy.rb"

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if ! grep -q "^Signature=adhoc$" <<<"$SIGNATURE_DETAILS"; then
  echo "Release validation failed: expected an ad-hoc app signature."
  exit 1
fi
if grep -q "^Authority=" <<<"$SIGNATURE_DETAILS"; then
  echo "Release validation failed: an unexpected signing authority is present."
  exit 1
fi
if ! grep -q "flags=.*runtime" <<<"$SIGNATURE_DETAILS"; then
  echo "Release validation failed: Hardened Runtime is not enabled."
  exit 1
fi

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

"$ROOT/scripts/create_dmg.sh" "$APP" "$FINAL_DMG" "Clippy $VERSION"
if codesign -dv "$FINAL_DMG" >/dev/null 2>&1; then
  echo "Release validation failed: the unsigned DMG unexpectedly has a code signature."
  exit 1
fi
"$ROOT/scripts/verify_dmg.sh" "$FINAL_DMG" "$VERSION"

if [[ ! -d "$LOCAL_DSYM" ]]; then
  echo "Release validation failed: the dSYM bundle is missing."
  exit 1
fi
ditto -c -k --keepParent "$LOCAL_DSYM" "$DSYM_ZIP"

SHA256="$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')"
printf "%s  %s\n" "$SHA256" "$(basename "$FINAL_DMG")" > "$FINAL_DMG.sha256"
sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__SHA256__/$SHA256/g" \
  Packaging/Casks/clippy-unsigned.rb.template > "$CASK"

echo
echo "Clippy $VERSION ($BUILD) is packaged for the free unsigned distribution."
echo "The app is ad-hoc signed with Hardened Runtime."
echo "It is NOT Developer ID signed or notarized by Apple."
echo "Release DMG:     $FINAL_DMG"
echo "SHA-256:         $SHA256"
echo "dSYM:            $DSYM_ZIP"
echo "Homebrew cask:   $CASK"
