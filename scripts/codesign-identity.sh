#!/bin/zsh
set -euo pipefail

# Resolve one stable identity and print its SHA-1 fingerprint. Fingerprints are
# used instead of certificate names so duplicate names can never be selected
# nondeterministically.

readonly FUWA_SHARED_LOCAL_IDENTITY="mimi Local Development"

fail() {
    print -u2 -r -- "error: $*"
    exit 1
}

typeset -a FUWA_IDENTITY_FINGERPRINTS
typeset -a FUWA_IDENTITY_NAMES
if ! FUWA_IDENTITY_LIST="$(/usr/bin/security find-identity -v -p codesigning)"; then
    fail "the macOS Keychain code-signing identity query failed"
fi

for FUWA_IDENTITY_LINE in "${(@f)FUWA_IDENTITY_LIST}"; do
    FUWA_IDENTITY_FINGERPRINT="$(
        print -r -- "${FUWA_IDENTITY_LINE}" \
            | /usr/bin/sed -nE \
                's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]+)[[:space:]]+"([^"]+)"[[:space:]]*$/\1/p'
    )"
    FUWA_IDENTITY_NAME="$(
        print -r -- "${FUWA_IDENTITY_LINE}" \
            | /usr/bin/sed -nE \
                's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]+)[[:space:]]+"([^"]+)"[[:space:]]*$/\2/p'
    )"
    if [[ -n "${FUWA_IDENTITY_FINGERPRINT}" && -n "${FUWA_IDENTITY_NAME}" ]]; then
        FUWA_IDENTITY_FINGERPRINTS+=("${FUWA_IDENTITY_FINGERPRINT:u}")
        FUWA_IDENTITY_NAMES+=("${FUWA_IDENTITY_NAME}")
    fi
done

resolve_exact_identity() {
    local FUWA_REQUESTED_IDENTITY="$1"
    local -a FUWA_MATCHES
    local FUWA_INDEX

    for (( FUWA_INDEX = 1; FUWA_INDEX <= ${#FUWA_IDENTITY_FINGERPRINTS}; FUWA_INDEX++ )); do
        if [[ "${FUWA_IDENTITY_FINGERPRINTS[FUWA_INDEX]}" == "${FUWA_REQUESTED_IDENTITY:u}" \
            || "${FUWA_IDENTITY_NAMES[FUWA_INDEX]}" == "${FUWA_REQUESTED_IDENTITY}" ]]; then
            FUWA_MATCHES+=("${FUWA_IDENTITY_FINGERPRINTS[FUWA_INDEX]}")
        fi
    done

    case "${#FUWA_MATCHES}" in
        0)
            print -u2 -r -- "error: the requested code-signing identity was not found: ${FUWA_REQUESTED_IDENTITY}"
            # Exit 4 means the Keychain query itself succeeded and the exact
            # requested identity is simply absent.
            exit 4
            ;;
        1)
            print -r -- "${FUWA_MATCHES[1]}"
            ;;
        *)
            fail "multiple valid identities match '${FUWA_REQUESTED_IDENTITY}'; use the certificate fingerprint"
            ;;
    esac
}

if [[ "${FUWA_CODESIGN_IDENTITY:-}" == "-" ]]; then
    fail "ad-hoc signing is not allowed for an app that can request macOS privacy permissions"
fi

if [[ -n "${FUWA_CODESIGN_IDENTITY:-}" ]]; then
    resolve_exact_identity "${FUWA_CODESIGN_IDENTITY}"
    exit 0
fi

typeset -a FUWA_APPLE_DEVELOPMENT_IDENTITIES
typeset -a FUWA_SHARED_LOCAL_IDENTITIES
for (( FUWA_INDEX = 1; FUWA_INDEX <= ${#FUWA_IDENTITY_FINGERPRINTS}; FUWA_INDEX++ )); do
    if [[ "${FUWA_IDENTITY_NAMES[FUWA_INDEX]}" == "Apple Development:"* ]]; then
        FUWA_APPLE_DEVELOPMENT_IDENTITIES+=("${FUWA_IDENTITY_FINGERPRINTS[FUWA_INDEX]}")
    fi
    if [[ "${FUWA_IDENTITY_NAMES[FUWA_INDEX]}" == "${FUWA_SHARED_LOCAL_IDENTITY}" ]]; then
        FUWA_SHARED_LOCAL_IDENTITIES+=("${FUWA_IDENTITY_FINGERPRINTS[FUWA_INDEX]}")
    fi
done

case "${#FUWA_SHARED_LOCAL_IDENTITIES}" in
    1)
        print -r -- "${FUWA_SHARED_LOCAL_IDENTITIES[1]}"
        exit 0
        ;;
    0) ;;
    *)
        fail "multiple '${FUWA_SHARED_LOCAL_IDENTITY}' identities are valid; set FUWA_CODESIGN_IDENTITY to the intended fingerprint"
        ;;
esac

case "${#FUWA_APPLE_DEVELOPMENT_IDENTITIES}" in
    1)
        print -r -- "${FUWA_APPLE_DEVELOPMENT_IDENTITIES[1]}"
        exit 0
        ;;
    0) ;;
    *)
        fail "multiple Apple Development identities are valid; set FUWA_CODESIGN_IDENTITY to the intended fingerprint"
        ;;
esac

cat >&2 <<'EOF'
error: no stable macOS code-signing identity is available.

Run ./scripts/setup-local-signing.sh once, install an Apple Development
identity, or set FUWA_CODESIGN_IDENTITY to an existing certificate fingerprint.
Fuwa refuses to create a normal ad-hoc build because doing so would make macOS
ask for Screen Recording permission again after a rebuild.
EOF
# Exit 3 is reserved for the one safe setup condition: the Keychain query
# succeeded, but no default stable identity exists yet.
exit 3
