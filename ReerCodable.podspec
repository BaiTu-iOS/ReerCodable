# Created by yuxilong on 2026/10/15.
Pod::Spec.new do |s|
  s.name = 'ReerCodable'
  s.version = '1.8.1'
  s.summary = 'Codable macros with BaiTu prebuilt macro integration.'
  s.homepage = 'https://github.com/BaiTu-iOS/ReerCodable'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'Asura19' => 'x.rhythm@qq.com' }
  s.source = { :git => 'https://github.com/reers/ReerCodable.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_versions = '5.10'
  s.source_files = 'Sources/ReerCodable/**/*.swift'

  # Both the macro declaration module and app/test consumers must load the host executable.
  plugin = "$(PODS_BUILD_DIR)/ReerCodable/#{s.version}/$(XCODE_VERSION_ACTUAL)/ReerCodableMacros"
  flags = "$(inherited) -load-plugin-executable \"#{plugin}#ReerCodableMacros\""
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => flags }
  s.user_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => flags }
  s.script_phase = {
    :name => 'Prepare ReerCodable macro',
    :execution_position => :before_compile,
    :shell_path => '/bin/bash',
    # Check the active Xcode even when its version changes without running pod install.
    :always_out_of_date => '1',
    :script => <<-SCRIPT
set -euo pipefail
trap 'echo "error: ReerCodable macro preparation failed at line $LINENO (exit $?)" >&2' ERR
if [[ $(uname -m) != arm64 ]]; then
  echo 'error: ReerCodable macros currently require an Apple Silicon Mac.' >&2
  exit 1
fi
xcode_version=$(xcodebuild -version | awk 'NR == 1 {print $2}')
case "$xcode_version" in
  26.4.1|26.5|26.6) producer="$xcode_version" ;;
  27.0) producer=26.6 ;; # Explicitly verified compatibility mapping.
  *) echo "error: No verified ReerCodable macro for Xcode $xcode_version" >&2; exit 1 ;;
esac
plugin_dir="${PODS_BUILD_DIR}/ReerCodable/#{s.version}/${XCODE_VERSION_ACTUAL}"
if [[ -x "$plugin_dir/ReerCodableMacros" ]]; then exit 0; fi
mkdir -p "$plugin_dir"
download_dir=$(mktemp -d "$plugin_dir/download.XXXXXX")
trap 'rm -rf "$download_dir"' EXIT
tag="macros-#{s.version}-xcode-$producer-arm64-flex-r1"
base="https://github.com/BaiTu-iOS/ReerCodable/releases/download/$tag"
for asset in ReerCodableMacros.tar.gz manifest.json SHA256SUMS; do
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 180 "$base/$asset" -o "$download_dir/$asset"
done
cd "$download_dir"
shasum -a 256 -c SHA256SUMS
[[ $(/usr/bin/plutil -extract release_tag raw -o - manifest.json) == "$tag" ]]
[[ $(/usr/bin/plutil -extract architecture raw -o - manifest.json) == arm64 ]]
[[ $(/usr/bin/plutil -extract auto_flexible_type raw -o - manifest.json) == true ]]
tar -xzf ReerCodableMacros.tar.gz
[[ $(lipo -archs ReerCodableMacros) == arm64 ]]
chmod +x ReerCodableMacros
mv ReerCodableMacros "$plugin_dir/ReerCodableMacros"
SCRIPT
  }
end
