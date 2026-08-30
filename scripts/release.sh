#!/bin/bash
# Builds a signed, optionally notarized Squatter release DMG, plus the signed Sparkle
# appcast that tells installed copies about it.
#
#   scripts/release.sh                 # archive, sign, DMG, appcast (no notarization)
#   scripts/release.sh --notarize      # also notarize + staple; only this output is publishable
#
# Before a release: bump BOTH MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml
# (Sparkle compares the build number — a reused one is invisible to installed copies) and
# cut the version's section in CHANGELOG.md (the appcast embeds it as release notes).
#
# Notarization needs a keychain profile created once with:
#   xcrun notarytool store-credentials squatter --apple-id <id> --team-id M8A3G95883 --password <app-specific-password>
# The appcast needs the Sparkle EdDSA key in the login Keychain under $SPARKLE_ACCOUNT
# (Sparkle's generate_keys); the app's SUPublicEDKey must be that key's public half.
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
SPARKLE_BIN="$BUILD/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
# Keychain account holding the Sparkle EdDSA key (step 3 of plan 013). "ed25519" is
# Sparkle's default account, shared with GhostCursor; "squatter" if the owner chose a
# dedicated key. Both tools below must use the same account or the appcast is unsigned.
SPARKLE_ACCOUNT="ed25519"

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
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" test -quiet

echo "==> Archive"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD/DerivedData" -archivePath "$ARCHIVE" archive -quiet

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

# The app must carry the public half of the key the appcast will be signed with. If they
# differ, every copy of this build would reject every future update — and generate_appcast
# only *warns* about the mismatch, then writes an unsigned item and exits 0. Fail here.
[[ -x "$SPARKLE_BIN/generate_keys" ]] || { echo "Sparkle tools not found under $SPARKLE_BIN"; exit 1; }
KEYCHAIN_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" -p --account "$SPARKLE_ACCOUNT")
BUNDLE_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$EXPORT/$APP/Contents/Info.plist")
if [[ "$KEYCHAIN_PUBLIC_KEY" != "$BUNDLE_PUBLIC_KEY" ]]; then
  echo "SUPublicEDKey in the app does not match the Sparkle key in the login Keychain."
  echo "Run generate_keys, put its public key in project.yml, and rebuild."; exit 1
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

echo "==> Appcast"
# Signed over the *final* DMG bytes: stapling changed them, so this cannot run earlier.
# (Without --notarize this still runs, over the unstapled DMG — useful for checking the
# pipeline, but only a --notarize run produces an appcast that may be published.)
# generate_appcast wants a directory; give it one holding exactly this release, plus a
# Squatter-<version>.md beside the DMG, which it embeds in the item as markdown release
# notes. Notes come from CHANGELOG.md, so a version that has not been cut there cannot
# be released.
APPCAST_DIR="$BUILD/appcast"
mkdir -p "$APPCAST_DIR"
cp "$DMG" "$APPCAST_DIR/"
NOTES="$APPCAST_DIR/Squatter-$VERSION.md"
awk -v v="## [$VERSION]" 'index($0, v) == 1 {p=1; next} /^## \[/ {p=0} p' CHANGELOG.md > "$NOTES"
[[ -s "$NOTES" ]] || { echo "CHANGELOG.md has no '## [$VERSION]' section — cut the release there first"; exit 1; }
RELEASE_URL="https://github.com/National-Idea-LLC/squatter/releases/download/v$VERSION/"
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$RELEASE_URL" \
  --embed-release-notes \
  --link "https://github.com/National-Idea-LLC/squatter" \
  --full-release-notes-url "https://github.com/National-Idea-LLC/squatter/blob/main/CHANGELOG.md" \
  --maximum-deltas 0 \
  -o "$BUILD/appcast.xml" \
  "$APPCAST_DIR"
# On a key mismatch generate_appcast prints a warning, writes the item with no EdDSA
# signature attribute, and exits 0 (verified with 2.9.6). Refuse that.
grep -q 'sparkle:edSignature="' "$BUILD/appcast.xml" || { echo "appcast.xml has no EdDSA signature — refusing"; exit 1; }
grep -q "$RELEASE_URL""Squatter-$VERSION.dmg" "$BUILD/appcast.xml" || { echo "appcast.xml does not point at Squatter-$VERSION.dmg under v$VERSION"; exit 1; }
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$BUILD/appcast.xml" || { echo "appcast.xml is not for $VERSION"; exit 1; }
grep -q 'sparkle:format="markdown"' "$BUILD/appcast.xml" || { echo "appcast.xml has no embedded release notes"; exit 1; }

echo
echo "DMG:     $DMG"
echo "sha256:  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "appcast: $BUILD/appcast.xml"
echo "notes:   $NOTES"
echo
echo "Publish the DMG and the appcast as assets of the same release — Sparkle reads the"
echo "appcast from the 'latest' release, and the release notes are embedded in it:"
echo "  gh release create v$VERSION \"$DMG\" \"$BUILD/appcast.xml\" --title \"Squatter $VERSION\" --notes-file \"$NOTES\""
