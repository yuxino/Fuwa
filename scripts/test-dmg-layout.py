#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('dmg_layout', Path(__file__).with_name('verify-dmg-layout.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class InstallerLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fuwa-dmg-layout-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        binary = self.root / 'Fuwa.app/Contents/MacOS/Fuwa'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'generated fixture')
        (self.root / 'Applications').symlink_to('/Applications')

    def test_installer_with_filesystem_metadata(self):
        for name in ('.DS_Store', '.Trashes', '.fseventsd'):
            (self.root / name).touch()
        module.verify(self.root)

    def test_wrong_installation_destination(self):
        (self.root / 'Applications').unlink()
        (self.root / 'Applications').symlink_to('/tmp')
        with self.assertRaises(ValueError): module.verify(self.root)

    def test_destination_must_be_a_shortcut(self):
        (self.root / 'Applications').unlink()
        (self.root / 'Applications').mkdir()
        with self.assertRaises(ValueError): module.verify(self.root)

    def test_missing_app_executable(self):
        (self.root / 'Fuwa.app/Contents/MacOS/Fuwa').unlink()
        with self.assertRaises(ValueError): module.verify(self.root)

    def test_unexpected_hidden_payload(self):
        (self.root / '.unexpected.app').mkdir()
        with self.assertRaises(ValueError): module.verify(self.root)

    def test_app_must_not_be_an_external_shortcut(self):
        original = self.root / 'Fuwa.app'
        original.rename(self.root / '.TemporaryItems')
        original.symlink_to(self.root / '.TemporaryItems')
        with self.assertRaises(ValueError): module.verify(self.root)

if __name__ == '__main__': unittest.main()
