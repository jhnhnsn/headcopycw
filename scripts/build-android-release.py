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
    match = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)", text, re.MULTILINE)
    if not match:
        sys.exit("ERROR: Could not parse version from pubspec.yaml")
    return match.group(1), match.group(2), match.group(3), int(match.group(4))


def bump_build_number():
    major, minor, patch, build = load_version_info()
    build += 1
    text = PUBSPEC.read_text()
    version_str = f"{major}.{minor}.{patch}+{build}"
    text = re.sub(r"^version:\s*\S+", f"version: {version_str}", text, count=1, flags=re.MULTILINE)
    PUBSPEC.write_text(text)
    return f"{major}.{minor}.{patch}", build


def build_apk():
    step(1, "Bumping build number and building APK/AAB (this may take a while)...")
    version, build = bump_build_number()
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
