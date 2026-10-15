# Created by yuxilong on 2026/10/15.
require 'cocoapods-core'

tag, commit = ARGV
abort 'Expected a release version and source commit' unless tag&.match?(/\Av?\d+\.\d+\.\d+\z/) && commit&.match?(/\A[a-f0-9]{40}\z/)
version = tag.delete_prefix('v')
path = File.expand_path('../../ReerCodable.podspec', __dir__)
source = File.read(path)
abort 'Missing podspec version declaration' unless source.sub!(/^  s.version = '[^']+'$/, "  s.version = '#{version}'")
spec = Pod::Specification.from_string(source, path)
# Pin the same immutable source that the compatibility tests compile.
spec.source = { :git => 'https://github.com/reers/ReerCodable.git', :commit => commit }
spec.attributes_hash.fetch('script_phases').fetch('script').sub!("macros-#{version}-", "macros-#{tag}-")
puts spec.to_pretty_json
