#!/usr/bin/env python3
"""Verify the mounted, read-only Fuwa installer layout without launching it."""
import os
import sys
from pathlib import Path

def verify(root: Path) -> None:
    allowed = {
        'Fuwa.app', 'Applications', '.DS_Store', '.Trashes', '.fseventsd',
        '.Spotlight-V100', '.TemporaryItems', '.HFS+ Private Directory Data\r',
    }
    entries = {path.name for path in root.iterdir()}
    if entries - allowed:
        raise ValueError(f'unexpected installer contents: {sorted(entries - allowed)!r}')
    app = root / 'Fuwa.app'
    if app.is_symlink() or not app.is_dir() or not (app / 'Contents/MacOS/Fuwa').is_file():
        raise ValueError('installer must contain the Fuwa.app bundle')
    applications = root / 'Applications'
    if not applications.is_symlink() or os.readlink(applications) != '/Applications':
        raise ValueError('installer must contain an Applications shortcut to /Applications')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify-dmg-layout.py <mounted-volume>')
    try:
        verify(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
    print('Fuwa DMG installer layout verified')
