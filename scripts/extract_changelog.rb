#!/usr/bin/env ruby
# extract_changelog.rb
#
# Usage:
#   ruby scripts/extract_changelog.rb 3.1.17
#   ruby scripts/extract_changelog.rb release-3.1.17
#   ruby scripts/extract_changelog.rb 3.1.17 --json
#   ruby scripts/extract_changelog.rb --json 3.1.17
#   ruby scripts/extract_changelog.rb --all
#   ruby scripts/extract_changelog.rb --all --json
#
# Output:
#   single version -> markdown body (default) OR JSON object (with --json)
#   --all          -> markdown for all versions
#   --all --json   -> JSON array for Hugo data

require 'json'

args = ARGV.dup
all_mode = args.delete('--all')
json_mode = args.delete('--json')

# CHANGELOG file
changelog_path = File.expand_path('../CHANGELOG', __dir__)
unless File.exist?(changelog_path)
  warn "Error: CHANGELOG file in #{changelog_path} not found."
  exit 1
end

changelog = File.read(changelog_path)

pattern_all = /^##\s+\[(?<ver>\d+\.\d+\.\d+)\]\s*(?:-\s*(?<date>\d{4}-\d{2}-\d{2}))?\s*\n(?<body>.*?)(?=^##\s+|\z)/m

entries = changelog.scan(pattern_all).map do |ver, date, body|
  {
    'version' => ver,
    'date' => date,
    'description' => body.to_s.strip
  }
end

if all_mode
  if json_mode
    puts JSON.pretty_generate(entries)
  else
    entries.each do |e|
      header = "## [#{e['version']}]"
      header += " - #{e['date']}" if e['date'] && !e['date'].empty?
      puts header
      puts
      puts e['description']
      puts
    end
  end
  exit 0
end

# Single-version mode
version = args[0].to_s.sub(/^release-/, '')
if version.empty?
  warn "Error: Please provide a version (e.g. 3.1.17) or use --all."
  exit 1
end

entry = entries.find { |e| e['version'] == version }

if entry
  if json_mode
    puts JSON.pretty_generate(entry)
  else
    puts entry['description']
  end
else
  if json_mode
    warn "Error: No entries for version #{version} found in the changelog."
    exit 1
  else
    puts "No entries for version #{version} found in the changelog."
  end
end
