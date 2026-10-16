#!/usr/bin/env python3
"""Embed this Mac's Denbox Keychain credentials into a private app bundle.

The resulting resource is intentionally extractable from the app. Use only for
private releases whose recipients are trusted with these shared API keys.
Credential values are never written to the source tree or printed.
"""

from pathlib import Path
import plistlib
import subprocess
import sys


SERVICE = "com.sepehr.SimbaMac.media-api"
REQUIRED = ("media-api-key", "catalog-feed-key")
OPTIONAL = ("tmdb-read-access-token", "opensubtitles-api-key")


def keychain_value(account: str) -> str | None:
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    value = result.stdout.decode("utf-8", errors="strict").rstrip("\r\n")
    return value if value.strip() else None


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: embed-private-api-keys.py /path/to/Denbox.app", file=sys.stderr)
        return 2

    app = Path(sys.argv[1]).expanduser()
    resources = app / "Contents" / "Resources"
    if not resources.is_dir():
        print("Expected an app bundle with Contents/Resources", file=sys.stderr)
        return 2

    credentials: dict[str, str] = {}
    for account in REQUIRED + OPTIONAL:
        value = keychain_value(account)
        if value is not None:
            credentials[account] = value

    missing = [account for account in REQUIRED if account not in credentials]
    if missing:
        print("Missing required Keychain entries: " + ", ".join(missing), file=sys.stderr)
        return 1

    payload = {"_version": "1", **credentials}
    destination = resources / "DenboxPrivateAPIKeys.plist"
    with destination.open("wb") as output:
        plistlib.dump(payload, output, fmt=plistlib.FMT_BINARY, sort_keys=True)
    destination.chmod(0o644)
    print(f"Embedded {len(credentials)} Keychain entries into the private app bundle; values were not printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
