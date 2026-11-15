#!/usr/bin/env python3
"""Generates RunSteady.xcodeproj. Source folders are file-system-synchronized groups,
so adding/removing Swift files never requires regenerating; rerun only to change targets/settings.

    python3 Config/generate_project.py
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = "com.runsteady.app"


def uid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def fmt(value, indent=2):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for k, v in value.items():
            lines.append(f"{pad}\t{k} = {fmt(v, indent + 1)};")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines = ["("]
        for v in value:
            lines.append(f"{pad}\t{fmt(v, indent + 1)},")
        lines.append(pad + ")")
        return "\n".join(lines)
    s = str(value)
    if s and all(c.isalnum() or c in "._/" for c in s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


objects = {}


def add(name, obj):
    key = uid(name)
    objects[key] = obj
    return key


# --- Groups -----------------------------------------------------------------
folders = ["Shared", "RunSteady", "RunSteadyWatch", "RunSteadyUITests", "RunSteadyWatchUITests"]
sync = {f: add("sync:" + f, {"isa": "PBXFileSystemSynchronizedRootGroup", "path": f, "sourceTree": "<group>"}) for f in folders}

products = {
    "RunSteady": ("RunSteady.app", "wrapper.application"),
    "RunSteadyWatch": ("RunSteadyWatch.app", "wrapper.application"),
    "RunSteadyUITests": ("RunSteadyUITests.xctest", "wrapper.cfbundle"),
    "RunSteadyWatchUITests": ("RunSteadyWatchUITests.xctest", "wrapper.cfbundle"),
}
product_refs = {
    t: add("product:" + t, {"isa": "PBXFileReference", "explicitFileType": kind, "includeInIndex": 0, "path": path,
                            "sourceTree": "BUILT_PRODUCTS_DIR"})
    for t, (path, kind) in products.items()
}
config_group = add("group:Config", {"isa": "PBXGroup", "path": "Config", "sourceTree": "<group>", "children": [
    add("file:watchplist", {"isa": "PBXFileReference", "lastKnownFileType": "text.plist.xml", "path": "Watch-Info.plist", "sourceTree": "<group>"}),
    add("file:watchent", {"isa": "PBXFileReference", "lastKnownFileType": "text.plist.entitlements", "path": "RunSteadyWatch.entitlements", "sourceTree": "<group>"}),
]})
products_group = add("group:Products", {"isa": "PBXGroup", "name": "Products", "sourceTree": "<group>", "children": list(product_refs.values())})
main_group = add("group:main", {"isa": "PBXGroup", "sourceTree": "<group>",
                                "children": list(sync.values()) + [config_group, products_group]})

# --- Package ----------------------------------------------------------------
package_ref = add("package", {"isa": "XCLocalSwiftPackageReference", "relativePath": "RunSteadyKit"})


def package_dep(target):
    dep = add("pkgdep:" + target, {"isa": "XCSwiftPackageProductDependency", "productName": "RunSteadyKit"})
    build_file = add("pkgbuild:" + target, {"isa": "PBXBuildFile", "productRef": dep})
    return dep, build_file


# --- Build settings ---------------------------------------------------------
common = {
    "SWIFT_VERSION": "5.0",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": 1,
    "MARKETING_VERSION": "1.0",
    "GENERATE_INFOPLIST_FILE": "YES",
}
ios = {**common, "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "TARGETED_DEVICE_FAMILY": 1}
watch = {**common, "SDKROOT": "watchos", "WATCHOS_DEPLOYMENT_TARGET": "10.0", "TARGETED_DEVICE_FAMILY": 4}

settings = {
    "RunSteady": {
        **ios,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "INFOPLIST_KEY_CFBundleDisplayName": "Run Steady",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "ENABLE_PREVIEWS": "YES",
    },
    "RunSteadyWatch": {
        **watch,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".watchkitapp",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "INFOPLIST_FILE": "Config/Watch-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Config/RunSteadyWatch.entitlements",
        "INFOPLIST_KEY_CFBundleDisplayName": "Run Steady",
        "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": BUNDLE,
        "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": "YES",
        "INFOPLIST_KEY_NSHealthShareUsageDescription": "Run Steady shows your heart rate and distance during a run.",
        "INFOPLIST_KEY_NSHealthUpdateUsageDescription": "Run Steady saves your run-walk workouts and routes to Apple Health.",
        "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "Run Steady records the route of your run.",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "SKIP_INSTALL": "YES",
        "ENABLE_PREVIEWS": "YES",
    },
    "RunSteadyUITests": {
        **ios,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".uitests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TEST_TARGET_NAME": "RunSteady",
    },
    "RunSteadyWatchUITests": {
        **watch,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".watchuitests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TEST_TARGET_NAME": "RunSteadyWatch",
    },
}


def config_list(name, base):
    configs = []
    for cfg in ("Debug", "Release"):
        s = dict(base)
        if name == "project":
            s.update({
                "ALWAYS_SEARCH_USER_PATHS": "NO",
                "CLANG_ENABLE_MODULES": "YES",
                "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
            })
            if cfg == "Debug":
                s.update({"ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "ENABLE_TESTABILITY": "YES",
                          "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "DEBUG_INFORMATION_FORMAT": "dwarf"})
            else:
                s.update({"SWIFT_COMPILATION_MODE": "wholemodule", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                          "VALIDATE_PRODUCT": "YES"})
        configs.append(add(f"cfg:{name}:{cfg}", {"isa": "XCBuildConfiguration", "name": cfg, "buildSettings": s}))
    return add("cfglist:" + name, {"isa": "XCConfigurationList", "buildConfigurations": configs,
                                   "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})


# --- Targets ----------------------------------------------------------------
project_id = uid("project")
target_ids = {t: uid("target:" + t) for t in products}


def dependency(owner, on):
    proxy = add(f"proxy:{owner}:{on}", {"isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": 1,
                                        "remoteGlobalIDString": target_ids[on], "remoteInfo": on})
    return add(f"dep:{owner}:{on}", {"isa": "PBXTargetDependency", "target": target_ids[on], "targetProxy": proxy})


def target(name, product_type, groups, deps=(), uses_package=False, extra_phases=()):
    frameworks_files = []
    package_deps = []
    if uses_package:
        dep, build_file = package_dep(name)
        package_deps.append(dep)
        frameworks_files.append(build_file)
    phases = [
        add("sources:" + name, {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0}),
        add("frameworks:" + name, {"isa": "PBXFrameworksBuildPhase", "buildActionMask": 2147483647, "files": frameworks_files, "runOnlyForDeploymentPostprocessing": 0}),
        add("resources:" + name, {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0}),
    ] + list(extra_phases)
    objects[target_ids[name]] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": config_list(name, settings[name]),
        "buildPhases": phases,
        "buildRules": [],
        "dependencies": [dependency(name, d) for d in deps],
        "fileSystemSynchronizedGroups": [sync[g] for g in groups],
        "name": name,
        "packageProductDependencies": package_deps,
        "productName": name,
        "productReference": product_refs[name],
        "productType": product_type,
    }


embed_file = add("embedfile:watch", {"isa": "PBXBuildFile", "fileRef": product_refs["RunSteadyWatch"],
                                     "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
embed_phase = add("embed:watch", {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": 2147483647,
                                  "dstPath": "$(CONTENTS_FOLDER_PATH)/Watch", "dstSubfolderSpec": 16, "files": [embed_file],
                                  "name": "Embed Watch Content", "runOnlyForDeploymentPostprocessing": 0})

target("RunSteadyWatch", "com.apple.product-type.application", ["Shared", "RunSteadyWatch"], uses_package=True)
target("RunSteady", "com.apple.product-type.application", ["Shared", "RunSteady"], deps=["RunSteadyWatch"],
       uses_package=True, extra_phases=[embed_phase])
target("RunSteadyUITests", "com.apple.product-type.bundle.ui-testing", ["RunSteadyUITests"], deps=["RunSteady"])
target("RunSteadyWatchUITests", "com.apple.product-type.bundle.ui-testing", ["RunSteadyWatchUITests"], deps=["RunSteadyWatch"])

objects[project_id] = {
    "isa": "PBXProject",
    "attributes": {"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 1620, "LastUpgradeCheck": 1620,
                   "TargetAttributes": {
                       target_ids["RunSteadyUITests"]: {"TestTargetID": target_ids["RunSteady"]},
                       target_ids["RunSteadyWatchUITests"]: {"TestTargetID": target_ids["RunSteadyWatch"]},
                   }},
    "buildConfigurationList": config_list("project", {}),
    "developmentRegion": "en",
    "hasScannedForEncodings": 0,
    "knownRegions": ["en", "Base"],
    "mainGroup": main_group,
    "minimizedProjectReferenceProxies": 1,
    "packageReferences": [package_ref],
    "preferredProjectObjectVersion": 77,
    "productRefGroup": products_group,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [target_ids[t] for t in ("RunSteady", "RunSteadyWatch", "RunSteadyUITests", "RunSteadyWatchUITests")],
}

body = "\n".join(f"\t\t{key} = {fmt(obj)};" for key, obj in sorted(objects.items(), key=lambda kv: (kv[1]["isa"], kv[0])))
pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{
{body}
\t}};
\trootObject = {project_id};
}}
"""


def scheme(app, tests):
    def ref(name):
        return (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" '
                f'BuildableName="{products[name][0]}" BlueprintName="{name}" ReferencedContainer="container:RunSteady.xcodeproj"/>')
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            {ref(app)}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            {ref(tests)}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {ref(app)}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {ref(app)}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
"""


proj_dir = os.path.join(ROOT, "RunSteady.xcodeproj")
schemes_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(schemes_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write(pbxproj)
for name, (app, tests) in {"RunSteady": ("RunSteady", "RunSteadyUITests"),
                           "RunSteadyWatch": ("RunSteadyWatch", "RunSteadyWatchUITests")}.items():
    with open(os.path.join(schemes_dir, name + ".xcscheme"), "w") as f:
        f.write(scheme(app, tests))
print("Wrote", proj_dir)
