#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Build this macOS-only capture adapter on a Mac with Xcode Command Line Tools.' >&2; exit 1; }
xcrun --find clang >/dev/null
out="${FUWA_BUILD_DIR:-build}"
mkdir -p "$out/bin" "$out/artifacts"
# Public key only: the existing owner-controlled Ed25519 identity. Never load a
# signing secret in preview CI, and never use the Swift production update feed.
key='8qWUhz/r6J3c6fVw9NVEmqvWcF4oVKwAtLFm9AkA1ZA='
feed='https://github.com/yuxino/Fuwa/releases/download/mygo-v{version}/update-darwin-universal.json'
flags="-s -w -X github.com/egoist/mygo.production=1 -X github.com/egoist/mygo.packageUpdateKey=$key -X github.com/egoist/mygo.packageUpdateFeed=$feed"
for arch in arm64 amd64; do
  CGO_ENABLED=1 GOOS=darwin GOARCH="$arch" CC=clang go build -trimpath -ldflags "$flags" -o "$out/bin/fuwa-$arch" .
done
app="$out/Fuwa MyGo.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$out/bin/fuwa-arm64" "$out/bin/fuwa-amd64" -output "$app/Contents/MacOS/FuwaMyGo"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for locale in en zh-Hans; do
 mkdir -p "$app/Contents/Resources/$locale.lproj"
 cp "Resources/$locale.lproj/InfoPlist.strings" "$app/Contents/Resources/$locale.lproj/InfoPlist.strings"
done
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
lipo -archs "$app/Contents/MacOS/FuwaMyGo"
zip="$out/artifacts/Fuwa-MyGo-1.1.0-mygo.1-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out/artifacts" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "Preview app: $app"
echo "Ad-hoc signed only; not Developer ID signed or notarized. No stable app was installed or replaced."
