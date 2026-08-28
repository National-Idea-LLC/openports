#!/bin/bash
# Builds a signed, optionally notarized Squatter release DMG.
#
#   scripts/release.sh                 # archive, sign, DMG (no notarization)
#   scripts/release.sh --notarize      # also notarize + staple
#
# Notarization needs a keychain profile created once with:
#   xcrun notarytool store-credentials squatter --apple-id <id> --team-id M8A3G95883 --password <app-specific-password>
set -euo pipefail

NOTARIZE=false
[[ "${1:-}" == "--notarize" ]] && NOTARIZE=true

PROJECT="Squatter.xcodeproj"
SCHEME="Squatter"
APP="Squatter.app"
TEAM_ID="M8A3G95883"
KEYCHAIN_PROFILE="squatter"
BUILD="build"
ARCHIVE="$BUILD/Squatter.xcarchive"
EXPORT="$BUILD/export"

cd "$(dirname "$0")/.."
VERSION=$(awk -F'"' '/MARKETING_VERSION/{print $2}' project.yml)
[[ -n "$VERSION" ]] || { echo "Couldn't read MARKETING_VERSION from project.yml"; exit 1; }
DMG="$BUILD/Squatter-$VERSION.dmg"

echo "==> Squatter $VERSION"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Regenerate project"
command -v xcodegen >/dev/null || { echo "xcodegen not found — install with 'brew install xcodegen'"; exit 1; }
xcodegen generate
git diff --quiet -- Squatter.xcodeproj || echo "note: Squatter.xcodeproj was regenerated from project.yml — commit the change"

echo "==> Tests"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' test -quiet

echo "==> Archive"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet

echo "==> Export"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$EXPORT" -quiet

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$EXPORT/$APP"
codesign -dv --verbose=4 "$EXPORT/$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" \
  || { echo "Missing Developer ID authority or hardened runtime"; exit 1; }
if codesign -d --entitlements - "$EXPORT/$APP" 2>/dev/null | grep -q "app-sandbox"; then
  echo "App Sandbox must stay off (Squatter needs kill(2))"; exit 1
fi

if [[ "$NOTARIZE" == true ]]; then
  echo "==> Notarize app"
  # The ticket must be stapled to the app itself, not only to the DMG: stapling does not
  # follow a bundle that is copied out of the disk image. Without this, `brew install
  # --cask` (which extracts the app) leaves an unstapled app that only passes Gatekeeper
  # on a machine that can reach Apple's notary service.
  ditto -c -k --keepParent "$EXPORT/$APP" "$BUILD/Squatter-app.zip"
  xcrun notarytool submit "$BUILD/Squatter-app.zip" --keychain-profile "$KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$EXPORT/$APP"
  xcrun stapler validate "$EXPORT/$APP"
  rm -f "$BUILD/Squatter-app.zip"
fi

echo "==> DMG"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$EXPORT/$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Squatter" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ "$NOTARIZE" == true ]]; then
  echo "==> Notarize"
  xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
else
  echo "==> Skipping notarization (pass --notarize once credentials exist)"
fi

echo
echo "DMG:    $DMG"
echo "sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
