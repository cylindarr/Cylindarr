#!/bin/sh
# Build the Mac app, development-signed, and install it in /Applications.
#
#   scripts/install-on-mac.sh            # build and install
#   scripts/install-on-mac.sh --launch   # and open it
#
# The share extension and the Services item register
# when the app is in /Applications and has been opened once.
set -eu

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

xcodebuild -project Cylindarr.xcodeproj -scheme CylindarrMac \
  -destination "platform=macOS" -derivedDataPath build -allowProvisioningUpdates \
  $AUTH \
  build > build/xcodebuild.log 2>&1 || { grep -E "error:" build/xcodebuild.log | grep -v export; echo "Build failed; the log is build/xcodebuild.log." >&2; exit 1; }

APP=build/Build/Products/Debug/Cylindarr.app
osascript -e 'quit app id "com.pantuso.cylindarr"' 2>/dev/null || true
rm -rf /Applications/Cylindarr.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Cylindarr.app
pluginkit -a /Applications/Cylindarr.app/Contents/PlugIns/CylindarrMacShare.appex 2>/dev/null || true

BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
echo "Cylindarr $VERSION ($BUILD) is in /Applications."

if [ "${1:-}" = "--launch" ]; then
  open /Applications/Cylindarr.app
fi
