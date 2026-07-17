#!/bin/bash
# Builds, bundles, and installs CleanShot Z into /Applications (replacing the old copy).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-and-bundle-app.sh release

pkill -f "CleanShot Z.app/Contents/MacOS/CleanShotZ" 2>/dev/null || true
sleep 1
rm -rf "/Applications/CleanShot Z.app"
cp -R "build/CleanShot Z.app" /Applications/
open "/Applications/CleanShot Z.app"
echo "Installed & launched: /Applications/CleanShot Z.app"
