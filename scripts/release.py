#!/usr/bin/env python3
"""Bump version/build numbers and tag the release in git.

Usage:
    ./release.py patch       # 1.0.0 → 1.0.1
    ./release.py minor       # 1.0.0 → 1.1.0
    ./release.py major       # 1.0.0 → 2.0.0
    ./release.py build       # bump build number only (no version change)
    ./release.py             # show current version
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"


def load_version():
    text = PUBSPEC.read_text()
    match = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)", text, re.MULTILINE)
    if not match:
        sys.exit("ERROR: Could not parse version from pubspec.yaml")
    return {
        "major": int(match.group(1)),
        "minor": int(match.group(2)),
        "patch": int(match.group(3)),
        "build": int(match.group(4)),
    }


def save_version(v):
    text = PUBSPEC.read_text()
    version_str = f"{v['major']}.{v['minor']}.{v['patch']}+{v['build']}"
    text = re.sub(r"^version:\s*\S+", f"version: {version_str}", text, count=1, flags=re.MULTILINE)
    PUBSPEC.write_text(text)


def version_string(v):
    return f"{v['major']}.{v['minor']}.{v['patch']}"


def bump(part):
    v = load_version()

    if part == "major":
        v["major"] += 1
        v["minor"] = 0
        v["patch"] = 0
    elif part == "minor":
        v["minor"] += 1
        v["patch"] = 0
    elif part == "patch":
        v["patch"] += 1

    v["build"] += 1
    save_version(v)
    return v


def bump_build():
    v = load_version()
    v["build"] += 1
    save_version(v)
    return v


def tag_release(v):
    version = version_string(v)
    build = v["build"]
    tag = f"v{version}"
    msg = f"Release {version} (build {build})"

    subprocess.run(["git", "add", str(PUBSPEC)], cwd=ROOT, check=True)
    subprocess.run(["git", "commit", "-m", msg], cwd=ROOT, check=True)
    subprocess.run(["git", "tag", "-a", tag, "-m", msg], cwd=ROOT, check=True)

    print(f"\n  Version: {version}")
    print(f"  Build:   {build}")
    print(f"  Tag:     {tag}")
    print(f"\n  Run 'git push && git push --tags' to publish.")


def main():
    if len(sys.argv) < 2:
        v = load_version()
        print(f"  Version: {version_string(v)}")
        print(f"  Build:   {v['build']}")
        return

    part = sys.argv[1]
    if part in ("major", "minor", "patch"):
        v = bump(part)
        tag_release(v)
    elif part == "build":
        v = bump_build()
        tag_release(v)
    else:
        print(f"Unknown: {part}")
        print("Usage: ./release.py [major|minor|patch|build]")
        sys.exit(1)


if __name__ == "__main__":
    main()
