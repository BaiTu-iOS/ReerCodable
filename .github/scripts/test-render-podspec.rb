# Created by yuxilong on 2026/10/15.
require 'json'
require 'open3'
require 'rbconfig'

script = File.join(__dir__, 'render-podspec.rb')
commit = 'a' * 40
%w[1.8.1 v1.9.0].each do |tag|
  output, error, status = Open3.capture3(RbConfig.ruby, script, tag, commit)
  abort error unless status.success?
  spec = JSON.parse(output)
  raise 'Incorrect version' unless spec['version'] == tag.delete_prefix('v')
  raise 'Source is not pinned' unless spec['source']['commit'] == commit
  phase = spec['script_phases']
  phase = phase.first if phase.is_a?(Array)
  raise 'Incorrect macro release' unless phase['script'].include?("macros-#{tag}-xcode-")
  raise 'Incorrect cache version' unless phase['script'].include?("/ReerCodable/#{spec['version']}/")
end
['../1.8.1', '1.8.1;echo bad'].each do |tag|
  _, _, status = Open3.capture3(RbConfig.ruby, script, tag, commit)
  raise 'Invalid version accepted' if status.success?
end
puts 'Podspec rendering checks passed'
