# Created by yuxilong on 2026/10/19.
gem 'minitest', '~> 5.0'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require_relative 'spec-compatibility'

class SpecCompatibilityTest < Minitest::Test
  def setup
    output, error, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'render-podspec.rb'), '1.8.1', 'a' * 40)
    raise error unless status.success?
    @spec = JSON.parse(output)
  end

  def test_new_version_uses_verified_producer_and_is_idempotent
    updated = SpecCompatibility.extend_spec(@spec, '99.1')
    assert_equal ['99.1'], SpecCompatibility.validate_update(@spec, updated)
    assert_equal updated, SpecCompatibility.extend_spec(updated, '99.1')
    block = SpecCompatibility.script(updated)[SpecCompatibility::CASE_BLOCK]
    output, _, status = Open3.capture3({ 'xcode_version' => '99.1' }, 'bash', '-c', "#{block}\nprintf '%s' \"$producer\"")
    assert status.success?
    assert_equal '26.6', output
    _, _, status = Open3.capture3({ 'xcode_version' => '99.2' }, 'bash', '-c', block)
    refute status.success?
  end

  def test_existing_mapping_is_unchanged
    assert_equal @spec, SpecCompatibility.extend_spec(@spec, '27.1')
    assert_empty SpecCompatibility.validate_update(@spec, @spec)
  end

  def test_multiple_additions_and_partial_publication_retry
    first = SpecCompatibility.extend_spec(@spec, '99.1')
    second = SpecCompatibility.extend_spec(first, '99.2')
    assert_equal %w[99.1 99.2], SpecCompatibility.validate_update(@spec, second)
    assert_equal ['99.2'], SpecCompatibility.validate_update(first, second)
    assert_raises(RuntimeError) { SpecCompatibility.validate_update(second, first) }
  end

  def test_rejects_source_and_other_setting_changes
    updated = SpecCompatibility.extend_spec(@spec, '99.1')
    updated['source']['commit'] = 'b' * 40
    assert_raises(RuntimeError) { SpecCompatibility.validate_update(@spec, updated) }
    updated = SpecCompatibility.extend_spec(@spec, '99.1')
    updated['version'] = '1.8.2'
    assert_raises(RuntimeError) { SpecCompatibility.validate_update(@spec, updated) }
  end

  def test_rejects_changed_mapping_checksum_and_unknown_version_guard
    ['producer=26.6', 'shasum -a 256 -c SHA256SUMS', 'exit 1'].each do |fragment|
      updated = SpecCompatibility.extend_spec(@spec, '99.1')
      updated['script_phases']['script'] = SpecCompatibility.script(updated).sub(fragment, ':')
      assert_raises(RuntimeError) { SpecCompatibility.validate_update(@spec, updated) }
    end
  end

  def test_rejects_injection_and_duplicate_mappings
    assert_raises(RuntimeError) { SpecCompatibility.extend_spec(@spec, '27.2;exit 0') }
    updated = SpecCompatibility.extend_spec(@spec, '99.1')
    line = SpecCompatibility.script(updated)[SpecCompatibility::AUTOMATIC_LINE]
    updated['script_phases']['script'] = SpecCompatibility.script(updated).sub(line, line * 2)
    assert_raises(RuntimeError) { SpecCompatibility.validate_update(@spec, updated) }
  end
end
