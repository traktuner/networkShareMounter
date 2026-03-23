#!/usr/bin/env ruby
# extract_changelog.rb
# usgae: ruby extract_changelog.rb 3.1.17

version = ARGV[0].to_s.sub(/^release-/, '')
if version.empty?
  puts "Error: Please provide a version."
  exit 1
end

# Ermittelt den Pfad zur CHANGELOG-Datei relativ zu diesem Skript
# __dir__ ist der Ordner des Skripts (scripts/), .. geht eine Ebene hoch zum Root.
changelog_path = File.expand_path('../CHANGELOG', __dir__)

unless File.exist?(changelog_path)
  puts "Error: CHANGELOG file in #{changelog_path} not found."
  exit 1
end

changelog = File.read(changelog_path)

# Dieser Regex sucht nach der Zeile "## [Version]" (mit oder ohne Klammern)
# und extrahiert alles bis zur nächsten Zeile, die mit "## " beginnt.
pattern = /^##\s*\[?#{Regexp.escape(version)}\]?.*?\n(.*?)(?=\n##\s| \z)/m

match = changelog.match(pattern)

if match
  # .strip entfernt überflüssige Leerzeilen am Anfang/Ende
  puts match[1].strip
else
  # Falls die Version nicht gefunden wurde (z.B. Tippfehler im Tag)
  puts "No entries for version #{version} found in the changelog."
end

