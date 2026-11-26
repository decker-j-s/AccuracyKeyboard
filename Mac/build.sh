#!/bin/bash
# Builds the Mac version and installs it into ~/Applications.
# Run again after any change (including prompt.md), like pressing ▶ for the phone.
#
#   ./Mac/build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "Building…"
swift build -c release

APP="build/Accuracy Checker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CheckChinese "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp ../Keyboard/prompt.md "$APP/Contents/Resources/"   # the same prompt the phone uses

# Sign it. Prefer the Apple Development certificate Xcode created for the
# phone: then macOS remembers the Accessibility permission across rebuilds.
# Without one, sign locally (works, but you'd re-allow Accessibility after each build).
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}' || true)
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Installing…"
pkill -x CheckChinese 2>/dev/null || true             # stop the old version if running
mkdir -p ~/Applications
rm -rf ~/Applications/"Accuracy Checker.app"
cp -R "$APP" ~/Applications/
# Tell macOS about the (new) app, then refresh the Services menu.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Accuracy Checker.app"
/System/Library/CoreServices/pbs -flush
/System/Library/CoreServices/pbs -update

open ~/Applications/"Accuracy Checker.app"                # start it so ⌃⌥C works right away
echo "Done: ~/Applications/Accuracy Checker.app (shortcut: ⌃⌥C)"
