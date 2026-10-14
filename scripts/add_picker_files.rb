#!/usr/bin/env ruby
# One-time wiring of the keyboard-navigation sources into EmoPic.xcodeproj.
#
#   ruby scripts/add_picker_files.rb [EmoPic.xcodeproj]
#
# The project uses explicit PBXFileReference entries (no folder-synchronized
# groups), so new .swift files are invisible to the build until registered here
# or in Xcode. Idempotent, and it drops each file into the same group as an
# existing sibling so the navigator stays tidy.
#
# Requires the xcodeproj gem: gem install --user-install xcodeproj

require 'xcodeproj'

PROJECT = ARGV[0] || 'EmoPic.xcodeproj'

project = Xcodeproj::Project.open(PROJECT)
app     = project.targets.find { |t| t.name == 'EmoPic' }
tests   = project.targets.find { |t| t.name == 'EmoPicTests' }
abort 'EmoPic target not found'      unless app
abort 'EmoPicTests target not found' unless tests

# The group holding an existing file, so new files land beside it.
def group_of(project, anchor)
  ref = project.files.find { |f| f.path.to_s.end_with?(anchor) }
  abort "anchor file #{anchor} not found in project" unless ref
  ref.parent
end

def add_source(project, target, group, name)
  already = target.source_build_phase.files.map { |f| f.file_ref&.path.to_s }
  if already.any? { |p| p.end_with?(name) }
    puts "already linked: #{name} (#{target.name})"
    return
  end
  existing = group.children.find { |c| c.display_name == name }
  ref = existing || group.new_reference(name)
  target.add_file_references([ref])
  puts "added #{name} -> #{target.name}"
end

picker_group = group_of(project, 'EmojiPickerView.swift')
add_source(project, app, picker_group, 'PickerSelectionModel.swift')
add_source(project, app, picker_group, 'PickerKeyCatcher.swift')

test_group = group_of(project, 'UpdateSettingsTests.swift')
add_source(project, tests, test_group, 'PickerSelectionTests.swift')

project.save
puts 'saved'
