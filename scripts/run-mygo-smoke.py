#!/usr/bin/env python3
"""Run a native fixture check and retain diagnostics even if it times out."""

import argparse
import os
import pathlib
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=pathlib.Path, required=True)
    parser.add_argument("--expect", required=True)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.timeout <= 0:
        parser.error("a command and a positive timeout are required")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    timed_out = False
    with args.log.open("wb") as log:
        try:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as error:
            log.write(f"Cannot launch fixture: {error}\n".encode())
            result = 1
        else:
            try:
                result = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                # Only this launched fixture's process group is terminated.
                # Killing descendants too prevents stale QA windows in later checks.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                log.write(f"\nFixture timed out after {args.timeout:g} seconds\n".encode())
                result = 124
    output = args.log.read_text(errors="replace")
    print(output, end="" if output.endswith("\n") else "\n")
    if timed_out or result != 0:
        return result if result > 0 else 1
    if not any(line.startswith(args.expect) for line in output.splitlines()):
        print(f"Missing success marker: {args.expect}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
