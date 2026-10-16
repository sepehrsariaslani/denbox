#!/usr/bin/env python3
"""Download the private v0.2.10 bootstrap DMG without exposing its token."""

from __future__ import annotations

import base64
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys


ASSET_URL = (
    "https://github.com/sepehrsariaslani/denbox/releases/download/v0.2.10/"
    "Denbox-0.2.10-build44-macOS-arm64.dmg"
)
EXPECTED_SHA256 = "bded999ad038fb240db1a1c5579ee5638213a870ff933577702cd4ec3ae40816"


def github_credentials() -> tuple[str, str] | None:
    if shutil.which("gh"):
        try:
            result = subprocess.run(
                ["gh", "auth", "token", "--hostname", "github.com"],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            token = result.stdout.strip()
            if result.returncode == 0 and token:
                return "x-access-token", token
        except (OSError, subprocess.TimeoutExpired):
            pass

    try:
        result = subprocess.run(
            ["git", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n",
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    fields = dict(
        line.split("=", 1)
        for line in result.stdout.splitlines()
        if "=" in line
    )
    username = fields.get("username", "")
    token = fields.get("password", "")
    return (username, token) if username and token else None


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: download-private-build-keys.py /path/to/bootstrap.dmg", file=sys.stderr)
        return 2

    credentials = github_credentials()
    if credentials is None:
        print(
            "Private API bootstrap needs GitHub access. Sign in with `gh auth login` "
            "or configure saved HTTPS Git credentials for this private repository.",
            file=sys.stderr,
        )
        return 1

    destination = Path(sys.argv[1]).expanduser()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.unlink(missing_ok=True)
    username, token = credentials
    basic = base64.b64encode(f"{username}:{token}".encode("utf-8")).decode("ascii")
    config = f'header = "Authorization: Basic {basic}"\n'
    try:
        result = subprocess.run(
            [
                "/usr/bin/curl",
                "--fail",
                "--location",
                "--proto",
                "=https",
                "--proto-redir",
                "=https",
                "--silent",
                "--show-error",
                "--max-time",
                "300",
                "--output",
                str(destination),
                "--write-out",
                "%{http_code}",
                "--config",
                "-",
                ASSET_URL,
            ],
            input=config,
            capture_output=True,
            text=True,
            timeout=320,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        destination.unlink(missing_ok=True)
        print("Could not retrieve the private Denbox bootstrap DMG.", file=sys.stderr)
        return 1

    if result.returncode != 0:
        destination.unlink(missing_ok=True)
        status = result.stdout.strip()
        suffix = f" (HTTP {status})" if status.isdigit() else ""
        print(
            "Could not retrieve the private Denbox bootstrap DMG" + suffix + ". "
            "Confirm this GitHub account can access the Denbox private release.",
            file=sys.stderr,
        )
        return 1

    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        destination.unlink(missing_ok=True)
        print("The private bootstrap DMG failed its SHA-256 integrity check.", file=sys.stderr)
        return 1

    destination.chmod(0o600)
    print("Retrieved and verified the private API bootstrap; credential values were not displayed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
