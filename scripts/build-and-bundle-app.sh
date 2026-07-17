#!/bin/bash
# Builds the SPM executable and assembles a signed CleanShotZ.app bundle.
# Signing with the local "Apple Development" cert keeps the TCC (Screen Recording)
# permission stable across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/CleanShot Z.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development}"

# The MacOSX27.0 SDK (default since the 2026-07 CLT update) turns SwiftUI @State
# into a macro backed by the SwiftUIMacros compiler plugin, which Command Line
# Tools do not ship — builds fail with "plugin for module 'SwiftUIMacros' not
# found". Pin the last working SDK while it exists (same fix as dockz).
LEGACY_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -d "$LEGACY_SDK" ]]; then
    export SDKROOT="$LEGACY_SDK"
fi

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/CleanShotZ" "$APP/Contents/MacOS/CleanShotZ"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    echo "warning: '$SIGN_IDENTITY' identity not found, falling back to ad-hoc signing (TCC permission may reset between builds)"
    codesign --force --sign - "$APP"
fi

echo "Built: $APP"
