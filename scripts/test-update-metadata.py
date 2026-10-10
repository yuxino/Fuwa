#!/usr/bin/env python3

import base64
import json
import subprocess
import tempfile
from pathlib import Path


def run(*arguments: str, succeeds: bool = True) -> None:
    result = subprocess.run(arguments, capture_output=True, text=True, check=False)
    if (result.returncode == 0) != succeeds:
        raise RuntimeError(
            f"unexpected exit {result.returncode}: {' '.join(arguments)}\n{result.stderr}"
        )


with tempfile.TemporaryDirectory(prefix="fuwa-update-metadata-tests-") as root_value:
    root = Path(root_value)
    assets = root / "assets"
    metadata = root / "metadata"
    assets.mkdir()
    notes = root / "notes.txt"
    notes.write_text("Signed updater fixture notes.", encoding="utf-8")
    version = "9.8.7"
    signature = base64.b64encode(bytes(range(64))).decode("ascii") + "\n"
    names = (
        f"Fuwa-{version}.dmg",
    )
    for index, name in enumerate(names):
        (assets / name).write_bytes(f"fixture-{index}".encode("ascii"))
        (assets / f"{name}.sig").write_text(signature, encoding="ascii")

    tool = str(Path(__file__).with_name("update-metadata.py"))
    run(
        "python3", tool, "generate",
        "--version", version,
        "--build", "42",
        "--published-at", "Wed, 02 Sep 2026 00:00:00 +0000",
        "--release-notes", str(notes),
        "--asset-dir", str(assets),
        "--output-dir", str(metadata),
    )
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
    )
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
        "--require-signed-feeds",
        succeeds=False,
    )

    run(
        "python3", tool, "generate",
        "--version", version,
        "--build", "42",
        "--published-at", "tag v9.8.7\nWed, 02 Sep 2026 00:00:00 +0000",
        "--release-notes", str(notes),
        "--asset-dir", str(assets),
        "--output-dir", str(metadata),
        succeeds=False,
    )

    latest_path = metadata / "latest.json"
    original_latest = latest_path.read_text(encoding="utf-8")
    latest = json.loads(original_latest)
    assert set(latest["assets"]) == {"macos-universal"}
    assert {path.name for path in metadata.iterdir()} == {"appcast.xml", "latest.json"}
    assert latest["assets"]["macos-universal"]["name"] == f"Fuwa-{version}.dmg"
    assert latest["assets"]["macos-universal"]["url"].endswith(f"/Fuwa-{version}.dmg")
    latest["assets"]["macos-universal"]["name"] = f"Fuwa-{version}.zip"
    latest_path.write_text(json.dumps(latest), encoding="utf-8")
    run("python3", tool, "verify", "--asset-dir", str(assets), "--metadata-dir", str(metadata), succeeds=False)
    latest = json.loads(original_latest)
    # A retired-platform record must not silently re-enter the release contract.
    latest["assets"]["windows-x64"] = dict(latest["assets"]["macos-universal"])
    latest_path.write_text(json.dumps(latest), encoding="utf-8")
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
        succeeds=False,
    )
    latest = json.loads(original_latest)
    latest["assets"]["macos-universal"]["sha256"] = "0" * 64
    latest_path.write_text(json.dumps(latest), encoding="utf-8")
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
        succeeds=False,
    )
    latest_path.write_text(original_latest, encoding="utf-8")

    feed = metadata / "appcast.xml"
    original_feed = feed.read_text(encoding="utf-8")
    feed.write_text("<rss><broken>", encoding="utf-8")
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
        succeeds=False,
    )
    feed.write_text(original_feed, encoding="utf-8")

    signature_path = assets / f"{names[0]}.sig"
    signature_path.write_text("not-base64\n", encoding="ascii")
    run(
        "python3", tool, "verify",
        "--asset-dir", str(assets),
        "--metadata-dir", str(metadata),
        succeeds=False,
    )

print("Fuwa update metadata fixture tests passed")
