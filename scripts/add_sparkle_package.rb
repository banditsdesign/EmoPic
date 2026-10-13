#!/usr/bin/env ruby
# One-time wiring of the Sparkle Swift package into EmoPic.xcodeproj, so the
# update mechanism can be added without opening Xcode.
#
#   ruby scripts/add_sparkle_package.rb [EmoPic.xcodeproj]
#
# Adds: the remote package reference, the Sparkle product dependency on the app
# target, and the link entry in the target's Frameworks phase. Idempotent.
#
# Deliberately NOT added: an "Embed Frameworks" copy phase. Xcode embeds dynamic
# library products from Swift packages on its own — verified by building and
# checking EmoPic.app/Contents/Frameworks/Sparkle.framework for Versions/B,
# Autoupdate, Updater.app and XPCServices/{Installer,Downloader}.xpc. A
# hand-rolled copy phase referencing the package product fails instead
# ("The file "Sparkle-product" couldn't be opened"), because the copy source it
# derives is the synthetic package target name rather than the artifact path.
#
# Requires the xcodeproj gem: gem install --user-install xcodeproj

require 'xcodeproj'

PROJECT = ARGV[0] || 'EmoPic.xcodeproj'
PRODUCT = 'Sparkle'
REPO    = 'https://github.com/sparkle-project/Sparkle'
MINIMUM = '2.10.0'

project = Xcodeproj::Project.open(PROJECT)
target  = project.targets.find { |t| t.name == 'EmoPic' }
abort 'EmoPic target not found' unless target

# 1. Remote package reference on the project.
ref = project.root_object.package_references.find do |r|
  r.respond_to?(:repositoryURL) && r.repositoryURL == REPO
end
unless ref
  ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  ref.repositoryURL = REPO
  ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => MINIMUM }
  project.root_object.package_references << ref
  puts "added package reference: #{REPO} >= #{MINIMUM}"
end

# 2. Product dependency on the app target.
dep = target.package_product_dependencies.find { |d| d.product_name == PRODUCT }
unless dep
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = ref
  dep.product_name = PRODUCT
  target.package_product_dependencies << dep
  puts "added product dependency: #{PRODUCT}"
end

# 3. Link phase: the executable must link Sparkle.framework.
frameworks = target.frameworks_build_phase
unless frameworks.files.any? { |f| f.product_ref == dep }
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  frameworks.files << build_file
  puts "linked #{PRODUCT} in #{frameworks.display_name}"
end

project.save
puts 'saved'
