#!/bin/zsh
# Builds a Developer ID–signed, notarized and stapled SyncBar DMG.
#
#   scripts/release.sh                 # full release: sign, notarize, staple, DMG
#   scripts/release.sh --skip-notarize # sign and package only (for a quick local check)
#
# Notarization uses a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials SyncBar-notary --apple-id <apple id> --team-id 3TJQ367JDZ
# Override the profile name with NOTARY_PROFILE=...
set -euo pipefail

TEAM_ID=3TJQ367JDZ
PROFILE=${NOTARY_PROFILE:-SyncBar-notary}
SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

ROOT=${0:A:h:h}
OUT=$ROOT/build/release
ARCHIVE=$OUT/SyncBar.xcarchive
EXPORT=$OUT/export
APP=$EXPORT/SyncBar.app

step() { print -P "\n%F{blue}==>%f %B$1%b" }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1 }

notarize() { # file
    local log=$OUT/notary-${1:t:r}.json
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json > "$log" || true
    local result=$(/usr/bin/plutil -extract status raw -o - "$log" 2>/dev/null || echo unknown)
    if [[ "$result" != "Accepted" ]]; then
        local id=$(/usr/bin/plutil -extract id raw -o - "$log" 2>/dev/null || true)
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        fail "notarization of ${1:t} returned '$result' (details above, raw result in $log)"
    fi
    print "Accepted"
}

if ! $SKIP_NOTARIZE; then
    step "Checking notarytool profile '$PROFILE'"
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
        || fail "no working notarytool profile '$PROFILE'. Create it once with:
  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
fi

security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM_ID)" \
    || fail "no 'Developer ID Application' certificate for team $TEAM_ID in the keychain"

rm -rf "$OUT" && mkdir -p "$OUT"
# Keep Spotlight from listing build copies of SyncBar next to the installed one.
touch "$ROOT/build/.metadata_never_index"

step "Archiving"
xcodebuild -project "$ROOT/SyncBar.xcodeproj" -scheme SyncBar -configuration Release \
    -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -derivedDataPath "$ROOT/build/DerivedData" \
    archive -quiet

step "Exporting with Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=$OUT/SyncBar-$VERSION.dmg

step "Checking signature of SyncBar $VERSION"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^(Authority=Developer ID Application|TeamIdentifier|Runtime Version|Timestamp)"

if ! $SKIP_NOTARIZE; then
    step "Notarizing the app"
    ditto -c -k --keepParent "$APP" "$OUT/SyncBar.zip"
    notarize "$OUT/SyncBar.zip"
    xcrun stapler staple -q "$APP"
fi

step "Building $DMG:t"
STAGE=$OUT/dmg
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SyncBar.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "SyncBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --sign "Developer ID Application: yuting bai ($TEAM_ID)" --timestamp "$DMG"

if ! $SKIP_NOTARIZE; then
    step "Notarizing the DMG"
    notarize "$DMG"
    xcrun stapler staple -q "$DMG"

    step "Gatekeeper assessment"
    spctl --assess --type execute -vv "$APP" 2>&1
    spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1
    xcrun stapler validate -q "$DMG" && print "DMG ticket stapled"
fi

# Only the DMG (and notarization records) are worth keeping; extra app copies confuse Spotlight and Launch Services.
rm -rf "$STAGE" "$EXPORT" "$ARCHIVE" "$OUT/SyncBar.zip"

step "Done"
print "$DMG ($(du -h "$DMG" | cut -f1))"
