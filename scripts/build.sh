#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcrun >/dev/null; then
  echo 'Native builds require macOS with Xcode and the iPhoneOS SDK. Use the Build workflow on GitHub.' >&2
  exit 1
fi
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p build
xcrun --sdk iphoneos clang -dynamiclib -arch arm64 -isysroot "$sdk" \
  -miphoneos-version-min=16.0 -fobjc-arc -fmodules -Wall -Wextra \
  -Wno-unused-parameter -Werror=return-type \
  -install_name @rpath/Aurora.dylib \
  -framework Foundation -framework UIKit -framework MediaPlayer \
  -framework QuartzCore -framework UniformTypeIdentifiers \
  Sources/AURCore.m Sources/AURPlayer.m Sources/AURInjection.m \
  -o build/Aurora.dylib
printf 'Built build/Aurora.dylib\n'
