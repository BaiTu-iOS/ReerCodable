# Created by yuxilong on 2026/10/19.
gem 'minitest', '~> 5.0'
require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require_relative 'update-xcode-support'

class XcodeSupportTest < Minitest::Test
  def test_registry_matches_all_supported_versions
    template = File.read(File.join(XcodeSupport::ROOT, 'ReerCodable.podspec'))
    registry = JSON.parse(File.read(File.join(XcodeSupport::ROOT, '.github/xcode-runners.json')))
    assert_equal SpecCompatibility.versions(template).sort, registry.map { |entry| entry.fetch('version') }.sort
    assert registry.all? { |entry| XcodeSupport::RUNNERS.include?(entry.fetch('runner')) }
  end

  def test_uses_release_inventory_instead_of_paths_or_build_suffixes
    previous = ENV['RUNNER_LABEL']
    ENV['RUNNER_LABEL'] = 'xcode-27'
    apps = %w[/Applications/Xcode_27.app /Applications/Xcode_27.1_Release_Candidate.app /Applications/Xcode_27.2_beta.app]
    capture = lambda do |*_, **options|
      path = options.fetch(:env).fetch('DEVELOPER_DIR')
      if path.include?('27.1')
        "Xcode 27.1\nBuild version 27A9275"
      elsif path.include?('beta')
        "Xcode 27.2\nBuild version 27B5000a"
      else
        "Xcode 27.0\nBuild version 27A266a"
      end
    end
    Dir.stub(:glob, apps) do
      File.stub(:realpath, ->(path) { path }) do
        XcodeSupport.stub(:released_toolchains, { '27.0' => '27A266a', '27.1' => '27A9275' }) do
          XcodeSupport.stub(:capture, capture) do
            assert_equal %w[27.0 27.1], XcodeSupport.installed_xcodes.map { |entry| entry['version'] }
          end
        end
      end
    end
  ensure
    ENV['RUNNER_LABEL'] = previous
  end

  def test_inventory_parser_excludes_beta_and_rc_labels
    inventory = <<~TABLE
      | 27.2 (beta) | 27B5028f | /Applications/Xcode_27.2_beta.app |
      | 27.3 (RC) | 27C123 | /Applications/Xcode_27.3_RC.app |
      | 27.1 | 27A9275 | /Applications/Xcode_27.1_Release_Candidate.app |
      | 27.0 (default) | 27A266a | /Applications/Xcode_27.app |
    TABLE
    previous = ENV['RUNNER_LABEL']
    ENV['RUNNER_LABEL'] = 'xcode-27'
    XcodeSupport.stub(:capture, inventory) do
      assert_equal({ '27.0' => '27A266a', '27.1' => '27A9275' }, XcodeSupport.released_toolchains)
    end
  ensure
    ENV['RUNNER_LABEL'] = previous
  end

  def test_ignores_drafts_prereleases_and_incomplete_releases
    complete = {
      'tag_name' => 'macros-1.8.1-xcode-26.6-arm64-flex-r1', 'draft' => false, 'prerelease' => false,
      'assets' => [{ 'name' => XcodeSupport::SPEC_NAME }, { 'name' => "#{XcodeSupport::SPEC_NAME}.sha256" }]
    }
    releases = [complete, complete.merge('draft' => true), complete.merge('prerelease' => true), complete.merge('assets' => []), complete.merge('tag_name' => '../invalid')]
    XcodeSupport.stub(:repository, 'BaiTu-iOS/ReerCodable') do
      XcodeSupport.stub(:capture, JSON.generate([releases])) do
        assert_equal [complete['tag_name']], XcodeSupport.released_tags
      end
    end
  end

  def test_publication_rejects_stale_evidence_before_any_write
    root = File.join(XcodeSupport::ROOT, '.tmp')
    FileUtils.mkdir_p(root)
    previous = ENV['GITHUB_SHA']
    ENV['GITHUB_SHA'] = 'current'
    Dir.mktmpdir('xcode-publication-', root) do |directory|
      XcodeSupport::RUNNERS.each do |runner|
        FileUtils.mkdir_p(File.join(directory, runner))
        File.write(File.join(directory, runner, 'report.json'), JSON.generate('source_sha' => 'old', 'verified' => []))
      end
      XcodeSupport.stub(:run, ->(*) { flunk 'No command may run with stale evidence' }) do
        error = assert_raises(RuntimeError) { XcodeSupport.publish(directory, '') }
        assert_match(/different commit/, error.message)
      end
    end
  ensure
    ENV['GITHUB_SHA'] = previous
    Dir.rmdir(root) if root && Dir.exist?(root) && Dir.empty?(root)
  end

  def test_publication_requires_all_runner_reports
    root = File.join(XcodeSupport::ROOT, '.tmp')
    FileUtils.mkdir_p(root)
    Dir.mktmpdir('xcode-publication-', root) do |directory|
      error = assert_raises(RuntimeError) { XcodeSupport.publish(directory, '') }
      assert_match(/Missing runner reports/, error.message)
    end
  ensure
    Dir.rmdir(root) if root && Dir.exist?(root) && Dir.empty?(root)
  end
end
