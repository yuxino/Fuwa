#!/bin/zsh
set -euo pipefail

FUWA_SCRIPT_DIR="${0:A:h}"
[[ $# == 2 ]] || { print -u2 'Usage: package-dmg.sh Fuwa.app Fuwa-<version>.dmg'; exit 2; }
[[ ! -L "$1" && ! -L "$2" ]] || {
    print -u2 'error: app and output paths cannot be symbolic links'; exit 2
}
FUWA_SOURCE_APP="${1:A}"
FUWA_DMG_PATH="${2:A}"
[[ -d "${FUWA_SOURCE_APP}" && ! -L "${FUWA_SOURCE_APP}" && "${FUWA_DMG_PATH}" == *.dmg ]] || {
    print -u2 'error: expected an app bundle and a .dmg output path'; exit 2
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${FUWA_SOURCE_APP}/Contents/Info.plist")" == app.yuxino.fuwa ]] || {
    print -u2 'error: expected the Fuwa application'; exit 1
}
codesign --verify --deep --strict "${FUWA_SOURCE_APP}"
FUWA_CODESIGN_IDENTITY="$("${FUWA_SCRIPT_DIR}/codesign-identity.sh")"
FUWA_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fuwa-dmg.XXXXXX")"
FUWA_CONTENTS_DIR="${FUWA_STAGING_DIR}/contents"
FUWA_MOUNT_DIR="${FUWA_STAGING_DIR}/mounted"
FUWA_MOUNTED=0
cleanup() {
    if (( FUWA_MOUNTED == 1 )); then
        hdiutil detach "${FUWA_MOUNT_DIR}" >/dev/null || {
            print -u2 -r -- "warning: preserved mounted verification directory: ${FUWA_STAGING_DIR}"
            return
        }
    fi
    rm -rf "${FUWA_STAGING_DIR}"
}
trap cleanup EXIT
mkdir -p "${FUWA_CONTENTS_DIR}" "${FUWA_MOUNT_DIR}"
/usr/bin/ditto "${FUWA_SOURCE_APP}" "${FUWA_CONTENTS_DIR}/Fuwa.app"
ln -s /Applications "${FUWA_CONTENTS_DIR}/Applications"
mkdir -p "${FUWA_DMG_PATH:h}"
hdiutil create -ov -fs HFS+ -format UDZO -nospotlight \
    -volname Fuwa -srcfolder "${FUWA_CONTENTS_DIR}" "${FUWA_DMG_PATH}"
FUWA_TIMESTAMP_ARGUMENT=--timestamp
if codesign --display --verbose=4 "${FUWA_SOURCE_APP}" 2>&1 | /usr/bin/grep -q 'TeamIdentifier=not set'; then
    FUWA_TIMESTAMP_ARGUMENT=--timestamp=none
fi
codesign --force "${FUWA_TIMESTAMP_ARGUMENT}" --sign "${FUWA_CODESIGN_IDENTITY}" "${FUWA_DMG_PATH}"
codesign --verify --strict "${FUWA_DMG_PATH}"
hdiutil verify "${FUWA_DMG_PATH}"
hdiutil attach -readonly -nobrowse -mountpoint "${FUWA_MOUNT_DIR}" "${FUWA_DMG_PATH}" >/dev/null
FUWA_MOUNTED=1
python3 "${FUWA_SCRIPT_DIR}/verify-dmg-layout.py" "${FUWA_MOUNT_DIR}"
codesign --verify --deep --strict "${FUWA_MOUNT_DIR}/Fuwa.app"
hdiutil detach "${FUWA_MOUNT_DIR}" >/dev/null
FUWA_MOUNTED=0
pushd "${FUWA_DMG_PATH:h}" >/dev/null
shasum -a 256 "${FUWA_DMG_PATH:t}" > "${FUWA_DMG_PATH:t}.sha256"
popd >/dev/null
print -r -- "Built ${FUWA_DMG_PATH}"
