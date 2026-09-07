#!/usr/bin/env python3
"""Run the app's real decoding types against complete and incomplete date fixtures."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="rocketlaunch-decoding-") as folder:
    binary = str(Path(folder) / "decoding-checks")
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5",
        "-module-cache-path", str(Path(folder) / "cache"),
        str(root / "RocketLaunch/2 - AppModel/Features/Launch Schedule/RocketLaunchDataTypes.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", binary
    ], check=True)
    subprocess.run([binary, str(root / "RocketLaunch/3 - App Resources/TestData.json")], check=True)
