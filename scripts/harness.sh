#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcrun >/dev/null; then
  echo 'Harness builds require macOS with Xcode and an iOS simulator SDK.' >&2; exit 1
fi
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
app=build/AuroraHarness.app
mkdir -p "$app"
xcrun --sdk iphonesimulator clang -arch "$arch" -isysroot "$sdk" \
  -target "$arch-apple-ios16.0-simulator" -fobjc-arc -fmodules -DAUR_HARNESS \
  -Wall -Wextra -Wno-unused-parameter -ISources \
  -framework Foundation -framework UIKit -framework MediaPlayer \
  -framework QuartzCore -framework CoreImage -framework UniformTypeIdentifiers \
  Sources/AURCore.m Sources/AURLyrics.m Sources/AURArtwork.m Sources/AURLockScreen.m Sources/AURPlayer.m Sources/AURInjection.m Harness/main.m \
  -o "$app/AuroraHarness"
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('build/AuroraHarness.app/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'dev.aurora.harness','CFBundleExecutable':'AuroraHarness',
 'CFBundleName':'Aurora Harness','CFBundlePackageType':'APPL','CFBundleVersion':'1',
 'CFBundleShortVersionString':'0.1.0','MinimumOSVersion':'16.0',
 'UILaunchScreen':{},'UIDeviceFamily':[1,2],
 'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']
}))
PY
codesign --force --sign - "$app"
echo 'Built build/AuroraHarness.app. Boot a simulator, then:'
echo 'xcrun simctl install booted build/AuroraHarness.app'
echo 'xcrun simctl launch --console booted dev.aurora.harness'
