#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Build this macOS-only capture adapter on a Mac with Xcode Command Line Tools.' >&2; exit 1; }
xcrun --find clang >/dev/null
out="${FUWA_BUILD_DIR:-build}"
mkdir -p "$out/bin" "$out/artifacts"
# CFLAGS on the capture adapter alone do not constrain the final executable.
# Without an explicit linker target, a macOS 15 builder produced a binary that
# required 15.0 even though its Info.plist advertised 14.0.
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)
export MACOSX_DEPLOYMENT_TARGET="$minimum"
export CGO_CFLAGS="${CGO_CFLAGS:-} -mmacosx-version-min=$minimum"
export CGO_LDFLAGS="${CGO_LDFLAGS:-} -mmacosx-version-min=$minimum"
version=$(python3 - <<'PY'
import pathlib, re
source = pathlib.Path('internal/core/core.go').read_text()
match = re.search(r'^const Version = "([0-9A-Za-z.+-]+)"$', source, re.MULTILINE)
if match is None:
    raise SystemExit('Cannot determine the preview version from core.Version')
print(match.group(1))
PY
)
# Public key only: the existing owner-controlled Ed25519 identity. Never load a
# signing secret in preview CI, and never use the Swift production update feed.
key='8qWUhz/r6J3c6fVw9NVEmqvWcF4oVKwAtLFm9AkA1ZA='
feed='https://github.com/yuxino/Fuwa/releases/download/mygo-v{version}/update-darwin-universal.json'
flags="-s -w -X github.com/egoist/mygo.production=1 -X github.com/egoist/mygo.packageUpdateKey=$key -X github.com/egoist/mygo.packageUpdateFeed=$feed"
for arch in arm64 amd64; do
  CGO_ENABLED=1 GOOS=darwin GOARCH="$arch" CC=clang go build -mod=readonly -tags mygo_noinspector -trimpath -ldflags "$flags" -o "$out/bin/fuwa-$arch" .
done
app="$out/Fuwa MyGo.app"
# Assemble from an empty directory, so repeated local builds cannot retain an
# old framework or an obsolete resource in the signed preview.
stage=$(mktemp -d "$out/.fuwa-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
staged_app="$stage/Fuwa MyGo.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
lipo -create "$out/bin/fuwa-arm64" "$out/bin/fuwa-amd64" -output "$staged_app/Contents/MacOS/FuwaMyGo"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
for locale in en zh-Hans; do
 mkdir -p "$staged_app/Contents/Resources/$locale.lproj"
 cp "Resources/$locale.lproj/InfoPlist.strings" "$staged_app/Contents/Resources/$locale.lproj/InfoPlist.strings"
done
plutil -lint "$staged_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$staged_app"
codesign --verify --all-architectures --strict --verbose=2 "$staged_app"
lipo -verify_arch arm64 x86_64 "$staged_app/Contents/MacOS/FuwaMyGo"
zip="$out/artifacts/Fuwa-MyGo-$version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$zip"
(cd "$out/artifacts" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
python3 scripts/verify-mygo-package.py "$zip" --report "$out/artifacts/package-verification.json"
if [[ -e "$app" || -L "$app" ]]; then
  rm -rf "$app"
fi
mv "$staged_app" "$app"
printf '%s\n' "$zip" > "$out/package-path.txt"
echo "Preview app: $app"
echo "Ad-hoc signed only; not Developer ID signed or notarized. No stable app was installed or replaced."
