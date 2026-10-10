#!/usr/bin/env python3
"""Guard the maintained platform and release contract using only the stdlib."""

import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def shell_array(workflow: str, name: str) -> list[str]:
    match = re.search(rf"^          {name}=\(\n(.*?)^          \)", workflow, re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing {name} asset contract")
    return [line.strip().strip('"') for line in match.group(1).splitlines() if line.strip()]


class MacOSOnlyTests(unittest.TestCase):
    def test_windows_source_is_retired(self) -> None:
        self.assertFalse((ROOT / "windows").exists())
        self.assertFalse(list((ROOT / "docs/plans").glob("*windows-native*")))

    def test_ci_keeps_the_mac_build_and_release_checks(self) -> None:
        workflow = read(".github/workflows/ci.yml")
        jobs = re.findall(r"^  ([a-z-]+):$", workflow.split("jobs:\n", 1)[1], re.M)
        self.assertEqual(set(jobs), {"release-checksum", "swift"})
        self.assertNotIn("windows-", workflow.lower())
        for requirement in (
            "FuwaLogicTests", "-strict-concurrency=complete", "-warnings-as-errors",
            "scripts/test-update-metadata.py", "scripts/test-macos-only.py", "scripts/test-dmg-layout.py",
            "scripts/test-verify-release-checksum.sh", "scripts/generate-app-icon.sh --check",
        ):
            self.assertIn(requirement, workflow)

    def test_promotion_requires_only_the_mac_archive_hash(self) -> None:
        workflow = read(".github/workflows/promote-release.yml")
        inputs = workflow.split("permissions:\n", 1)[0]
        self.assertEqual(re.findall(r"^      ([a-z0-9_]+):$", inputs, re.M),
                         ["tag", "macos_sha256", "confirmation"])
        self.assertNotIn("windows", workflow.lower())
        self.assertNotIn("/artifacts", workflow)
        self.assertIn("publish Fuwa ${RELEASE_TAG} with unnotarized macOS assets", workflow)
        self.assertEqual(shell_array(workflow, "base_assets"),
                         ["$macos_dmg", "${macos_dmg}.sha256"])
        self.assertEqual(shell_array(workflow, "expected_assets"), [
            "$macos_dmg", "${macos_dmg}.sha256", "${macos_dmg}.sig",
            "appcast.xml", "appcast.xml.sig", "latest.json", "latest.json.sig",
        ])
        self.assertEqual(shell_array(workflow, "feeds"), ["appcast.xml"])

    def test_mac_release_safety_gates_are_retained(self) -> None:
        workflow = read(".github/workflows/promote-release.yml")
        for gate in (
            "environment: release-promotion", "needs: [verify-macos, prepare-update-metadata]",
            "scripts/test-macos-only.py", "merge-base --is-ancestor",
            "actions/workflows/ci.yml/runs", 'select(.tag_name == $tag and .draft == true)',
            'lipo "$binary" -verify_arch arm64 x86_64',
            'codesign --verify --deep --strict --verbose=2 "$app"',
            "verify-macos-signature-pin.py", "leafCertificateSha256",
            "hdiutil attach -readonly -nobrowse", "scripts/verify-dmg-layout.py",
            "FUWA_UPDATER_ED25519_PRIVATE_KEY", "verify-ed25519-signature.swift",
            "fuwa-altered-update.bin", "--require-signed-feeds",
            'verify_package "$macos_dmg" "$ACCEPTED_MACOS_SHA256"',
            '"$final_draft_snapshot" != "$asset_snapshot"',
            '"$post_publish_snapshot" != "$asset_snapshot"',
            "releases/latest",
        ):
            self.assertIn(gate, workflow)

    def test_mac_updater_identity_and_user_control_are_preserved(self) -> None:
        metadata = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        self.assertEqual(metadata["CFBundleIdentifier"], "app.yuxino.fuwa")
        self.assertEqual(metadata["SUFeedURL"],
                         "https://github.com/yuxino/fuwa/releases/latest/download/appcast.xml")
        self.assertTrue(metadata["SURequireSignedFeed"])
        self.assertTrue(metadata["SUVerifyUpdateBeforeExtraction"])
        for key in ("SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate", "SUEnableAutomaticChecks"):
            self.assertFalse(metadata[key])
        self.assertIn(f"public_key='{metadata['SUPublicEDKey']}'",
                      read(".github/workflows/promote-release.yml"))

    def test_public_platform_requirements_are_consistent(self) -> None:
        for path in ("README.md", "README_ZH.md"):
            self.assertIn("macOS 14 或更高版本", read(path))
        self.assertIn("macOS 14 or later", read("README_EN.md"))
        self.assertIn("discontinued Windows builds are unsupported", read("SECURITY.md"))


if __name__ == "__main__":
    unittest.main()
