#!/usr/bin/env python3
"""Exercise packaging preflight without a build or access to signing keys."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class PackageOutputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="fuwa-package-output-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.package = scripts / "package-app.sh"
        shutil.copy2(Path(__file__).with_name("package-app.sh"), self.package)
        identity = scripts / "codesign-identity.sh"
        identity.write_text("#!/bin/zsh\nprint -u2 -- 'signing preflight reached'\nexit 93\n")
        identity.chmod(0o755)
        self.default_output = self.root / "dist"
        self.binary = self.default_output / "Fuwa.app/Contents/MacOS/Fuwa"
        self.binary.parent.mkdir(parents=True)
        subprocess.run(["/usr/bin/cc", "-x", "c", "-o", str(self.binary), "-"],
                       input="#include <unistd.h>\nint main(void) { sleep(60); return 0; }\n",
                       text=True, check=True, capture_output=True)
        self.original_binary = self.binary.read_bytes()
        self.process = subprocess.Popen([str(self.binary)])
        self.addCleanup(self.stop_process)

    def stop_process(self):
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=5)

    def run_package(self, output=None):
        environment = dict(os.environ)
        environment.pop("FUWA_OUTPUT_DIR", None)
        environment["FUWA_BUILD_UNIVERSAL"] = "1"
        if output is not None:
            environment["FUWA_OUTPUT_DIR"] = str(output)
        return subprocess.run(["zsh", str(self.package)], env=environment,
                              capture_output=True, text=True, timeout=10)

    def test_running_default_bundle_is_preserved_before_signing(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("package output is in use", result.stderr)
        self.assertNotIn("signing preflight reached", result.stderr)
        self.assertEqual(self.binary.read_bytes(), self.original_binary)
        self.assertIsNone(self.process.poll())

    def test_isolated_release_output_can_proceed_while_default_is_running(self):
        result = self.run_package(self.root / "dist/release-9.8.7")
        self.assertEqual(result.returncode, 93, result.stderr)
        self.assertIn("signing preflight reached", result.stderr)
        self.assertEqual(self.binary.read_bytes(), self.original_binary)
        self.assertIsNone(self.process.poll())

    def test_running_explicit_output_is_also_preserved(self):
        result = self.run_package(self.default_output)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("package output is in use", result.stderr)
        self.assertNotIn("signing preflight reached", result.stderr)


if __name__ == "__main__":
    unittest.main()
