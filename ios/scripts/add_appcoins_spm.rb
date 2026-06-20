#!/usr/bin/env ruby
# Injects the AppCoins SwiftPM package + product into the Runner Xcode target,
# points the target at Runner.entitlements (keychain capability), and raises the
# deployment target to the floor required by iOS alternative distribution.
#
# Why a script instead of committed project.pbxproj edits: the project is set up
# on Windows (no Xcode), so this runs on the Codemagic macOS builder before
# `flutter build ipa`. It edits the ephemeral CI checkout only — nothing is
# committed — and is idempotent, so re-running on every build is safe.
#
# Requires the `xcodeproj` gem (ships with CocoaPods; the CI step installs it).

require "xcodeproj"

PROJECT      = File.expand_path(File.join(__dir__, "..", "Runner.xcodeproj"))
PKG_URL      = "https://github.com/Catappult/appcoins-sdk-ios.git"
PKG_MIN      = "4.3.2" # latest at time of writing; pin >= this, < 5.0.0
PRODUCT      = "AppCoinsSDK"
TARGET_NAME  = "Runner"
ENTITLEMENTS = "Runner/Runner.entitlements"
MIN_IOS      = "17.4" # AppCoins / alternative distribution floor

project = Xcodeproj::Project.open(PROJECT)
target  = project.targets.find { |t| t.name == TARGET_NAME }
raise "Target #{TARGET_NAME} not found in #{PROJECT}" unless target

# 1. Remote SwiftPM package reference (idempotent).
pkg_ref = project.root_object.package_references.find do |r|
  r.respond_to?(:repositoryURL) && r.repositoryURL == PKG_URL
end
unless pkg_ref
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = PKG_URL
  pkg_ref.requirement = {
    "kind" => "upToNextMajorVersion",
    "minimumVersion" => PKG_MIN,
  }
  project.root_object.package_references << pkg_ref
  puts "Added SwiftPM package reference: #{PKG_URL} (>= #{PKG_MIN})"
end

# 2. Product dependency linked to the Runner target (idempotent).
dep = target.package_product_dependencies.find { |d| d.product_name == PRODUCT }
unless dep
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = pkg_ref
  dep.product_name = PRODUCT
  target.package_product_dependencies << dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
  puts "Linked product #{PRODUCT} into #{TARGET_NAME}"
end

# 3. Entitlements (keychain capability) + deployment target on every config.
target.build_configurations.each do |config|
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = ENTITLEMENTS
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = MIN_IOS
end

project.save
puts "AppCoins SPM injection complete for #{TARGET_NAME}."
