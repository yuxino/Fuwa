#!/usr/bin/env python3
"""Check the shipped ZIP, including Mach-O deployment targets, without running it.

The binary inspection works on any host. --extract-to additionally uses macOS
ditto and codesign, preserving the executable bits and bundle signature before
the CI startup check runs the extracted application.
"""

import argparse
import hashlib
import json
import pathlib
import plistlib
import stat
import struct
import subprocess
import sys
import zipfile


APP = "Fuwa MyGo.app"
BINARY = f"{APP}/Contents/MacOS/FuwaMyGo"
ARCHITECTURES = {0x01000007: "x86_64", 0x0100000C: "arm64"}
DYLIB_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x80000023}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_tuple(version):
    parts = tuple(int(part) for part in version.split("."))
    return (parts + (0, 0, 0))[:3]


def packed_version(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def format_version(value):
    return ".".join(str(part) for part in value)


def inspect_macho(binary, minimum):
    require(len(binary) >= 8, "Missing universal Mach-O header")
    magic, count = struct.unpack_from(">II", binary)
    require(magic == 0xCAFEBABE and count == 2, "Expected exactly two universal Mach-O slices")
    require(len(binary) >= 8 + count * 20, "Truncated universal Mach-O header")
    results = {}
    ranges = []
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", binary, 8 + index * 20)
        arch = ARCHITECTURES.get(cpu)
        require(arch is not None and arch not in results, "Missing or duplicated arm64/x86_64 slice")
        require(offset >= 8 + count * 20 and size >= 32 and offset + size <= len(binary),
                f"Invalid {arch} slice range")
        require(all(offset + size <= start or offset >= end for start, end in ranges),
                "Overlapping universal Mach-O slices")
        ranges.append((offset, offset + size))
        data = binary[offset:offset + size]
        magic, inner_cpu, _, filetype, commands, command_bytes, _, _ = struct.unpack_from("<8I", data)
        require(magic == 0xFEEDFACF and inner_cpu == cpu and filetype == 2,
                f"{arch} is not a 64-bit macOS executable")
        require(32 + command_bytes <= size, f"Truncated {arch} load commands")
        cursor = 32
        targets = []
        dependencies = []
        signed = False
        for _ in range(commands):
            require(cursor + 8 <= 32 + command_bytes, f"Truncated {arch} load command")
            command, length = struct.unpack_from("<II", data, cursor)
            require(length >= 8 and cursor + length <= 32 + command_bytes,
                    f"Invalid {arch} load command size")
            if command == 0x32:  # LC_BUILD_VERSION
                require(length >= 24, f"Truncated {arch} build version")
                platform, target, _, _ = struct.unpack_from("<4I", data, cursor + 8)
                require(platform == 1, f"{arch} targets a platform other than macOS")
                targets.append(packed_version(target))
            elif command == 0x24:  # LC_VERSION_MIN_MACOSX
                require(length >= 16, f"Truncated {arch} minimum version")
                targets.append(packed_version(struct.unpack_from("<I", data, cursor + 8)[0]))
            elif command in DYLIB_COMMANDS:
                require(length >= 24, f"Truncated {arch} dylib command")
                start = struct.unpack_from("<I", data, cursor + 8)[0]
                require(24 <= start < length, f"Invalid {arch} dependency path")
                dependency = data[cursor + start:cursor + length].split(b"\0", 1)[0].decode("utf-8")
                require(dependency.startswith(("/System/Library/Frameworks/", "/usr/lib/")),
                        f"{arch} loads a non-system dependency: {dependency}")
                dependencies.append(dependency)
            elif command == 0x1D:  # LC_CODE_SIGNATURE; cryptographically checked by codesign on macOS.
                require(length >= 16, f"Truncated {arch} code signature command")
                start, signature_size = struct.unpack_from("<II", data, cursor + 8)
                require(start > 0 and signature_size > 0 and start + signature_size <= size,
                        f"Invalid {arch} code signature range")
                signed = True
            cursor += length
        require(cursor == 32 + command_bytes, f"Inconsistent {arch} load command count")
        require(len(targets) == 1, f"Missing or ambiguous {arch} deployment target")
        require(targets[0] <= minimum,
                f"{arch} requires macOS {format_version(targets[0])}, "
                f"but Info.plist promises {format_version(minimum)}")
        require(signed, f"{arch} has no code signature")
        require(dependencies, f"{arch} has no macOS framework dependencies")
        results[arch] = {"minimum_macos": format_version(targets[0]), "dependencies": dependencies}
    require(set(results) == {"arm64", "x86_64"}, "Universal binary is missing an architecture")
    return results


def verify_archive(archive):
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = pathlib.Path(str(archive) + ".sha256").read_text().split()
    require(len(checksum) == 2 and checksum[0] == digest and checksum[1] == archive.name,
            "ZIP checksum or checksum filename does not match")
    with zipfile.ZipFile(archive) as package:
        seen = set()
        for entry in package.infolist():
            path = pathlib.PurePosixPath(entry.filename)
            require(not path.is_absolute() and ".." not in path.parts,
                    f"Unsafe ZIP entry: {entry.filename}")
            require(path.parts and path.parts[0] in (APP, "__MACOSX"),
                    f"Unexpected top-level ZIP entry: {entry.filename}")
            require(entry.filename not in seen, f"Duplicate ZIP entry: {entry.filename}")
            seen.add(entry.filename)
            require(not stat.S_ISLNK(entry.external_attr >> 16),
                    f"Unexpected symbolic link: {entry.filename}")
            require("Frameworks" not in path.parts and not entry.filename.endswith(".dylib"),
                    f"Unexpected bundled runtime: {entry.filename}")
        require(package.testzip() is None, "ZIP content failed its CRC check")
        info = plistlib.loads(package.read(f"{APP}/Contents/Info.plist"))
        require(info.get("CFBundleIdentifier") == "app.yuxino.fuwa.mygo", "Preview bundle identity changed")
        require(info.get("CFBundleExecutable") == "FuwaMyGo", "Unexpected bundle executable")
        require(info.get("CFBundleName") == "Fuwa MyGo" and info.get("CFBundlePackageType") == "APPL",
                "Unexpected preview bundle metadata")
        require(info.get("NSScreenCaptureUsageDescription"), "Missing screen-capture permission description")
        require(package.getinfo(BINARY).external_attr >> 16 & 0o111, "Bundle executable bit was lost")
        for resource in ("AppIcon.icns", "en.lproj/InfoPlist.strings", "zh-Hans.lproj/InfoPlist.strings"):
            require(package.read(f"{APP}/Contents/Resources/{resource}"), f"Missing resource: {resource}")
        require(package.read(f"{APP}/Contents/_CodeSignature/CodeResources"), "Missing bundle signature resources")
        minimum = version_tuple(info["LSMinimumSystemVersion"])
        slices = inspect_macho(package.read(BINARY), minimum)
    return {"archive": archive.name, "sha256": digest, "bundle_id": info["CFBundleIdentifier"],
            "minimum_macos": format_version(minimum), "architectures": slices}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--extract-to", type=pathlib.Path)
    args = parser.parse_args()
    report = verify_archive(args.archive)
    if args.extract_to is not None:
        require(sys.platform == "darwin", "Bundle extraction and signature verification require macOS")
        destination = args.extract_to.resolve()
        require(not destination.exists() or not any(destination.iterdir()), "Extraction directory must be empty")
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ditto", "-x", "-k", str(args.archive), str(destination)], check=True)
        subprocess.run(["codesign", "--verify", "--all-architectures", "--strict", "--verbose=2", str(destination / APP)], check=True)
        report["extracted_signature"] = "verified"
    text = json.dumps(report, indent=2) + "\n"
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text)
    print(text, end="")
    print("PASS preview package: universal binary, deployment targets, resources and checksum")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"FAIL preview package: {error}", file=sys.stderr)
        sys.exit(1)
