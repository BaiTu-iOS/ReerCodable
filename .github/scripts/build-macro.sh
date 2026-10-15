#!/bin/bash
set -euo pipefail

[[ $(uname -m) == arm64 ]]
[[ $(xcodebuild -version | head -n 1) == "Xcode $EXPECTED_XCODE" ]]
[[ $(git -C upstream rev-parse HEAD) == "$UPSTREAM_COMMIT" ]]

xcrun swift build --package-path upstream -c release --product ReerCodableMacros --traits AutoFlexibleType
bin=$(xcrun swift build --package-path upstream -c release --show-bin-path --traits AutoFlexibleType)
mkdir -p dist/package dist/check
cp "$bin/ReerCodableMacros-tool" dist/package/ReerCodableMacros
chmod +x dist/package/ReerCodableMacros
[[ $(lipo -archs dist/package/ReerCodableMacros) == arm64 ]]
plugin="$PWD/dist/package/ReerCodableMacros#ReerCodableMacros"

# Exercise the copied executable through the same compiler flag CocoaPods will use.
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find upstream/Sources/ReerCodable -name '*.swift' -print0)
xcrun swiftc -emit-library -emit-module -module-name ReerCodable \
  -load-plugin-executable "$plugin" "${sources[@]}" \
  -emit-module-path dist/check/ReerCodable.swiftmodule -o dist/check/libReerCodable.dylib
xcrun swiftc .github/scripts/macro-smoke.swift -I dist/check -L dist/check -lReerCodable \
  -load-plugin-executable "$plugin" -Xlinker -rpath -Xlinker "$PWD/dist/check" -o dist/check/smoke
dist/check/smoke

cp upstream/LICENSE* dist/package/
cp upstream/Package.resolved dist/package/
xcodebuild -version > dist/package/xcode-version.txt
xcrun swift --version > dist/package/swift-version.txt
otool -L dist/package/ReerCodableMacros > dist/package/linked-libraries.txt
if grep -E '/Users/|/Applications/|@rpath|@loader_path|@executable_path' dist/package/linked-libraries.txt; then
  echo 'Plugin depends on non-system libraries; package those before distributing.' >&2
  exit 1
fi
jq -n --arg version "$UPSTREAM_VERSION" --arg commit "$UPSTREAM_COMMIT" \
  --arg tag "$RELEASE_TAG" --arg xcode "$EXPECTED_XCODE" \
  --rawfile swift dist/package/swift-version.txt --rawfile xcode_build dist/package/xcode-version.txt \
  --arg macos "$(sw_vers -productVersion)" \
  '{release_tag:$tag, upstream_version:$version, upstream_commit:$commit, xcode:$xcode, xcode_build:$xcode_build, swift:$swift, architecture:"arm64", auto_flexible_type:true, tested_host_macos:$macos, build_revision:1}' > dist/manifest.json
cp dist/manifest.json dist/package/
tar -czf dist/ReerCodableMacros.tar.gz -C dist/package .
(cd dist && shasum -a 256 ReerCodableMacros.tar.gz manifest.json > SHA256SUMS)
rm -r dist/check dist/package
