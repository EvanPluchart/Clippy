#!/usr/bin/env ruby
# Validates translation completeness and, when given a build directory,
# compares the catalog with every Localizable key emitted by the Swift compiler.
require "json"

root = File.expand_path("..", __dir__)
catalog_path = File.join(root, "Clippy/Resources/Localizable.xcstrings")
catalog = JSON.parse(File.read(catalog_path))
strings = catalog.fetch("strings")
errors = []

errors << "sourceLanguage must be fr" unless catalog["sourceLanguage"] == "fr"

placeholder_pattern = /%(?:\d+\$)?(?:lld|ld|d|f|@)/
strings.each do |key, entry|
  unit = entry.dig("localizations", "en", "stringUnit")
  unless unit&.fetch("state", nil) == "translated" && !unit.fetch("value", "").empty?
    errors << "missing English translation: #{key}"
    next
  end

  source_placeholders = key.scan(placeholder_pattern).sort
  translation_placeholders = unit.fetch("value").scan(placeholder_pattern).sort
  unless source_placeholders == translation_placeholders
    errors << "placeholder mismatch: #{key}"
  end
end

if ARGV.first
  strings_data_paths = Dir.glob(File.join(File.expand_path(ARGV.first), "**/*.stringsdata"))
  abort "No .stringsdata files found under #{ARGV.first}" if strings_data_paths.empty?

  extracted_keys = strings_data_paths.flat_map do |path|
    data = JSON.parse(File.read(path))
    data.dig("tables", "Localizable")&.map { |entry| entry.fetch("key") } || []
  end.uniq

  (extracted_keys - strings.keys).sort.each do |key|
    errors << "extracted key missing from catalog: #{key}"
  end
  (strings.keys - extracted_keys).sort.each do |key|
    errors << "catalog key is no longer extracted: #{key}"
  end
end

abort errors.join("\n") unless errors.empty?
puts "Localization catalog valid: #{strings.count} French source strings, all translated to English."
