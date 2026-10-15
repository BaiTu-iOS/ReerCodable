#!/bin/bash
# Created by yuxilong on 2026/10/15.
set -euo pipefail

mkdir -p results
[[ $(uname -m) == arm64 ]]
[[ $(xcodebuild -version | sed -n '1p') == "Xcode $CONSUMER" ]]
xcodebuild -version > results/toolchain.txt
xcrun swift --version >> results/toolchain.txt
cp plugin/manifest.json results/
xcodegen generate
plugin="$PWD/plugin/ReerCodableMacros"

tests=failed
if xcodebuild test -project MacroIntegration.xcodeproj -scheme MacIntegration \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build-mac \
  -resultBundlePath results/MacIntegration.xcresult "MACRO_PLUGIN=$plugin" \
  > results/mac-test.log 2>&1; then
  tests=passed
else
  tail -n 80 results/mac-test.log
fi

ios=failed
if xcodebuild build -project MacroIntegration.xcodeproj -scheme iOSIntegration \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-ios "MACRO_PLUGIN=$plugin" > results/ios-build.log 2>&1; then
  ios=passed
else
  tail -n 80 results/ios-build.log
fi

echo "| $PRODUCER | $CONSUMER | $tests | $ios |" | tee results/summary.md >> "$GITHUB_STEP_SUMMARY"
[[ "$tests" == passed && "$ios" == passed ]]
