#!/usr/bin/env python3
"""Head Copy CW Trainer Android Release Build — builds APK and AAB."""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST_DIR = ROOT / "dist"
PUBSPEC = ROOT / "pubspec.yaml"

TOTAL_STEPS = 3


def step(num, msg):
    print(f"\n[{num}/{TOTAL_STEPS}] {msg}")


def load_version_info():
    text = PUBSPEC.read_text()
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)", text, re.MULTILINE)
    if not match:
        sys.exit("ERROR: Could not parse version from pubspec.yaml")
    return match.group(1), int(match.group(2))


def build_apk():
    step(1, "Building APK and AAB with Flutter (this may take a while)...")
    version, build = load_version_info()
    print(f"       Version: {version} (build {build})")

    for target in ["apk", "appbundle"]:
        cmd = [
            "flutter", "build", target,
            "--release",
            f"--build-name={version}",
            f"--build-number={build}",
        ]
        result = subprocess.run(cmd, cwd=ROOT)
        if result.returncode != 0:
            sys.exit(f"ERROR: flutter build {target} failed")

    print("       Done: Build complete")


def print_summary():
    step(2, "Collecting outputs...")
    DIST_DIR.mkdir(exist_ok=True)
    version, build = load_version_info()

    apk_path = ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    aab_path = ROOT / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"

    step(3, "Done!")
    print()
    print("=" * 40)
    print(" SUCCESS")
    print("=" * 40)

    if apk_path.exists():
        dest = DIST_DIR / f"HeadCopyCW-{version}-{build}.apk"
        shutil.copy2(apk_path, dest)
        print(f"\n  APK: {dest}")
    else:
        print("\n  APK: NOT FOUND")

    if aab_path.exists():
        dest = DIST_DIR / f"HeadCopyCW-{version}-{build}.aab"
        shutil.copy2(aab_path, dest)
        print(f"  AAB: {dest}")
    else:
        print("  AAB: NOT FOUND")

    if apk_path.exists():
        print(f"\n  Install APK: adb install -r \"{apk_path}\"")
    print()


def main():
    print("=" * 40)
    print(" Head Copy CW Trainer Android Release Build")
    print("=" * 40)

    build_apk()
    print_summary()


if __name__ == "__main__":
    main()
