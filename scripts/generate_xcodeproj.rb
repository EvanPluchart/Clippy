#!/usr/bin/env ruby
# Generates the dependency-free Xcode project from the repository layout.
require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
PROJECT_DIR = File.join(ROOT, "Clippy.xcodeproj")
APP_SOURCES = Dir.glob(File.join(ROOT, "Clippy/**/*.swift")).sort.map { |p| p.delete_prefix(ROOT + "/") }
TEST_SOURCES = Dir.glob(File.join(ROOT, "ClippyTests/**/*.swift")).sort.map { |p| p.delete_prefix(ROOT + "/") }

def xid(value)
  Digest::SHA1.hexdigest("Clippy.#{value}").upcase[0, 24]
end

app_target = xid("target.app")
test_target = xid("target.tests")
project = xid("project")
main_group = xid("group.main")
app_group = xid("group.app")
test_group = xid("group.tests")
resource_group = xid("group.resources")
product_group = xid("group.products")
app_product = xid("product.app")
test_product = xid("product.tests")
app_sources_phase = xid("phase.app.sources")
app_resources_phase = xid("phase.app.resources")
app_frameworks_phase = xid("phase.app.frameworks")
test_sources_phase = xid("phase.tests.sources")
test_resources_phase = xid("phase.tests.resources")
test_frameworks_phase = xid("phase.tests.frameworks")
container_proxy = xid("proxy.tests.app")
target_dependency = xid("dependency.tests.app")
project_config_list = xid("configlist.project")
app_config_list = xid("configlist.app")
test_config_list = xid("configlist.tests")

resource_paths = ["Clippy/Resources/Info.plist", "Clippy/Resources/Clippy.entitlements", "Clippy/Resources/ClippyDebug.entitlements", "Clippy/Resources/PrivacyInfo.xcprivacy", "Clippy/Resources/Assets.xcassets"]
all_files = APP_SOURCES + TEST_SOURCES + resource_paths

file_refs = all_files.map do |path|
  type = if path.end_with?(".swift") then "sourcecode.swift"
         elsif path.end_with?(".xcassets") then "folder.assetcatalog"
         elsif path.end_with?(".plist") then "text.plist.xml"
         elsif path.end_with?(".entitlements") then "text.plist.entitlements"
         else "text.xml" end
  "\t\t#{xid("fileref.#{path}")} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = \"#{path}\"; sourceTree = SOURCE_ROOT; };"
end
file_refs << "\t\t#{app_product} /* Clippy.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Clippy.app; sourceTree = BUILT_PRODUCTS_DIR; };"
file_refs << "\t\t#{test_product} /* ClippyTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ClippyTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };"

build_files = (APP_SOURCES + TEST_SOURCES + ["Clippy/Resources/PrivacyInfo.xcprivacy", "Clippy/Resources/Assets.xcassets"]).map do |path|
  phase = path.start_with?("ClippyTests") ? "Sources" : (path.end_with?(".swift") ? "Sources" : "Resources")
  "\t\t#{xid("buildfile.#{path}")} /* #{File.basename(path)} in #{phase} */ = {isa = PBXBuildFile; fileRef = #{xid("fileref.#{path}")} /* #{File.basename(path)} */; };"
end

group_children = ->(paths) { paths.map { |p| "\t\t\t\t#{xid("fileref.#{p}")} /* #{File.basename(p)} */," }.join("\n") }
phase_files = ->(paths, name) { paths.map { |p| "\t\t\t\t#{xid("buildfile.#{p}")} /* #{File.basename(p)} in #{name} */," }.join("\n") }

config = lambda do |id, name, settings|
  lines = settings.map { |key, value| "\t\t\t\t#{key} = #{value};" }.join("\n")
  "\t\t#{id} /* #{name} */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n#{lines}\n\t\t\t};\n\t\t\tname = #{name};\n\t\t};"
end

project_settings = {
  "ALWAYS_SEARCH_USER_PATHS" => "NO", "CLANG_ENABLE_MODULES" => "YES", "CLANG_ENABLE_OBJC_ARC" => "YES",
  "CLANG_ENABLE_OBJC_WEAK" => "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS" => "YES",
  "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER" => "YES", "ENABLE_USER_SCRIPT_SANDBOXING" => "YES",
  "GCC_WARN_64_TO_32_BIT_CONVERSION" => "YES", "GCC_WARN_UNDECLARED_SELECTOR" => "YES",
  "GCC_WARN_UNINITIALIZED_AUTOS" => "YES_AGGRESSIVE", "GCC_WARN_UNUSED_FUNCTION" => "YES",
  "GCC_WARN_UNUSED_VARIABLE" => "YES", "MACOSX_DEPLOYMENT_TARGET" => "14.0", "SDKROOT" => "macosx",
  "SWIFT_STRICT_CONCURRENCY" => "complete", "SWIFT_TREAT_WARNINGS_AS_ERRORS" => "YES", "SWIFT_VERSION" => "6.0"
}
app_settings = {
  "CODE_SIGN_ENTITLEMENTS" => "Clippy/Resources/Clippy.entitlements", "CODE_SIGN_STYLE" => "Automatic",
  "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
  "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS" => "YES",
  "COMBINE_HIDPI_IMAGES" => "YES", "CURRENT_PROJECT_VERSION" => "7", "DEVELOPMENT_TEAM" => '""',
  "ENABLE_APP_SANDBOX" => "NO", "ENABLE_HARDENED_RUNTIME" => "YES",
  "GENERATE_INFOPLIST_FILE" => "NO", "INFOPLIST_FILE" => "Clippy/Resources/Info.plist",
  "LD_RUNPATH_SEARCH_PATHS" => '"$(inherited) @executable_path/../Frameworks"', "MARKETING_VERSION" => "1.2.0",
  "PRODUCT_BUNDLE_IDENTIFIER" => "com.evpl.clippy", "PRODUCT_NAME" => '"$(TARGET_NAME)"', "SWIFT_EMIT_LOC_STRINGS" => "YES"
}
test_settings = {
  "BUNDLE_LOADER" => '"$(TEST_HOST)"', "CODE_SIGN_STYLE" => "Automatic", "GENERATE_INFOPLIST_FILE" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0", "PRODUCT_BUNDLE_IDENTIFIER" => "com.evpl.clippy.tests",
  "PRODUCT_NAME" => '"$(TARGET_NAME)"', "SWIFT_STRICT_CONCURRENCY" => "complete",
  "SWIFT_TREAT_WARNINGS_AS_ERRORS" => "YES", "SWIFT_VERSION" => "6.0",
  "TEST_HOST" => '"$(BUILT_PRODUCTS_DIR)/Clippy.app/Contents/MacOS/Clippy"'
}

configs = []
%w[Debug Release].each do |name|
  project_configuration = project_settings.merge(
    "DEBUG_INFORMATION_FORMAT" => name == "Debug" ? "dwarf" : '"dwarf-with-dsym"',
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => name == "Debug" ? '"DEBUG $(inherited)"' : '"$(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL" => name == "Debug" ? '"-Onone"' : '"-O"'
  )
  configs << config.call(xid("config.project.#{name}"), name, project_configuration)
  entitlement = name == "Debug" ? "Clippy/Resources/ClippyDebug.entitlements" : "Clippy/Resources/Clippy.entitlements"
  release_settings = name == "Debug" ? {
    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS" => "YES",
    "ENABLE_TESTABILITY" => "YES"
  } : {
    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS" => "NO",
    "COPY_PHASE_STRIP" => "YES",
    "DEAD_CODE_STRIPPING" => "YES",
    "ENABLE_TESTABILITY" => "NO",
    "STRIP_INSTALLED_PRODUCT" => "YES",
    "SWIFT_COMPILATION_MODE" => "wholemodule",
    "VALIDATE_PRODUCT" => "YES"
  }
  configs << config.call(
    xid("config.app.#{name}"),
    name,
    app_settings.merge(release_settings).merge("CODE_SIGN_ENTITLEMENTS" => entitlement)
  )
  configs << config.call(xid("config.tests.#{name}"), name, test_settings)
end

pbx = <<~PBX
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
#{build_files.join("\n")}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		#{container_proxy} = {isa = PBXContainerItemProxy; containerPortal = #{project}; proxyType = 1; remoteGlobalIDString = #{app_target}; remoteInfo = Clippy; };
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
#{file_refs.join("\n")}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		#{app_frameworks_phase} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
		#{test_frameworks_phase} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		#{main_group} = {isa = PBXGroup; children = (#{app_group}, #{test_group}, #{resource_group}, #{product_group}); sourceTree = "<group>"; };
		#{app_group} = {isa = PBXGroup; children = (
#{group_children.call(APP_SOURCES)}
			); name = Clippy; sourceTree = "<group>"; };
		#{test_group} = {isa = PBXGroup; children = (
#{group_children.call(TEST_SOURCES)}
			); name = ClippyTests; sourceTree = "<group>"; };
		#{resource_group} = {isa = PBXGroup; children = (
#{group_children.call(resource_paths)}
			); name = Resources; sourceTree = "<group>"; };
		#{product_group} = {isa = PBXGroup; children = (#{app_product}, #{test_product}); name = Products; sourceTree = "<group>"; };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		#{app_target} = {isa = PBXNativeTarget; buildConfigurationList = #{app_config_list}; buildPhases = (#{app_sources_phase}, #{app_frameworks_phase}, #{app_resources_phase}); buildRules = (); dependencies = (); name = Clippy; productName = Clippy; productReference = #{app_product}; productType = "com.apple.product-type.application"; };
		#{test_target} = {isa = PBXNativeTarget; buildConfigurationList = #{test_config_list}; buildPhases = (#{test_sources_phase}, #{test_frameworks_phase}, #{test_resources_phase}); buildRules = (); dependencies = (#{target_dependency}); name = ClippyTests; productName = ClippyTests; productReference = #{test_product}; productType = "com.apple.product-type.bundle.unit-test"; };
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		#{project} = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; TargetAttributes = {#{app_target} = {CreatedOnToolsVersion = 26.6;}; #{test_target} = {CreatedOnToolsVersion = 26.6; TestTargetID = #{app_target};};};}; buildConfigurationList = #{project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, Base); mainGroup = #{main_group}; productRefGroup = #{product_group}; projectDirPath = ""; projectRoot = ""; targets = (#{app_target}, #{test_target}); };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		#{app_resources_phase} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (
#{phase_files.call(["Clippy/Resources/PrivacyInfo.xcprivacy", "Clippy/Resources/Assets.xcassets"], "Resources")}
			); runOnlyForDeploymentPostprocessing = 0; };
		#{test_resources_phase} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		#{app_sources_phase} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (
#{phase_files.call(APP_SOURCES, "Sources")}
			); runOnlyForDeploymentPostprocessing = 0; };
		#{test_sources_phase} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (
#{phase_files.call(TEST_SOURCES, "Sources")}
			); runOnlyForDeploymentPostprocessing = 0; };
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		#{target_dependency} = {isa = PBXTargetDependency; target = #{app_target}; targetProxy = #{container_proxy}; };
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
#{configs.join("\n")}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		#{project_config_list} = {isa = XCConfigurationList; buildConfigurations = (#{xid("config.project.Debug")}, #{xid("config.project.Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
		#{app_config_list} = {isa = XCConfigurationList; buildConfigurations = (#{xid("config.app.Debug")}, #{xid("config.app.Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
		#{test_config_list} = {isa = XCConfigurationList; buildConfigurations = (#{xid("config.tests.Debug")}, #{xid("config.tests.Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
/* End XCConfigurationList section */
	};
	rootObject = #{project};
}
PBX

FileUtils.mkdir_p(File.join(PROJECT_DIR, "xcshareddata/xcschemes"))
File.write(File.join(PROJECT_DIR, "project.pbxproj"), pbx)

scheme = <<~XML
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{app_target}" BuildableName="Clippy.app" BlueprintName="Clippy" ReferencedContainer="container:Clippy.xcodeproj"/></BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{test_target}" BuildableName="ClippyTests.xctest" BlueprintName="ClippyTests" ReferencedContainer="container:Clippy.xcodeproj"/></BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{test_target}" BuildableName="ClippyTests.xctest" BlueprintName="ClippyTests" ReferencedContainer="container:Clippy.xcodeproj"/></TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{app_target}" BuildableName="Clippy.app" BlueprintName="Clippy" ReferencedContainer="container:Clippy.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{app_target}" BuildableName="Clippy.app" BlueprintName="Clippy" ReferencedContainer="container:Clippy.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
XML
File.write(File.join(PROJECT_DIR, "xcshareddata/xcschemes/Clippy.xcscheme"), scheme)
puts "Generated Clippy.xcodeproj with #{APP_SOURCES.count} app sources and #{TEST_SOURCES.count} test sources."
