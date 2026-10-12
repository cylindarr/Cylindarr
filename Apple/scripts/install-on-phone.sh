#!/bin/sh
# Build the iPhone app and install it on a phone, development-signed.
#
#   scripts/install-on-phone.sh            # build and install
#   scripts/install-on-phone.sh --launch   # and open it
#
# The phone is paired over the network: awake and on the same network is enough.
# Signing uses your team: CYLINDARR_TEAM is the team ID from your Apple
# Developer account, which project.yml takes when xcodegen runs.
set -eu

: "${CYLINDARR_TEAM:?set CYLINDARR_TEAM to your Apple Developer team ID}"

# The phone's identifier, from `xcrun devicectl list devices`.
DEVICE="${CYLINDARR_DEVICE:?set CYLINDARR_DEVICE to the phone's identifier}"
# Optional: an App Store Connect API key, for a Mac whose Xcode has no Apple
# ID signed in (automatic signing cannot make a profile without one or the
# other). APPLE_API_KEY_PATH is the .p8 file.
AUTH=""
if [ -n "${APPLE_API_KEY_PATH:-}" ]; then
  AUTH="-authenticationKeyPath $APPLE_API_KEY_PATH -authenticationKeyID ${APPLE_API_KEY_ID:?} -authenticationKeyIssuerID ${APPLE_API_ISSUER_ID:?}"
fi

cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
mkdir -p build

xcodebuild -project Cylindarr.xcodeproj -scheme Cylindarr \
  -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates \
  $AUTH \
  build > build/xcodebuild.log 2>&1 || { grep -E "error:" build/xcodebuild.log | grep -v export; echo "Build failed; the log is build/xcodebuild.log." >&2; exit 1; }

APP=build/Build/Products/Debug-iphoneos/Cylindarr.app
xcrun devicectl device install app --device "$DEVICE" "$APP"

BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
echo "Cylindarr $VERSION ($BUILD) is on the phone."

if [ "${1:-}" = "--launch" ]; then
  xcrun devicectl device process launch --device "$DEVICE" com.pantuso.cylindarr
fi
