#!/usr/bin/env bash
# Use the locked MyGo source plus Fuwa's narrowly scoped, verified updater fix.
# The module cache is never edited. This wrapper is also usable for `run .`.
set -euo pipefail
cd "$(dirname "$0")/.."
go_bin="${FUWA_GO:-go}"
patch_flags=$(python3 scripts/prepare-mygo-overlay.py --go "$go_bin")
GOFLAGS=$(python3 - "$patch_flags" <<'PY'
import os, sys

# Match Go's quoted.Split (quoted fields have no escape processing), so paths
# containing spaces work without silently changing other user-supplied flags.
def fields(text):
    result = []
    while text.strip(' \t\r\n'):
        text = text.lstrip(' \t\r\n')
        if text[0] in "\"'":
            end = text.find(text[0], 1)
            if end < 0:
                raise SystemExit('GOFLAGS has an unclosed quote')
            result.append(text[1:end])
            text = text[end + 1:]
        else:
            end = next((i for i, char in enumerate(text) if char in ' \t\r\n'), len(text))
            result.append(text[:end])
            text = text[end:]
    return result

def quote(flag):
    if not any(char in ' \t\r\n' for char in flag):
        return flag
    for delimiter in "'\"":
        if delimiter not in flag:
            return delimiter + flag + delimiter
    raise SystemExit('GOFLAGS cannot represent a path containing whitespace and both quote types')

required = {}
for flag in fields(sys.argv[1]):
    name, separator, value = flag.partition('=')
    if not separator or name not in ('-overlay', '-modfile') or name in required or not value:
        raise SystemExit('The MyGo source preparation returned invalid build flags')
    required[name] = flag
if set(required) != {'-modfile', '-overlay'}:
    raise SystemExit('The MyGo source preparation did not provide both isolated build flags')
flags = []
for flag in fields(os.environ.get('GOFLAGS', '')):
    name, separator, value = flag.partition('=')
    canonical = '-' + name.lstrip('-')
    if canonical in required:
        if not separator or canonical + '=' + value != required[canonical]:
            raise SystemExit('An unrelated Go overlay or modfile is already active; refusing to replace it silently')
    else:
        flags.append(flag)
flags.extend(required.values())
print(' '.join(quote(flag) for flag in flags))
PY
)
export GOFLAGS
exec "$go_bin" "$@"
