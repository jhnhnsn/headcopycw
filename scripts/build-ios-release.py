#!/usr/bin/env python3
"""Head Copy CW Trainer iOS Release Build — builds IPA and uploads to TestFlight."""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST_DIR = ROOT / "dist"
EXPORT_OPTIONS = ROOT / "ExportOptions.plist"
PUBSPEC = ROOT / "pubspec.yaml"
SECRETS_FILE = ROOT / ".build-secrets.json"

TEAM_ID = "B9DZPLYB8W"
BUNDLE_ID = "com.headcopycw.app"

TOTAL_STEPS = 4


def step(num, msg):
    print(f"\n[{num}/{TOTAL_STEPS}] {msg}")


# --- Secrets (plain JSON) ---

def load_secrets() -> dict:
    if SECRETS_FILE.exists():
        return json.loads(SECRETS_FILE.read_text())

    print("\n  No secrets file found — let's create one.")
    api_key_id = input("  App Store Connect Key ID: ").strip()
    api_issuer_id = input("  App Store Connect Issuer ID: ").strip()

    if not api_key_id or not api_issuer_id:
        sys.exit("ERROR: All fields are required.")

    secrets = {
        "api_key_id": api_key_id,
        "api_issuer_id": api_issuer_id,
    }

    SECRETS_FILE.write_text(json.dumps(secrets, indent=4) + "\n")
    print(f"       Secrets saved to {SECRETS_FILE.name}")
    return secrets


# --- Version ---

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
    return f"{major}.{minor}.{patch}", str(build)


# --- Build steps ---

def build_ipa():
    step(1, "Bumping build number and building IPA (this may take a while)...")
    marketing_version, build_number = bump_build_number()
    print(f"       Version: {marketing_version} (build {build_number})")

    DIST_DIR.mkdir(exist_ok=True)

    cmd = [
        "flutter", "build", "ipa",
        "--release",
        f"--build-name={marketing_version}",
        f"--build-number={build_number}",
        f"--export-options-plist={EXPORT_OPTIONS}",
    ]

    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode != 0:
        sys.exit("ERROR: flutter build ipa failed")
    print("       Done: IPA built")


def find_ipa():
    ipa_dir = ROOT / "build" / "ios" / "ipa"
    ipa_files = list(ipa_dir.glob("*.ipa")) if ipa_dir.exists() else []
    if not ipa_files:
        sys.exit(f"ERROR: IPA not found in {ipa_dir}")
    return ipa_files[0]


def upload_to_testflight(secrets: dict):
    step(2, "Uploading to TestFlight...")
    ipa = find_ipa()
    print(f"       IPA: {ipa.name}")

    key_id = secrets["api_key_id"]
    key_file = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"
    if not key_file.exists():
        sys.exit(
            f"ERROR: API key not found at {key_file}\n"
            f"       Copy your .p8 file there and rename it to AuthKey_{key_id}.p8"
        )

    print("       Validating...")
    validate_cmd = [
        "xcrun", "altool",
        "--validate-app",
        "--type", "ios",
        "--file", str(ipa),
        "--apiKey", key_id,
        "--apiIssuer", secrets["api_issuer_id"],
    ]

    result = subprocess.run(validate_cmd)
    if result.returncode != 0:
        sys.exit("ERROR: Validation failed — fix the issues above before uploading")

    print("       Uploading...")
    upload_cmd = [
        "xcrun", "altool",
        "--upload-app",
        "--type", "ios",
        "--file", str(ipa),
        "--apiKey", key_id,
        "--apiIssuer", secrets["api_issuer_id"],
    ]

    result = subprocess.run(upload_cmd)
    if result.returncode != 0:
        sys.exit("ERROR: Upload to TestFlight failed")
    print("       Done: Uploaded to App Store Connect!")


def print_summary():
    step(3, "Done!")
    ipa = find_ipa()
    print()
    print("=" * 40)
    print(" SUCCESS")
    print("=" * 40)
    print(f"\n  IPA: {ipa}")
    print()
    print("  Your build has been uploaded to App Store Connect.")
    print("  It may take 15-30 minutes to process before appearing in TestFlight.")
    print()


# --- Status check ---

def _generate_jwt(secrets: dict) -> str:
    try:
        import jwt as pyjwt
    except ImportError:
        print("Installing required dependency: PyJWT[crypto]...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "PyJWT[crypto]"])
        import jwt as pyjwt

    key_id = secrets["api_key_id"]
    key_file = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"
    if not key_file.exists():
        sys.exit(
            f"ERROR: API key not found at {key_file}\n"
            f"       Copy your .p8 file there and rename it to AuthKey_{key_id}.p8"
        )

    now = int(time.time())
    payload = {
        "iss": secrets["api_issuer_id"],
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }
    return pyjwt.encode(payload, key_file.read_text(), algorithm="ES256", headers={"kid": key_id})


def check_status(secrets: dict):
    """Check recent build status on App Store Connect."""
    token = _generate_jwt(secrets)
    headers = {"Authorization": f"Bearer {token}"}

    app_url = f"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={BUNDLE_ID}"
    app_req = urllib.request.Request(app_url, headers=headers)
    try:
        with urllib.request.urlopen(app_req) as resp:
            app_data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"ERROR: App Store Connect API returned {e.code}\n{e.read().decode()}")

    apps = app_data.get("data", [])
    if not apps:
        sys.exit(f"ERROR: No app found with bundle ID {BUNDLE_ID}")
    app_id = apps[0]["id"]

    url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5"
    req = urllib.request.Request(url, headers=headers)

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        sys.exit(f"ERROR: App Store Connect API returned {e.code}\n{body}")

    builds = data.get("data", [])
    if not builds:
        print("No builds found.")
        return

    print(f"\n  {'Version':<12} {'Build':<16} {'Status':<24} {'Uploaded'}")
    print(f"  {'-'*12} {'-'*16} {'-'*24} {'-'*20}")
    for build in builds:
        attrs = build["attributes"]
        version = attrs.get("version", "?")
        processing = attrs.get("processingState", "?")
        uploaded = attrs.get("uploadedDate", "?")[:19].replace("T", " ")
        print(f"  {version:<12} {attrs.get('buildNumber', '?'):<16} {processing:<24} {uploaded}")
    print()


def main():
    parser = argparse.ArgumentParser(description="Head Copy CW Trainer iOS Release Build")
    parser.add_argument("--status", action="store_true", help="Check recent build status on App Store Connect")
    args = parser.parse_args()

    if args.status:
        secrets = load_secrets()
        check_status(secrets)
        return

    print("=" * 40)
    print(" Head Copy CW Trainer iOS Release Build")
    print("=" * 40)

    secrets = load_secrets()

    os.chdir(ROOT)
    build_ipa()
    upload_to_testflight(secrets)
    print_summary()


if __name__ == "__main__":
    main()
