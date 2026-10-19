# Created by yuxilong on 2026/10/19.
require 'json'

module SpecCompatibility
  VERSION = /\A\d+\.\d+(?:\.\d+)?\z/
  CASE_BLOCK = /case "\$xcode_version" in\n.*?\nesac/m
  AUTOMATIC_LINE = /^  (\d+\.\d+(?:\.\d+)?)\) producer=26\.6 ;; # Automatically verified compatibility mapping\.\n/

  def self.script(spec)
    phase = spec.fetch('script_phases')
    phase = phase.fetch(0) if phase.is_a?(Array) && phase.length == 1
    phase.fetch('script')
  end

  def self.versions(script)
    block = script[CASE_BLOCK] or raise 'Missing Xcode compatibility case'
    block.scan(/^  ([\d.|]+)\) producer=/).flat_map { |match| match.first.split('|') }
  end

  def self.extend_script(script, version)
    raise 'Invalid Xcode version' unless version.match?(VERSION)
    return script if versions(script).include?(version)

    # Only add a tested exact version; never broaden an existing match or fallback.
    block = script[CASE_BLOCK]
    line = "  #{version}) producer=26.6 ;; # Automatically verified compatibility mapping.\n"
    updated = block.sub(/^  \*\)/, "#{line}  *)")
    raise 'Missing unknown-Xcode rejection' if updated == block
    script.sub(block, updated)
  end

  def self.extend_spec(spec, version)
    updated = JSON.parse(JSON.generate(spec))
    phase = updated.fetch('script_phases')
    phase = phase.first if phase.is_a?(Array)
    phase['script'] = extend_script(script(spec), version)
    updated
  end

  def self.validate_update(old, updated)
    previous = script(old)
    candidate = script(updated)
    known = versions(previous)
    additions = candidate.scan(AUTOMATIC_LINE).flatten.reject { |version| known.include?(version) }
    raise 'Duplicate Xcode mapping' unless additions.uniq == additions
    expected = additions.reduce(old) { |spec, version| extend_spec(spec, version) }
    raise 'Only additive verified Xcode mappings may change' unless updated == expected
    additions
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: spec-compatibility.rb OLD.json NEW.json' unless ARGV.length == 2
  additions = SpecCompatibility.validate_update(*ARGV.map { |path| JSON.parse(File.read(path)) })
  puts "Validated additive Xcode mappings: #{additions.join(', ')}"
end
