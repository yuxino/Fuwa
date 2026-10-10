#!/bin/zsh
set -euo pipefail

FUWA_SCRIPT_DIR="${0:A:h}"
FUWA_PROJECT_DIR="${FUWA_SCRIPT_DIR:h}"
FUWA_APP_DIR="${FUWA_PROJECT_DIR}/dist/Fuwa.app"
FUWA_CONTENTS_DIR="${FUWA_APP_DIR}/Contents"
FUWA_MACOS_DIR="${FUWA_CONTENTS_DIR}/MacOS"
FUWA_RESOURCES_DIR="${FUWA_CONTENTS_DIR}/Resources"
FUWA_FRAMEWORKS_DIR="${FUWA_CONTENTS_DIR}/Frameworks"
FUWA_SDK_15="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
FUWA_BUILD_UNIVERSAL="${FUWA_BUILD_UNIVERSAL:-1}"

verify_universal_binary() {
    local FUWA_BINARY="$1"
    if ! /usr/bin/lipo "${FUWA_BINARY}" -verify_arch arm64 x86_64; then
        print -u2 -r -- "error: expected an arm64 and x86_64 universal binary: ${FUWA_BINARY}"
        exit 1
    fi
}

case "${FUWA_BUILD_UNIVERSAL}" in
    0|1) ;;
    *)
        print -u2 -r -- "error: FUWA_BUILD_UNIVERSAL must be 0 or 1"
        exit 2
        ;;
esac

FUWA_CODESIGN_IDENTITY="$("${FUWA_SCRIPT_DIR}/codesign-identity.sh")"

if [[ -d "${FUWA_SDK_15}" ]]; then
    export SDKROOT="${FUWA_SDK_15}"
fi

export CLANG_MODULE_CACHE_PATH="/private/tmp/fuwa-package-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/private/tmp/fuwa-package-swift-cache"

cd "${FUWA_PROJECT_DIR}"
if [[ "${FUWA_BUILD_UNIVERSAL}" == "1" ]]; then
    FUWA_ARCH_BINARIES=()
    FUWA_SPARKLE_FRAMEWORK_SOURCE=""
    for FUWA_ARCH in arm64 x86_64; do
        swift build \
            --disable-sandbox \
            --configuration release \
            --product Fuwa \
            --arch "${FUWA_ARCH}" \
            -Xswiftc -Osize \
            -Xswiftc -strict-concurrency=complete \
            -Xswiftc -warnings-as-errors
        FUWA_ARCH_BIN_DIR="$(swift build \
            --disable-sandbox \
            --configuration release \
            --arch "${FUWA_ARCH}" \
            --show-bin-path)"
        FUWA_ARCH_BINARIES+=("${FUWA_ARCH_BIN_DIR}/Fuwa")
        FUWA_ARCH_SPARKLE_FRAMEWORK="$({
            find "${FUWA_PROJECT_DIR}/.build/artifacts" \
                -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' \
                -type d -print -quit
        })"
        if [[ -z "${FUWA_ARCH_SPARKLE_FRAMEWORK}" ]]; then
            print -u2 -r -- "error: Sparkle.framework was not resolved for ${FUWA_ARCH}"
            exit 1
        fi
        FUWA_SPARKLE_FRAMEWORK_SOURCE="${FUWA_ARCH_SPARKLE_FRAMEWORK}"
    done

    FUWA_UNIVERSAL_DIR="${FUWA_PROJECT_DIR}/.build/package-universal"
    mkdir -p "${FUWA_UNIVERSAL_DIR}"
    /usr/bin/lipo -create \
        "${FUWA_ARCH_BINARIES[@]}" \
        -output "${FUWA_UNIVERSAL_DIR}/Fuwa"
    verify_universal_binary "${FUWA_UNIVERSAL_DIR}/Fuwa"
    FUWA_BINARY_SOURCE="${FUWA_UNIVERSAL_DIR}/Fuwa"
else
    swift build \
        --disable-sandbox \
        --configuration release \
        --product Fuwa \
        -Xswiftc -Osize \
        -Xswiftc -strict-concurrency=complete \
        -Xswiftc -warnings-as-errors
    FUWA_BIN_DIR="$(swift build \
        --disable-sandbox \
        --configuration release \
        --product Fuwa \
        --show-bin-path)"
    FUWA_BINARY_SOURCE="${FUWA_BIN_DIR}/Fuwa"
    FUWA_SPARKLE_FRAMEWORK_SOURCE="$({
        find "${FUWA_PROJECT_DIR}/.build/artifacts" \
            -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' \
            -type d -print -quit
    })"
    if [[ -z "${FUWA_SPARKLE_FRAMEWORK_SOURCE}" ]]; then
        print -u2 -r -- "error: Sparkle.framework was not resolved"
        exit 1
    fi
fi
FUWA_VERSION="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "${FUWA_PROJECT_DIR}/Resources/Info.plist")"
FUWA_ARCHIVE_NAME="Fuwa-${FUWA_VERSION}.dmg"
FUWA_ARCHIVE_PATH="${FUWA_PROJECT_DIR}/dist/${FUWA_ARCHIVE_NAME}"

rm -rf "${FUWA_APP_DIR}"
rm -f "${FUWA_ARCHIVE_PATH}" "${FUWA_ARCHIVE_PATH}.sha256"
mkdir -p "${FUWA_MACOS_DIR}" "${FUWA_RESOURCES_DIR}" "${FUWA_FRAMEWORKS_DIR}"
cp "${FUWA_BINARY_SOURCE}" "${FUWA_MACOS_DIR}/Fuwa"
/usr/bin/ditto \
    "${FUWA_SPARKLE_FRAMEWORK_SOURCE}" \
    "${FUWA_FRAMEWORKS_DIR}/Sparkle.framework"
# SwiftPM needs these declarations when compiling, but the embedded framework
# only needs its runtime code and resources. Trim the distributable copy before
# signing it; preserve the resolved framework and all updater helpers in full.
for FUWA_DEVELOPMENT_DIRECTORY in Headers PrivateHeaders Modules; do
    rm -rf \
        "${FUWA_FRAMEWORKS_DIR}/Sparkle.framework/${FUWA_DEVELOPMENT_DIRECTORY}" \
        "${FUWA_FRAMEWORKS_DIR}/Sparkle.framework/Versions/B/${FUWA_DEVELOPMENT_DIRECTORY}"
done
cp "${FUWA_PROJECT_DIR}/Resources/Info.plist" "${FUWA_CONTENTS_DIR}/Info.plist"
cp "${FUWA_PROJECT_DIR}/Resources/AppIcon.icns" "${FUWA_RESOURCES_DIR}/AppIcon.icns"
for FUWA_LOCALIZATION_DIR in "${FUWA_PROJECT_DIR}"/Resources/*.lproj; do
    cp -R "${FUWA_LOCALIZATION_DIR}" "${FUWA_RESOURCES_DIR}/${FUWA_LOCALIZATION_DIR:t}"
done
chmod +x "${FUWA_MACOS_DIR}/Fuwa"

# Strip only the distributable copy. Keep SwiftPM's build output intact so
# local crash reports and profiling sessions retain their diagnostic symbols.
/usr/bin/strip -x "${FUWA_MACOS_DIR}/Fuwa"

if [[ "${FUWA_BUILD_UNIVERSAL}" == "1" ]]; then
    verify_universal_binary "${FUWA_MACOS_DIR}/Fuwa"
fi

plutil -lint "${FUWA_CONTENTS_DIR}/Info.plist"
/usr/bin/lipo \
    "${FUWA_FRAMEWORKS_DIR}/Sparkle.framework/Versions/B/Sparkle" \
    -verify_arch arm64 x86_64

if ! /usr/bin/otool -l "${FUWA_MACOS_DIR}/Fuwa" \
    | /usr/bin/grep -F '@executable_path/../Frameworks' >/dev/null; then
    print -u2 -r -- "error: packaged binary has no Frameworks runpath"
    exit 1
fi

FUWA_IDENTITY_DESCRIPTION="$(
    /usr/bin/security find-identity -v -p codesigning \
        | /usr/bin/grep -F "${FUWA_CODESIGN_IDENTITY}" \
        | /usr/bin/head -n 1
)"
case "${FUWA_CODESIGN_TIMESTAMP:-auto}" in
    auto)
        if [[ "${FUWA_IDENTITY_DESCRIPTION}" == *'"Developer ID Application:'* ]]; then
            FUWA_TIMESTAMP_ARGUMENT="--timestamp"
        else
            FUWA_TIMESTAMP_ARGUMENT="--timestamp=none"
        fi
        ;;
    1) FUWA_TIMESTAMP_ARGUMENT="--timestamp" ;;
    0) FUWA_TIMESTAMP_ARGUMENT="--timestamp=none" ;;
    *)
        print -u2 -r -- "error: FUWA_CODESIGN_TIMESTAMP must be auto, 1, or 0"
        exit 2
        ;;
esac
codesign \
    --force \
    --deep \
    --options runtime \
    "${FUWA_TIMESTAMP_ARGUMENT}" \
    --sign "${FUWA_CODESIGN_IDENTITY}" \
    "${FUWA_APP_DIR}"

# Library Validation matches Apple Team IDs, not a self-signed certificate's
# fingerprint. A stable local identity has no Team ID, so even our own signed
# Sparkle framework would otherwise abort in dyld before main. Keep the rest of
# Hardened Runtime enabled; Apple team-signed builds need no exception.
FUWA_SIGNED_TEAM_ID="$(
    codesign --display --verbose=4 "${FUWA_APP_DIR}" 2>&1 \
        | /usr/bin/sed -n 's/^TeamIdentifier=//p'
)"
if [[ "${FUWA_SIGNED_TEAM_ID}" == "not set" ]]; then
    # Re-sign only the host, without propagating its exception to the helpers.
    codesign --force --options runtime "${FUWA_TIMESTAMP_ARGUMENT}" \
        --entitlements "${FUWA_PROJECT_DIR}/Resources/LocalSigning.entitlements" \
        --sign "${FUWA_CODESIGN_IDENTITY}" "${FUWA_APP_DIR}"
elif [[ -z "${FUWA_SIGNED_TEAM_ID}" ]]; then
    print -u2 -r -- "error: unable to determine the signed application's Team ID"
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "${FUWA_APP_DIR}"
FUWA_CODESIGN_IDENTITY="${FUWA_CODESIGN_IDENTITY}" \
    "${FUWA_SCRIPT_DIR}/verify-framework-loading.sh" "${FUWA_APP_DIR}"
FUWA_DESIGNATED_REQUIREMENT="$(
    codesign --display --requirements - "${FUWA_APP_DIR}" 2>&1 \
        | /usr/bin/sed -n 's/^#*[[:space:]]*designated => //p'
)"
if [[ -z "${FUWA_DESIGNATED_REQUIREMENT}" ]]; then
    print -u2 -r -- "error: packaged app has no designated requirement"
    exit 1
fi
if [[ "${FUWA_DESIGNATED_REQUIREMENT:l}" == *cdhash* ]]; then
    print -u2 -r -- "error: stable package unexpectedly has a build-specific cdhash requirement"
    exit 1
fi
FUWA_CODESIGN_IDENTITY="${FUWA_CODESIGN_IDENTITY}" \
    "${FUWA_SCRIPT_DIR}/package-dmg.sh" "${FUWA_APP_DIR}" "${FUWA_ARCHIVE_PATH}"

echo "Built ${FUWA_APP_DIR}"
echo "Archived ${FUWA_ARCHIVE_PATH}"
echo "Signing identity: ${FUWA_CODESIGN_IDENTITY}"
echo "Designated requirement: ${FUWA_DESIGNATED_REQUIREMENT}"
