#!/usr/bin/env python3
"""Generate and verify Fuwa's signed-update metadata without handling secrets."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NAMESPACE)


def fail(message: str) -> None:
    raise ValueError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def signature(path: Path) -> str:
    value = path.read_text(encoding="utf-8").strip()
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise ValueError(f"invalid base64 signature in {path.name}") from error
    if len(decoded) != 64:
        fail(f"Ed25519 signature in {path.name} must decode to 64 bytes")
    return value


def published_at(value: object) -> str:
    if not isinstance(value, str) or "\n" in value or "\r" in value:
        fail("publishedAt must be one RFC 2822 date line")
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError) as error:
        raise ValueError("publishedAt is not a valid RFC 2822 date") from error
    if parsed.tzinfo is None:
        fail("publishedAt must include a timezone")
    return value


def verify_signed_feed_comment(path: Path) -> None:
    payload = path.read_bytes()
    match = re.search(
        rb"<!-- sparkle-signatures:\s*"
        rb"edSignature: ([A-Za-z0-9+/=]+)\s*"
        rb"length: ([0-9]+)\s*-->\s*$",
        payload,
    )
    if match is None:
        fail(f"{path.name} has no Sparkle signed-feed comment")
    try:
        decoded = base64.b64decode(match.group(1), validate=True)
    except ValueError as error:
        raise ValueError(f"{path.name} has an invalid feed signature") from error
    if len(decoded) != 64 or int(match.group(2)) != match.start():
        fail(f"{path.name} has inconsistent signed-feed metadata")


def asset_record(path: Path, url_prefix: str) -> dict[str, object]:
    return {
        "name": path.name,
        "url": f"{url_prefix}/{path.name}",
        "size": path.stat().st_size,
        "sha256": sha256(path),
        "edSignature": signature(path.with_name(path.name + ".sig")),
    }


def write_feed(
    path: Path,
    *,
    title: str,
    version: str,
    build: str,
    published_at: str,
    notes: str,
    minimum_system_version: str | None,
    asset: dict[str, object],
) -> None:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    ET.SubElement(channel, "link").text = "https://github.com/yuxino/fuwa"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Fuwa {version}"
    ET.SubElement(item, "pubDate").text = published_at
    ET.SubElement(item, "description").text = notes
    ET.SubElement(item, f"{{{SPARKLE_NAMESPACE}}}version").text = build
    ET.SubElement(
        item, f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
    ).text = version
    if minimum_system_version:
        ET.SubElement(
            item, f"{{{SPARKLE_NAMESPACE}}}minimumSystemVersion"
        ).text = minimum_system_version
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": str(asset["url"]),
            "length": str(asset["size"]),
            "type": "application/octet-stream",
            f"{{{SPARKLE_NAMESPACE}}}edSignature": str(asset["edSignature"]),
        },
    )
    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(path, encoding="utf-8", xml_declaration=True)


def generate(arguments: argparse.Namespace) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", arguments.version):
        fail("version must contain three numeric components")
    if not re.fullmatch(r"\d+", arguments.build):
        fail("build must be numeric")
    normalized_published_at = published_at(arguments.published_at)
    asset_dir = arguments.asset_dir.resolve()
    output_dir = arguments.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    url_prefix = (
        f"https://github.com/yuxino/fuwa/releases/download/v{arguments.version}"
    )
    names = {
        "macos": f"Fuwa-{arguments.version}.dmg",
    }
    assets: dict[str, dict[str, object]] = {}
    for key, name in names.items():
        path = asset_dir / name
        if not path.is_file():
            fail(f"missing update asset: {name}")
        assets[key] = asset_record(path, url_prefix)

    notes = arguments.release_notes.read_text(encoding="utf-8").strip()
    if not notes:
        fail("release notes must not be empty")
    write_feed(
        output_dir / "appcast.xml",
        title="Fuwa macOS Updates",
        version=arguments.version,
        build=arguments.build,
        published_at=normalized_published_at,
        notes=notes,
        minimum_system_version="14.0",
        asset=assets["macos"],
    )

    latest = {
        "schemaVersion": 1,
        "version": arguments.version,
        "build": int(arguments.build),
        "tag": f"v{arguments.version}",
        "publishedAt": normalized_published_at,
        "assets": {
            "macos-universal": assets["macos"],
        },
    }
    (output_dir / "latest.json").write_text(
        json.dumps(latest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def verify(arguments: argparse.Namespace) -> None:
    asset_dir = arguments.asset_dir.resolve()
    metadata_dir = arguments.metadata_dir.resolve()
    latest_path = metadata_dir / "latest.json"
    try:
        latest = json.loads(latest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("latest.json is missing or malformed") from error
    if latest.get("schemaVersion") != 1:
        fail("latest.json schemaVersion must be 1")
    published_at(latest.get("publishedAt"))
    version = latest.get("version")
    build = latest.get("build")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail("latest.json version is invalid")
    if not isinstance(build, int) or build < 1:
        fail("latest.json build is invalid")
    expected_names = {
        "macos-universal": f"Fuwa-{version}.dmg",
    }
    assets = latest.get("assets")
    if not isinstance(assets, dict) or set(assets) != set(expected_names):
        fail("latest.json must contain exactly the macos-universal asset")
    for key, name in expected_names.items():
        record = assets[key]
        path = asset_dir / name
        if not path.is_file() or not isinstance(record, dict):
            fail(f"missing asset record or file for {key}")
        if record.get("name") != name:
            fail(f"asset name mismatch for {key}")
        if record.get("size") != path.stat().st_size:
            fail(f"asset size mismatch for {key}")
        if record.get("sha256") != sha256(path):
            fail(f"asset SHA-256 mismatch for {key}")
        if record.get("edSignature") != signature(path.with_name(name + ".sig")):
            fail(f"asset signature mismatch for {key}")

    feeds = {
        "appcast.xml": "macos-universal",
    }
    for feed_name, asset_key in feeds.items():
        feed_path = metadata_dir / feed_name
        try:
            root = ET.parse(feed_path).getroot()
        except (OSError, ET.ParseError) as error:
            raise ValueError(f"{feed_name} is missing or malformed") from error
        items = root.findall("./channel/item")
        if len(items) != 1:
            fail(f"{feed_name} must contain exactly one update item")
        item = items[0]
        sparkle_version = item.findtext(f"{{{SPARKLE_NAMESPACE}}}version")
        short_version = item.findtext(
            f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
        )
        enclosures = item.findall("enclosure")
        if sparkle_version != str(build) or short_version != version:
            fail(f"{feed_name} version metadata differs from latest.json")
        if len(enclosures) != 1:
            fail(f"{feed_name} must contain exactly one enclosure")
        enclosure = enclosures[0]
        record = assets[asset_key]
        if (
            enclosure.get("url") != record["url"]
            or enclosure.get("length") != str(record["size"])
            or enclosure.get(f"{{{SPARKLE_NAMESPACE}}}edSignature")
            != record["edSignature"]
        ):
            fail(f"{feed_name} enclosure differs from latest.json")
        if arguments.require_signed_feeds:
            verify_signed_feed_comment(feed_path)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    generator = subparsers.add_parser("generate")
    generator.add_argument("--version", required=True)
    generator.add_argument("--build", required=True)
    generator.add_argument("--published-at", required=True)
    generator.add_argument("--release-notes", type=Path, required=True)
    generator.add_argument("--asset-dir", type=Path, required=True)
    generator.add_argument("--output-dir", type=Path, required=True)
    verifier = subparsers.add_parser("verify")
    verifier.add_argument("--asset-dir", type=Path, required=True)
    verifier.add_argument("--metadata-dir", type=Path, required=True)
    verifier.add_argument("--require-signed-feeds", action="store_true")
    return parser.parse_args()


def main() -> int:
    try:
        arguments = parse_arguments()
        generate(arguments) if arguments.command == "generate" else verify(arguments)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
