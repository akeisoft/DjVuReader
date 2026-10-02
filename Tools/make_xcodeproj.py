#!/usr/bin/env python3
"""
Writes DjVuReader.xcodeproj (Xcode 16+ format with synchronized folders).

Not needed to build the app: the project is committed. Folders are
synchronized, so files added to Sources/, Resources/ or the DjVuLibre
sources appear in Xcode by themselves. Rerun only to change targets or
build settings: python3 Tools/make_xcodeproj.py
"""
import hashlib
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PROJECT = os.path.join(ROOT, "DjVuReader.xcodeproj")

APP_NAME = "DjVu Reader"
APP_PRODUCT = APP_NAME + ".app"
BUNDLE_ID = "com.akeisoft.djvureader"
VERSION = "0.3.1"
BUILD = "4"
MACOS = "14.0"


def oid(label):
    """Stable 24-hex object id derived from a label."""
    return hashlib.md5(("DjVuReader:" + label).encode()).hexdigest()[:24].upper()


def q(value):
    """Quotes a scalar the way Xcode does when needed."""
    s = str(value)
    if s and re.fullmatch(r"[A-Za-z0-9_./]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(value, indent):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append(f"{pad}\t{q(key)} = {render(item, indent + 1)};")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines = ["("]
        for item in value:
            lines.append(f"{pad}\t{render(item, indent + 1)},")
        lines.append(pad + ")")
        return "\n".join(lines)
    return q(value)


# ---------------------------------------------------------------- objects

ids = {name: oid(name) for name in [
    "project", "mainGroup", "productsGroup", "configGroup", "thirdPartyGroup", "djvuGroup", "djvuConfigGroup",
    "appTarget", "libTarget", "appProduct", "libProduct",
    "syncSources", "syncResources", "syncLibdjvu",
    "infoPlist", "entitlements", "configH", "osiFolder", "copying", "readme", "license",
    "appSources", "appFrameworks", "appResources", "libSources", "libFrameworks",
    "libInApp", "osiInApp", "proxy", "dependency",
    "projectConfigs", "projectDebug", "projectRelease",
    "appConfigs", "appDebug", "appRelease",
    "libConfigs", "libDebug", "libRelease",
]}
I = ids

objects = {}


def add(key, comment, body):
    objects[I[key]] = (comment, body)


add("appProduct", APP_PRODUCT, {
    "isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
    "path": APP_PRODUCT, "sourceTree": "BUILT_PRODUCTS_DIR"})
add("libProduct", "libDjVuLibre.a", {
    "isa": "PBXFileReference", "explicitFileType": "archive.ar", "includeInIndex": "0",
    "path": "libDjVuLibre.a", "sourceTree": "BUILT_PRODUCTS_DIR"})
add("infoPlist", "Info.plist", {
    "isa": "PBXFileReference", "lastKnownFileType": "text.plist.xml", "path": "Info.plist", "sourceTree": "<group>"})
add("entitlements", "DjVuReader.entitlements", {
    "isa": "PBXFileReference", "lastKnownFileType": "text.plist.entitlements",
    "path": "DjVuReader.entitlements", "sourceTree": "<group>"})
add("configH", "config.h", {
    "isa": "PBXFileReference", "lastKnownFileType": "sourcecode.c.h", "path": "config.h", "sourceTree": "<group>"})
add("osiFolder", "osi", {
    "isa": "PBXFileReference", "lastKnownFileType": "folder", "path": "osi", "sourceTree": "<group>"})
add("copying", "COPYING", {
    "isa": "PBXFileReference", "lastKnownFileType": "text", "path": "COPYING", "sourceTree": "<group>"})
add("readme", "README.md", {
    "isa": "PBXFileReference", "lastKnownFileType": "net.daringfireball.markdown", "path": "README.md",
    "sourceTree": "<group>"})
add("license", "LICENSE", {
    "isa": "PBXFileReference", "lastKnownFileType": "text", "path": "LICENSE", "sourceTree": "<group>"})

add("syncSources", "Sources", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Sources", "sourceTree": "<group>"})
add("syncResources", "Resources", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Resources", "sourceTree": "<group>"})
add("syncLibdjvu", "libdjvu", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "libdjvu", "sourceTree": "<group>"})

add("libInApp", "libDjVuLibre.a in Frameworks", {"isa": "PBXBuildFile", "fileRef": I["libProduct"]})
add("osiInApp", "osi in Resources", {"isa": "PBXBuildFile", "fileRef": I["osiFolder"]})


def phase(isa, files):
    return {"isa": isa, "buildActionMask": "2147483647", "files": files, "runOnlyForDeploymentPostprocessing": "0"}


add("appSources", "Sources", phase("PBXSourcesBuildPhase", []))
add("appFrameworks", "Frameworks", phase("PBXFrameworksBuildPhase", [I["libInApp"]]))
add("appResources", "Resources", phase("PBXResourcesBuildPhase", [I["osiInApp"]]))
add("libSources", "Sources", phase("PBXSourcesBuildPhase", []))
add("libFrameworks", "Frameworks", phase("PBXFrameworksBuildPhase", []))

add("mainGroup", None, {"isa": "PBXGroup", "children": [
    I["syncSources"], I["syncResources"], I["configGroup"], I["thirdPartyGroup"],
    I["readme"], I["license"], I["productsGroup"]], "sourceTree": "<group>"})
add("productsGroup", "Products", {"isa": "PBXGroup", "children": [I["appProduct"], I["libProduct"]],
                                  "name": "Products", "sourceTree": "<group>"})
add("configGroup", "Config", {"isa": "PBXGroup", "children": [I["infoPlist"], I["entitlements"]],
                              "path": "Config", "sourceTree": "<group>"})
add("thirdPartyGroup", "ThirdParty", {"isa": "PBXGroup", "children": [I["djvuGroup"]],
                                      "path": "ThirdParty", "sourceTree": "<group>"})
add("djvuGroup", "DjVuLibre", {"isa": "PBXGroup", "children": [
    I["djvuConfigGroup"], I["syncLibdjvu"], I["osiFolder"], I["copying"]],
    "path": "DjVuLibre", "sourceTree": "<group>"})
add("djvuConfigGroup", "config", {"isa": "PBXGroup", "children": [I["configH"]],
                                  "path": "config", "sourceTree": "<group>"})

add("proxy", "PBXContainerItemProxy", {
    "isa": "PBXContainerItemProxy", "containerPortal": I["project"], "proxyType": "1",
    "remoteGlobalIDString": I["libTarget"], "remoteInfo": "DjVuLibre"})
add("dependency", "PBXTargetDependency", {
    "isa": "PBXTargetDependency", "target": I["libTarget"], "targetProxy": I["proxy"]})

add("appTarget", "DjVuReader", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": I["appConfigs"],
    "buildPhases": [I["appSources"], I["appFrameworks"], I["appResources"]],
    "buildRules": [],
    "dependencies": [I["dependency"]],
    "fileSystemSynchronizedGroups": [I["syncSources"], I["syncResources"]],
    "name": "DjVuReader",
    "packageProductDependencies": [],
    "productName": "DjVuReader",
    "productReference": I["appProduct"],
    "productType": "com.apple.product-type.application"})
add("libTarget", "DjVuLibre", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": I["libConfigs"],
    "buildPhases": [I["libSources"], I["libFrameworks"]],
    "buildRules": [],
    "dependencies": [],
    "fileSystemSynchronizedGroups": [I["syncLibdjvu"]],
    "name": "DjVuLibre",
    "packageProductDependencies": [],
    "productName": "DjVuLibre",
    "productReference": I["libProduct"],
    "productType": "com.apple.product-type.library.static"})

# ---------------------------------------------------------------- build settings

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++17",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": MACOS,
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "macosx",
}
project_debug = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
})

app = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": "Config/DjVuReader.entitlements",
    # "Sign to Run Locally"; choose your team in Signing & Capabilities for releases.
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": BUILD,
    "DEAD_CODE_STRIPPING": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "HEADER_SEARCH_PATHS": ["$(SRCROOT)/ThirdParty/DjVuLibre"],
    "INFOPLIST_FILE": "Config/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "MARKETING_VERSION": VERSION,
    "OTHER_LDFLAGS": ["$(inherited)", "-lc++", "-liconv", "-framework", "CoreFoundation"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_MODULE_NAME": "DjVuReader",
    "PRODUCT_NAME": APP_NAME,
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_OBJC_BRIDGING_HEADER": "Sources/Engine/DjVuReader-Bridging-Header.h",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "SWIFT_VERSION": "5.0",
}
lib = {
    "CODE_SIGN_STYLE": "Automatic",
    "EXECUTABLE_PREFIX": "lib",
    # DjVuLibre's own code: always optimized (decoding speed in Debug builds too),
    # its many legacy warnings hidden so the issue list shows only app problems.
    "GCC_OPTIMIZATION_LEVEL": "s",
    "GCC_PREPROCESSOR_DEFINITIONS": ["HAVE_CONFIG_H=1", "NDEBUG=1"],
    "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
    "HEADER_SEARCH_PATHS": ["$(SRCROOT)/ThirdParty/DjVuLibre/config"],
    # atomic, debug, DjVuGlobalMemory and JPEGDecoder compile to nothing in this
    # configuration (builtin atomics, NDEBUG, no custom allocator, no JPEG); without
    # this flag libtool warns "has no symbols" for each of them.
    "OTHER_LIBTOOLFLAGS": "-no_warning_for_no_symbols",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES",
}


def config(key, name, settings):
    add(key, name, {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": name})


config("projectDebug", "Debug", project_debug)
config("projectRelease", "Release", project_release)
config("appDebug", "Debug", dict(app))
config("appRelease", "Release", dict(app))
config("libDebug", "Debug", dict(lib))
config("libRelease", "Release", dict(lib))


def config_list(key, comment, debug, release):
    add(key, comment, {"isa": "XCConfigurationList", "buildConfigurations": [I[debug], I[release]],
                       "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"})


config_list("projectConfigs", 'Build configuration list for PBXProject "DjVuReader"', "projectDebug", "projectRelease")
config_list("appConfigs", 'Build configuration list for PBXNativeTarget "DjVuReader"', "appDebug", "appRelease")
config_list("libConfigs", 'Build configuration list for PBXNativeTarget "DjVuLibre"', "libDebug", "libRelease")

add("project", "Project object", {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "1600",
        "LastUpgradeCheck": "1600",
        "TargetAttributes": {
            I["appTarget"]: {"CreatedOnToolsVersion": "16.0"},
            I["libTarget"]: {"CreatedOnToolsVersion": "16.0"},
        },
    },
    "buildConfigurationList": I["projectConfigs"],
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base", "uk", "ru"],
    "mainGroup": I["mainGroup"],
    "minimizedProjectReferenceProxies": "1",
    "preferredProjectObjectVersion": "77",
    "productRefGroup": I["productsGroup"],
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [I["appTarget"], I["libTarget"]],
})

# ---------------------------------------------------------------- output

comments = {oid_: c for oid_, (c, _) in objects.items() if c}


def annotate(text):
    """Adds Xcode-style /* name */ comments after object ids."""
    def sub(m):
        name = comments.get(m.group(0))
        return f"{m.group(0)} /* {name} */" if name else m.group(0)
    return re.sub(r"\b[0-9A-F]{24}\b", sub, text)


sections = {}
for object_id, (comment, body) in objects.items():
    sections.setdefault(body["isa"], []).append((object_id, comment, body))

lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {", ""]
for isa in sorted(sections):
    lines.append(f"/* Begin {isa} section */")
    for object_id, comment, body in sorted(sections[isa]):
        rendered = render(body, 2)
        if isa in ("PBXBuildFile", "PBXFileReference"):  # one-line form, like Xcode
            rendered = "{" + " ".join(f"{q(k)} = {render(v, 0)};" for k, v in body.items()) + " }"
        lines.append(f"\t\t{object_id} = {rendered};")
    lines.append(f"/* End {isa} section */")
    lines.append("")
lines += ["\t};", f"\trootObject = {I['project']};", "}", ""]
pbxproj = annotate("\n".join(lines))

os.makedirs(os.path.join(PROJECT, "project.xcworkspace", "xcshareddata"), exist_ok=True)
os.makedirs(os.path.join(PROJECT, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(PROJECT, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write(pbxproj)

with open(os.path.join(PROJECT, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
            '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

# Only the shared scheme below: no auto-created "DjVuLibre" scheme to pick by mistake.
with open(os.path.join(PROJECT, "project.xcworkspace", "xcshareddata", "WorkspaceSettings.xcsettings"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n'
            '\t<key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>\n\t<false/>\n'
            '</dict>\n</plist>\n')

ref = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I['appTarget']}"
               BuildableName = "{APP_PRODUCT}"
               BlueprintName = "DjVuReader"
               ReferencedContainer = "container:DjVuReader.xcodeproj">
            </BuildableReference>'''
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
with open(os.path.join(PROJECT, "xcshareddata", "xcschemes", "DjVuReader.xcscheme"), "w") as f:
    f.write(scheme)
print("wrote", os.path.relpath(PROJECT, ROOT))
