#!/usr/bin/env python3
"""Run the same XCTest source files on macOS when an iOS simulator is unavailable.

This checks Model/ViewModel behaviour. It does not execute the app's SwiftUI views.
The temporary package is generated from the current app sources on each run.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="rocketlaunch-host-tests-") as directory:
    package = Path(directory)
    production = package / "Sources/RocketLaunch"
    production.mkdir(parents=True)
    # Include the real Model sources and each screen's real ViewModel.
    sources = list((root / "RocketLaunch/2 - AppModel").rglob("*.swift"))
    sources += list((root / "RocketLaunch/1 - View").rglob("*ViewModel.swift"))
    for source in sources:
        destination = production / source.relative_to(root / "RocketLaunch")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    shutil.copytree(root / "RocketLaunchTests", package / "Tests/RocketLaunchTests")
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "RocketLaunchHostChecks",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "RocketLaunch"),
        .testTarget(name: "RocketLaunchTests", dependencies: ["RocketLaunch"],
                    resources: [.process("Fixtures")])
    ]
)
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "module-cache")
    subprocess.run([
        "xcrun", "swift", "test", "--disable-sandbox", "--package-path", str(package),
        "--scratch-path", str(package / "build"), "--cache-path", str(package / "cache"),
        "--config-path", str(package / "config"), "--security-path", str(package / "security")
    ], check=True, env=environment)
