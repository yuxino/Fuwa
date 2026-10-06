#!/usr/bin/env python3
"""Prepare Fuwa's source-verified MyGo updater overlay without changing modules.

The complete -modfile and -overlay flags are written to stdout. Diagnostics go
to stderr, so build scripts can append the result to GOFLAGS.
"""

import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


REPOSITORY = Path(__file__).resolve().parent.parent
MODULE = "github.com/egoist/mygo"
VERSION = "v0.0.0-20261005151153-bfb878510ce3"
COMMIT = "bfb878510ce3e0f7ac684090137d5147ed4421ff"
SOURCE_SHA256 = "c00462ba30aca5f74c80d962f261a9d1c740d76b7cd61b5a974de80fb80a4141"
PATCHED_SHA256 = "e3ccb6fb3cc46982a7e495f7d32af48edf75832462ed47c55cdd646a9091ad1d"
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)$")


class OverlayError(RuntimeError):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def quote_go_flag(flag):
    # GOFLAGS uses Go's quoted.Split, not a shell parser. Shell-style mixed
    # quote escaping would corrupt a checkout path containing an apostrophe.
    if not any(character in " \t\r\n" for character in flag):
        return flag
    for delimiter in "'\"":
        if delimiter not in flag:
            return delimiter + flag + delimiter
    raise OverlayError("GOFLAGS cannot represent a path containing whitespace and both quote types")


def apply_exact_patch(source, patch):
    """Apply one updater.go unified diff, without offsets or fuzzy matching."""
    original = source.splitlines(keepends=True)
    lines = patch.splitlines(keepends=True)
    if lines[:2] != ["--- a/updater.go\n", "+++ b/updater.go\n"]:
        raise OverlayError("patch must contain exactly the reviewed updater.go diff")
    output = []
    cursor = 0
    index = 2
    hunks = 0
    while index < len(lines):
        match = HUNK.fullmatch(lines[index].rstrip("\n"))
        if not match:
            raise OverlayError("invalid patch hunk at line %d" % (index + 1))
        old_start, new_start = int(match[1]), int(match[3])
        old_count = int(match[2]) if match[2] is not None else 1
        new_count = int(match[4]) if match[4] is not None else 1
        offset = old_start - 1 if old_count else old_start
        if offset < cursor or offset > len(original):
            raise OverlayError("patch hunk is outside the original source")
        output.extend(original[cursor:offset])
        cursor = offset
        expected_output = new_start - 1 if new_count else new_start
        if len(output) != expected_output:
            raise OverlayError("patch output position does not match its header")
        removed = added = 0
        index += 1
        while index < len(lines) and not lines[index].startswith("@@ "):
            line = lines[index]
            if not line or line[0] not in " +-":
                raise OverlayError("unsupported patch content at line %d" % (index + 1))
            kind, content = line[0], line[1:]
            if kind in " -":
                if cursor >= len(original) or original[cursor] != content:
                    raise OverlayError("patch context mismatch at source line %d" % (cursor + 1))
                cursor += 1
                removed += 1
            if kind in " +":
                output.append(content)
                added += 1
            index += 1
        if (removed, added) != (old_count, new_count):
            raise OverlayError("patch hunk counts do not match the reviewed diff")
        hunks += 1
    if hunks == 0:
        raise OverlayError("patch has no changes")
    output.extend(original[cursor:])
    return "".join(output)


def locate_module(go):
    # Module metadata does not need build overlays. An inherited overlay may
    # refer to a previous checkout or to files not generated yet in this one.
    environment = os.environ.copy()
    environment["GOFLAGS"] = ""
    environment["GOWORK"] = "off"
    result = subprocess.run(
        [go, "list", "-mod=readonly", "-m", "-json", MODULE],
        cwd=REPOSITORY,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise OverlayError("cannot locate pinned MyGo module: " + result.stderr.strip())
    module = json.loads(result.stdout)
    if module.get("Path") != MODULE or module.get("Version") != VERSION or module.get("Replace"):
        raise OverlayError("MyGo module changed; review the cancellation patch before updating its pin")
    if not module.get("Dir"):
        raise OverlayError("MyGo source is unavailable; run go mod download first")
    # Preserve Go's spelling of the module directory for overlay matching,
    # including paths whose parents are symlinks on macOS.
    return Path(module["Dir"]).absolute()


def write_atomic(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix=".overlay-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def module_tree_hash(root):
    """Fingerprint the complete copied module, including file permissions."""
    digest = hashlib.sha256()
    for directory, names, files in os.walk(root):
        names[:] = sorted(name for name in names if name != ".git")
        for name in sorted(names + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                raise OverlayError("module source contains an unexpected symlink: " + relative)
            mode = path.stat().st_mode & 0o777
            digest.update((relative + "\0" + str(mode) + "\0").encode("utf-8"))
            if path.is_file():
                digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def copy_verified_module(module_dir, destination, fingerprint):
    """Publish an immutable module copy once, never edit an active build's copy."""
    if destination.exists():
        if module_tree_hash(destination) != fingerprint:
            raise OverlayError("cached MyGo source changed; remove its generated build directory and retry")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".mygo-copy-", dir=destination.parent))
    staging = temporary / "source"
    try:
        shutil.copytree(module_dir, staging, ignore=shutil.ignore_patterns(".git"))
        if module_tree_hash(staging) != fingerprint:
            raise OverlayError("MyGo source changed while copying; refusing an inconsistent build")
        # The module cache marks directory roots read-only. Some build
        # filesystems require owner write access to publish the copied root.
        # The files and subdirectories, whose modes are fingerprinted, stay
        # unchanged.
        os.chmod(staging, 0o755)
        try:
            os.rename(staging, destination)
        except OSError as error:
            if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                raise
            # Another preparer may have atomically completed the same copy.
            if module_tree_hash(destination) != fingerprint:
                raise OverlayError("concurrent MyGo source copy failed verification") from error
    finally:
        # Module-cache directories may be read-only. The temporary copy is ours.
        for directory, names, files in os.walk(temporary):
            os.chmod(directory, 0o700)
        shutil.rmtree(temporary)


def prepare(args):
    module_dir = Path(args.module_dir).absolute() if args.module_dir else locate_module(args.go)
    source_path = module_dir / "updater.go"
    source = source_path.read_bytes()
    original_hash = sha256(source)
    if original_hash != SOURCE_SHA256:
        raise OverlayError(
            "updater.go SHA-256 mismatch; refusing to patch unreviewed source "
            "(expected %s, got %s)" % (SOURCE_SHA256, original_hash)
        )
    patch_path = REPOSITORY / "patches" / "mygo-updater-cancellation.patch"
    patch = patch_path.read_bytes()
    patched = apply_exact_patch(source.decode("utf-8"), patch.decode("utf-8")).encode("utf-8")
    if sha256(patched) != PATCHED_SHA256:
        raise OverlayError("patched updater.go SHA-256 mismatch; review the patch before building")
    license_data = (module_dir / "LICENSE").read_bytes()
    if license_data != (REPOSITORY / "patches" / "MyGo-LICENSE").read_bytes():
        raise OverlayError("MyGo license changed; review the upstream attribution before building")
    output = Path(args.output)
    if not output.is_absolute():
        output = REPOSITORY / output
    output = output.resolve()
    try:
        output.relative_to(module_dir.resolve())
    except ValueError:
        pass
    else:
        raise OverlayError("overlay output must not be inside the MyGo source or module cache")
    output.mkdir(parents=True, exist_ok=True)
    # Go deliberately rejects overlays that target GOMODCACHE. Use a verified,
    # immutable module copy selected by a temporary modfile, then overlay only
    # the updater in that copy. The committed module files remain untouched.
    source_fingerprint = module_tree_hash(module_dir)
    copied_module = output / ".modules" / ("mygo-" + VERSION + "-" + source_fingerprint[:16])
    copy_verified_module(module_dir, copied_module, source_fingerprint)
    copied_source = copied_module / "updater.go"
    # A .go suffix would make go test ./... treat this build artifact as a
    # Fuwa package, where MyGo's internal imports would correctly be rejected.
    replacement = output / "updater.go.patched"
    overlay = output / "overlay.json"
    modfile = output / "fuwa.mod"
    sumfile = output / "fuwa.sum"
    # Go retains replacement text in binary build information. A repository-
    # relative path avoids embedding a developer's home directory in releases.
    module_relative = "./" + Path(os.path.relpath(copied_module, REPOSITORY)).as_posix()
    mod_source = (REPOSITORY / "go.mod").read_bytes()
    sum_source = (REPOSITORY / "go.sum").read_bytes()
    generated_mod = mod_source.rstrip() + (
        "\n\n// Fuwa's verified temporary MyGo source; generated for this build.\n"
        "replace " + MODULE + " => " + json.dumps(module_relative) + "\n"
    ).encode("utf-8")
    metadata = {
        "module": MODULE,
        "version": VERSION,
        "commit": COMMIT,
        "source": str(source_path),
        "source_sha256": original_hash,
        "module_tree_sha256": source_fingerprint,
        "copied_module": str(copied_module),
        "module_replacement": module_relative,
        "modfile": str(modfile),
        "sumfile": str(sumfile),
        "original_go_mod_sha256": sha256(mod_source),
        "original_go_sum_sha256": sha256(sum_source),
        "replacement": str(replacement),
        "replacement_sha256": PATCHED_SHA256,
        "patch": str(patch_path.relative_to(REPOSITORY)),
        "patch_sha256": sha256(patch),
        "license": "MIT",
        "explicit_module_directory": bool(args.module_dir),
    }
    write_atomic(replacement, patched)
    write_atomic(output / "MyGo-LICENSE", license_data)
    write_atomic(modfile, generated_mod)
    write_atomic(sumfile, sum_source)
    write_atomic(output / "metadata.json", (json.dumps(metadata, indent=2) + "\n").encode("utf-8"))
    write_atomic(overlay, (json.dumps({"Replace": {str(copied_source): str(replacement)}}, indent=2) + "\n").encode("utf-8"))
    return ["-modfile=" + str(modfile), "-overlay=" + str(overlay)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--go", default="go", help="Go executable used to locate the pinned module")
    parser.add_argument("--output", default="build/mygo-overlay", help="output directory, relative to the repository unless absolute")
    parser.add_argument("--module-dir", help="explicit source directory for controlled QA; updater.go and license hashes are still checked")
    args = parser.parse_args()
    try:
        flags = prepare(args)
        formatted_flags = " ".join(quote_go_flag(flag) for flag in flags)
    except (OverlayError, OSError, ValueError) as error:
        print("MyGo overlay: " + str(error), file=sys.stderr)
        return 1
    print(formatted_flags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
