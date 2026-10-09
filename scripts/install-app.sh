#!/bin/zsh
set -euo pipefail

# Build, verify, and update one canonical Fuwa installation without silently
# changing its macOS code identity.

readonly FUWA_SCRIPT_DIR="${0:A:h}"
readonly FUWA_PROJECT_DIR="${FUWA_SCRIPT_DIR:h}"
readonly FUWA_BUILD_APP="${FUWA_PROJECT_DIR}/dist/Fuwa.app"
readonly FUWA_EXPECTED_IDENTIFIER="app.yuxino.fuwa"
FUWA_INSTALL_APP="${FUWA_INSTALL_PATH:-/Applications/Fuwa.app}"
FUWA_SHOULD_LAUNCH=1

usage() {
    cat >&2 <<'EOF'
Usage: ./scripts/install-app.sh [--no-build] [--no-launch]

Builds and installs Fuwa at /Applications/Fuwa.app with one stable identity.
Set FUWA_INSTALL_PATH only to choose another permanent absolute .app path.
EOF
    exit 2
}

FUWA_SHOULD_BUILD=1
while (( $# > 0 )); do
    case "$1" in
        --no-build) FUWA_SHOULD_BUILD=0 ;;
        --no-launch) FUWA_SHOULD_LAUNCH=0 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
    shift
done

case "${FUWA_INSTALL_APP}" in
    /*/*.app) ;;
    *)
        print -u2 -r -- "error: FUWA_INSTALL_PATH must be an absolute .app path"
        exit 2
        ;;
esac
[[ ! -L "${FUWA_INSTALL_APP}" ]] || {
    print -u2 -r -- "error: the canonical app path cannot be a symbolic link"
    exit 1
}

FUWA_REQUESTED_PARENT="${FUWA_INSTALL_APP:h}"
FUWA_INSTALL_NAME="${FUWA_INSTALL_APP:t}"
[[ -d "${FUWA_REQUESTED_PARENT}" && -w "${FUWA_REQUESTED_PARENT}" ]] || {
    print -u2 -r -- "error: install directory is not writable: ${FUWA_REQUESTED_PARENT}"
    exit 1
}
FUWA_INSTALL_PARENT="${FUWA_REQUESTED_PARENT:A}"
FUWA_INSTALL_APP="${FUWA_INSTALL_PARENT}/${FUWA_INSTALL_NAME}"
case "${FUWA_INSTALL_PARENT}" in
    *.app|*.app/*)
        print -u2 -r -- "error: Fuwa cannot be installed inside another app bundle"
        exit 1
        ;;
esac
[[ "${FUWA_INSTALL_APP}" != "${FUWA_BUILD_APP}" ]] || {
    print -u2 -r -- "error: the canonical path cannot be the disposable build bundle"
    exit 1
}

bundle_identifier() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$1/Contents/Info.plist" 2>/dev/null
}

designated_requirement() {
    codesign --display --requirements - "$1" 2>&1 \
        | /usr/bin/sed -n 's/^#*[[:space:]]*designated => //p'
}

verify_fuwa_app() {
    local FUWA_APP="$1"
    [[ -d "${FUWA_APP}" && ! -L "${FUWA_APP}" ]] || return 1
    codesign --verify --deep --strict "${FUWA_APP}" || return 1
    [[ "$(bundle_identifier "${FUWA_APP}")" == "${FUWA_EXPECTED_IDENTIFIER}" ]] || return 1
    local FUWA_REQUIREMENT="$(designated_requirement "${FUWA_APP}")"
    [[ -n "${FUWA_REQUIREMENT}" && "${FUWA_REQUIREMENT:l}" != *cdhash* ]]
}

if (( FUWA_SHOULD_BUILD == 1 )); then
    "${FUWA_SCRIPT_DIR}/package-app.sh"
fi
verify_fuwa_app "${FUWA_BUILD_APP}" || {
    print -u2 -r -- "error: the built Fuwa app is unsigned, ad-hoc, or otherwise invalid"
    exit 1
}
FUWA_NEW_REQUIREMENT="$(designated_requirement "${FUWA_BUILD_APP}")"

if [[ -e "${FUWA_INSTALL_APP}" && ! -d "${FUWA_INSTALL_APP}" ]]; then
    print -u2 -r -- "error: install path exists but is not an app bundle: ${FUWA_INSTALL_APP}"
    exit 1
fi
if [[ -d "${FUWA_INSTALL_APP}" ]]; then
    verify_fuwa_app "${FUWA_INSTALL_APP}" || {
        print -u2 -r -- "error: existing Fuwa installation is invalid or ad-hoc"
        print -u2 -r -- "Set FUWA_ALLOW_IDENTITY_CHANGE=1 only for the one-time migration."
        [[ "${FUWA_ALLOW_IDENTITY_CHANGE:-0}" == "1" ]] || exit 1
    }
    FUWA_OLD_REQUIREMENT="$(designated_requirement "${FUWA_INSTALL_APP}" || true)"
    if [[ "${FUWA_OLD_REQUIREMENT}" != "${FUWA_NEW_REQUIREMENT}" ]]; then
        if [[ "${FUWA_ALLOW_IDENTITY_CHANGE:-0}" != "1" ]]; then
            cat >&2 <<EOF
error: refusing to replace Fuwa with a different macOS code identity.

Installed: ${FUWA_OLD_REQUIREMENT:-<invalid or unsigned>}
New:       ${FUWA_NEW_REQUIREMENT}

A deliberate migration requires one run with FUWA_ALLOW_IDENTITY_CHANGE=1 and
may require one final Screen Recording authorization.
EOF
            exit 1
        fi
        print -u2 -r -- "warning: performing an explicit one-time code-identity migration"
    fi
fi

FUWA_RUNNING_PIDS="$(/usr/bin/pgrep -U "$(/usr/bin/id -u)" -x Fuwa || true)"
if [[ -n "${FUWA_RUNNING_PIDS}" ]]; then
    print -u2 -r -- "error: quit every running Fuwa copy before installing (PID ${FUWA_RUNNING_PIDS//$'\n'/, })"
    exit 1
fi

FUWA_STAGING_DIR="$(/usr/bin/mktemp -d "${FUWA_INSTALL_PARENT}/.fuwa-install.XXXXXX")"
case "${FUWA_STAGING_DIR}" in
    "${FUWA_INSTALL_PARENT}"/.fuwa-install.*) ;;
    *)
        print -u2 -r -- "error: unexpected staging path: ${FUWA_STAGING_DIR}"
        exit 1
        ;;
esac
FUWA_STAGED_APP="${FUWA_STAGING_DIR}/new.app"
FUWA_PREVIOUS_APP="${FUWA_STAGING_DIR}/previous.app"
FUWA_INSTALL_COMMITTED=0

cleanup() {
    if [[ -d "${FUWA_PREVIOUS_APP:-}" && ! -e "${FUWA_INSTALL_APP}" ]]; then
        /bin/mv "${FUWA_PREVIOUS_APP}" "${FUWA_INSTALL_APP}" || true
    fi
    if [[ "${FUWA_INSTALL_COMMITTED:-0}" == "1" ]]; then
        /bin/rm -rf "${FUWA_STAGING_DIR}"
    elif [[ -d "${FUWA_STAGING_DIR:-}" ]]; then
        print -u2 -r -- "warning: interrupted install preserved at ${FUWA_STAGING_DIR}"
    fi
}
trap cleanup EXIT

/usr/bin/ditto "${FUWA_BUILD_APP}" "${FUWA_STAGED_APP}"
verify_fuwa_app "${FUWA_STAGED_APP}" || {
    print -u2 -r -- "error: staged app failed signature verification"
    exit 1
}
[[ "$(designated_requirement "${FUWA_STAGED_APP}")" == "${FUWA_NEW_REQUIREMENT}" ]] || {
    print -u2 -r -- "error: staged app identity changed during copying"
    exit 1
}

if [[ -d "${FUWA_INSTALL_APP}" ]]; then
    /bin/mv "${FUWA_INSTALL_APP}" "${FUWA_PREVIOUS_APP}"
fi
if ! /bin/mv "${FUWA_STAGED_APP}" "${FUWA_INSTALL_APP}"; then
    [[ ! -d "${FUWA_PREVIOUS_APP}" ]] \
        || /bin/mv "${FUWA_PREVIOUS_APP}" "${FUWA_INSTALL_APP}"
    print -u2 -r -- "error: Fuwa could not be installed"
    exit 1
fi

if ! verify_fuwa_app "${FUWA_INSTALL_APP}" \
    || [[ "$(designated_requirement "${FUWA_INSTALL_APP}")" != "${FUWA_NEW_REQUIREMENT}" ]]; then
    /bin/rm -rf "${FUWA_INSTALL_APP}"
    [[ ! -d "${FUWA_PREVIOUS_APP}" ]] \
        || /bin/mv "${FUWA_PREVIOUS_APP}" "${FUWA_INSTALL_APP}"
    print -u2 -r -- "error: installed Fuwa failed final identity verification"
    exit 1
fi

FUWA_INSTALL_COMMITTED=1
/bin/rm -rf "${FUWA_PREVIOUS_APP}"
print -r -- "Installed stable Fuwa app: ${FUWA_INSTALL_APP}"
print -r -- "Designated requirement: ${FUWA_NEW_REQUIREMENT}"

if (( FUWA_SHOULD_LAUNCH == 1 )); then
    /usr/bin/open -n "${FUWA_INSTALL_APP}"
fi
