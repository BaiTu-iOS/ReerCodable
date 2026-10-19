# Created by yuxilong on 2026/10/19.
require 'digest'
require 'fileutils'
require 'open3'
require 'rubygems'
require_relative 'spec-compatibility'

module XcodeSupport
  ROOT = File.expand_path('../..', __dir__)
  SPEC_NAME = 'ReerCodable.podspec.json'
  RELEASE_TAG = /\Amacros-(v?\d+\.\d+\.\d+)-xcode-26\.6-arm64-flex-r1\z/
  RUNNERS = %w[macos-26 xcode-27].freeze

  def self.capture(*command, env: {}, chdir: ROOT)
    output, error, status = Open3.capture3(env, *command, :chdir => chdir)
    raise "#{command.first} failed: #{error}\n#{output}" unless status.success?
    output.strip
  end

  def self.run(*command, env: {}, chdir: ROOT, log: nil)
    puts "+ #{command.join(' ')}"
    success = if log
                File.open(log, 'w') { |file| system(env, *command, :chdir => chdir, :out => file, :err => file) }
              else
                system(env, *command, :chdir => chdir)
              end
    raise "Command failed: #{command.first}; log: #{log}" unless success
  end

  def self.repository
    ENV.fetch('GITHUB_REPOSITORY')
  end

  def self.download_spec(tag, directory)
    match = RELEASE_TAG.match(tag) or raise 'Invalid macro release tag'
    FileUtils.mkdir_p(directory)
    run('gh', 'release', 'download', tag, '--repo', repository, '--pattern', "#{SPEC_NAME}*", '--dir', directory)
    contents = File.read(File.join(directory, SPEC_NAME))
    checksum = File.read(File.join(directory, "#{SPEC_NAME}.sha256"))
    raise 'Specification checksum mismatch' unless checksum == "#{Digest::SHA256.hexdigest(contents)}  #{SPEC_NAME}\n"
    spec = JSON.parse(contents)
    source = spec.fetch('source')
    raise 'Invalid released specification' unless spec['name'] == 'ReerCodable' && spec['version'] == match[1].delete_prefix('v') &&
                                                source['git'] == 'https://github.com/reers/ReerCodable.git' && source['commit']&.match?(/\A[a-f0-9]{40}\z/)
    spec
  end

  def self.installed_xcodes
    releases = released_toolchains
    Dir.glob('/Applications/Xcode*.app').map { |path| File.realpath(path) }.uniq.map do |app|
      developer = File.join(app, 'Contents/Developer')
      next unless File.executable?(File.join(developer, 'usr/bin/xcodebuild'))
      output = capture('xcodebuild', '-version', :env => { 'DEVELOPER_DIR' => developer })
      match = /\AXcode (\d+\.\d+(?:\.\d+)?)\nBuild version (\w+)\z/.match(output)
      next unless match && releases[match[1]] == match[2]
      { 'version' => match[1], 'runner' => ENV.fetch('RUNNER_LABEL'), 'developer_dir' => developer, 'build' => match[2] }
    end.compact.uniq { |entry| entry['version'] }.sort_by { |entry| Gem::Version.new(entry['version']) }
  end

  def self.released_toolchains
    image = ENV.fetch('RUNNER_LABEL')
    readme = capture('gh', 'api', "repos/actions/runner-images/contents/images/macos/#{image}-arm64-Readme.md", '-H', 'Accept: application/vnd.github.raw+json')
    # Official image metadata distinguishes GA from beta; paths and build suffixes do not.
    releases = readme.scan(/^\|\s*(\d+\.\d+(?:\.\d+)?)(?:\s+\(default\))?\s*\|\s*(\w+)\s*\|\s*\/Applications\/Xcode/).to_h
    raise 'No release Xcode entries in official runner inventory' if releases.empty?
    releases
  end

  def self.released_tags
    releases = JSON.parse(capture('gh', 'api', '--paginate', '--slurp', "repos/#{repository}/releases?per_page=100")).flatten(1)
    releases.reject { |release| release['draft'] || release['prerelease'] }.select do |release|
      release['tag_name'].match?(RELEASE_TAG) && [SPEC_NAME, "#{SPEC_NAME}.sha256"].all? { |name| release['assets'].any? { |asset| asset['name'] == name } }
    end.map { |release| release.fetch('tag_name') }.sort
  end

  def self.verify(directory, requested)
    raise 'Invalid requested Xcode' unless requested.empty? || requested.match?(SpecCompatibility::VERSION)
    raise 'Expected an Apple Silicon runner' unless capture('uname', '-m') == 'arm64'
    raise 'Unrecognized runner' unless RUNNERS.include?(ENV.fetch('RUNNER_LABEL'))
    FileUtils.mkdir_p(directory)
    installed = installed_xcodes
    raise 'No installed Xcode matches the official release inventory' if installed.empty?
    template = File.read(File.join(ROOT, 'ReerCodable.podspec'))
    known = SpecCompatibility.versions(template)
    candidates = installed.select do |entry|
      requested.empty? ? Gem::Version.new(entry['version']) > known.map { |version| Gem::Version.new(version) }.max : entry['version'] == requested
    end
    report = { 'source_sha' => ENV.fetch('GITHUB_SHA'), 'installed' => installed, 'verified' => [] }
    unless candidates.empty?
      tags = released_tags
      raise 'No published specifications to verify' if tags.empty?
      candidates.each do |xcode|
        specs = tags.map do |tag|
          work = File.join(directory, xcode.fetch('version'), tag)
          baseline = download_spec(tag, File.join(work, 'baseline'))
          candidate = SpecCompatibility.extend_spec(baseline, xcode.fetch('version'))
          SpecCompatibility.validate_update(baseline, candidate)
          verify_spec(candidate, xcode, work)
          { 'tag' => tag, 'baseline' => baseline, 'candidate' => candidate }
        end
        # Approval is emitted only after every published version passes on this Xcode.
        report['verified'] << { 'xcode' => xcode, 'specs' => specs }
      end
    end
    File.write(File.join(directory, 'report.json'), JSON.pretty_generate(report) + "\n")
    puts "Installed: #{installed.map { |entry| entry['version'] }.join(', ')}; verified: #{candidates.map { |entry| entry['version'] }.join(', ')}"
  end

  def self.verify_spec(spec, xcode, work)
    FileUtils.cp_r(File.join(ROOT, '.github/cocoapods'), File.join(work, 'cocoapods'))
    FileUtils.cp_r(File.join(ROOT, '.github/integration'), File.join(work, 'integration'))
    project = File.join(work, 'cocoapods')
    runtime = File.join(project, 'runtime')
    run('git', 'init', runtime)
    run('git', 'fetch', '--depth', '1', 'https://github.com/reers/ReerCodable.git', spec.fetch('source').fetch('commit'), :chdir => runtime)
    run('git', 'checkout', '--detach', 'FETCH_HEAD', :chdir => runtime)
    File.write(File.join(runtime, SPEC_NAME), JSON.pretty_generate(spec) + "\n")
    env = { 'DEVELOPER_DIR' => xcode.fetch('developer_dir') }
    run('xcodegen', 'generate', :env => env, :chdir => project)
    run('pod', 'install', :env => env, :chdir => project, :log => File.join(work, 'pod-install.log'))
    run('xcodebuild', 'test', '-workspace', 'PodIntegration.xcworkspace', '-scheme', 'MacIntegration',
        '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', 'build-mac', '-resultBundlePath', File.join(work, 'Tests.xcresult'),
        :env => env, :chdir => project, :log => File.join(work, 'mac-test.log'))
    run('xcodebuild', 'build', '-workspace', 'PodIntegration.xcworkspace', '-scheme', 'iOSIntegration', '-configuration', 'Release',
        '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', 'build-ios',
        :env => env, :chdir => project, :log => File.join(work, 'ios-build.log'))
  end

  def self.publish(directory, requested)
    reports = Dir.glob(File.join(directory, '*', 'report.json')).map { |path| JSON.parse(File.read(path)) }
    raise 'Missing runner reports' unless reports.length == RUNNERS.length
    raise 'Reports belong to a different commit' unless reports.all? { |report| report.fetch('source_sha') == ENV.fetch('GITHUB_SHA') }
    approvals = reports.flat_map { |report| report.fetch('verified') }
    raise 'Requested Xcode was unavailable on all runners' if !requested.empty? && approvals.empty?
    return puts('No new Xcode support to publish.') if approvals.empty?

    # Do not publish stale test results over a newer template or a concurrent release.
    run('git', 'fetch', 'origin', 'main')
    raise 'main changed during verification; rerun the workflow' unless capture('git', 'rev-parse', 'origin/main') == ENV.fetch('GITHUB_SHA')
    tags = released_tags
    raise 'Published versions changed during verification; rerun' unless approvals.all? { |approval| approval.fetch('specs').map { |spec| spec.fetch('tag') }.sort == tags }
    template_path = File.join(ROOT, 'ReerCodable.podspec')
    template = File.read(template_path)
    registry_path = File.join(ROOT, '.github/xcode-runners.json')
    registry = JSON.parse(File.read(registry_path))
    specs = {}
    originals = {}
    approvals.each do |approval|
      xcode = approval.fetch('xcode')
      version = xcode.fetch('version')
      raise 'Invalid runner evidence' unless RUNNERS.include?(xcode.fetch('runner')) && xcode.fetch('developer_dir').match?(%r{\A/Applications/Xcode[^/]*\.app/Contents/Developer\z})
      template = SpecCompatibility.extend_script(template, version)
      registry << xcode.reject { |key, _| key == 'build' } unless registry.any? { |entry| entry['version'] == version }
      approval.fetch('specs').each do |tested|
        tag = tested.fetch('tag')
        baseline = tested.fetch('baseline')
        candidate = tested.fetch('candidate')
        raise 'Unexpected tested mapping' unless candidate == SpecCompatibility.extend_spec(baseline, version)
        unless specs.key?(tag)
          current = download_spec(tag, File.join(directory, 'current', tag))
          SpecCompatibility.validate_update(baseline, current)
          specs[tag] = current
          originals[tag] = current
        end
        SpecCompatibility.validate_update(baseline, specs.fetch(tag))
        specs[tag] = SpecCompatibility.extend_spec(specs.fetch(tag), version)
      end
    end
    # The template is pushed last: interrupted asset uploads are safely retried next time.
    specs.each do |tag, spec|
      next if spec == originals.fetch(tag)
      output = File.join(directory, 'publish', tag)
      FileUtils.mkdir_p(output)
      contents = JSON.pretty_generate(spec) + "\n"
      File.write(File.join(output, SPEC_NAME), contents)
      File.write(File.join(output, "#{SPEC_NAME}.sha256"), "#{Digest::SHA256.hexdigest(contents)}  #{SPEC_NAME}\n")
      begin
        run('gh', 'release', 'upload', tag, SPEC_NAME, "#{SPEC_NAME}.sha256", '--repo', repository, '--clobber', :chdir => output)
      rescue StandardError
        # Restore the previous verified pair if uploading the replacement fails.
        run('gh', 'release', 'upload', tag, SPEC_NAME, "#{SPEC_NAME}.sha256", '--repo', repository, '--clobber', :chdir => File.join(directory, 'current', tag))
        raise
      end
    end
    File.write(template_path, template) unless File.read(template_path) == template
    registry = registry.sort_by { |entry| Gem::Version.new(entry.fetch('version')) }
    File.write(registry_path, JSON.pretty_generate(registry) + "\n") unless JSON.parse(File.read(registry_path)) == registry
    run('git', 'add', '--', 'ReerCodable.podspec', '.github/xcode-runners.json')
    return if system('git', 'diff', '--cached', '--quiet', :chdir => ROOT)
    run('git', 'diff', '--cached', '--check')
    run('git', 'config', 'user.name', 'github-actions[bot]')
    run('git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
    run('git', 'commit', '-m', "fix: 🐛 自动支持已验证的 Xcode #{approvals.map { |approval| approval['xcode']['version'] }.uniq.join(', ')}")
    run('git', 'push', 'origin', 'HEAD:main')
  end
end

if $PROGRAM_NAME == __FILE__
  command, directory = ARGV
  abort 'Usage: update-xcode-support.rb verify|publish DIRECTORY' unless %w[verify publish].include?(command) && directory
  XcodeSupport.public_send(command, File.expand_path(directory), ENV.fetch('REQUESTED_XCODE', ''))
end
