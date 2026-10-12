#!/bin/sh
# Stamps a built Info.plist with Cylindarr's apps' version and build number, the house
# pattern in ~/.claude/CLAUDE.md. Run from a postbuild script phase.
#
#   stamp-version.sh next   the first target an xcodebuild compiles: takes a new build number
#   stamp-version.sh same   a target built after it: reuses that number, so an app and its
#                           embedded extension match, which App Store Connect requires
#
# Version is the Year.Month of the build. Build is a counter, one more on every
# build, kept with the version in the gitignored .buildnumber ("2026.9 42").
# Nothing comes from git, so a build numbers the same way in any checkout.
set -eu

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
stamp="$SRCROOT/.buildnumber"

case "${1:-}" in
  next)
    # The last number in the file, so an older one-number file still counts up.
    previous=$(awk '{ print $NF }' "$stamp" 2>/dev/null || true)
    case "$previous" in
      ''|*[!0-9]*) previous=0 ;;
    esac
    echo "$(date +%Y.%-m) $((previous + 1))" > "$stamp"
    ;;
  same)
    if [ ! -f "$stamp" ]; then
      echo "error: $stamp is missing; the target that runs 'next' should have built first" >&2
      exit 1
    fi
    ;;
  *)
    echo "error: usage: stamp-version.sh next|same" >&2
    exit 1
    ;;
esac

read -r version build < "$stamp"

# A second App Store release in the same month needs a higher version than the
# first. CYLINDARR_VERSION_PATCH sets this; the file keeps Year.Month, so the
# patch applies to that one build and never sticks.
patch="${CYLINDARR_VERSION_PATCH:-0}"
case "$patch" in
  ''|*[!0-9]*)
    echo "error: CYLINDARR_VERSION_PATCH must be a number, got '$patch'" >&2
    exit 1
    ;;
esac
if [ "$patch" -ne 0 ]; then
  version="$version.$patch"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"

# Read it back: a phase that silently edits the wrong file still reports success.
written="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist") $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")"
if [ "$written" != "$version $build" ]; then
  echo "error: $plist says $written, expected $version $build" >&2
  exit 1
fi
