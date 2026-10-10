# Fuwa Release Runbook

Fuwa is maintained for macOS only. A release maintainer produces the universal
archive on a trusted Mac holding Fuwa's stable local signing identity. GitHub
Actions verifies the macOS build and logic tests, and the promotion workflow
independently verifies the archive, signs the exact reviewed update package,
and generates the signed Sparkle feed and macOS-only `latest.json`.

Pushing a tag does not publish a Release. Publication is a separate manual
promotion of an already reviewed draft. This runbook applies only to tags that
include the [macOS-only decision](decisions/2026-09-06-macos-only.md); do not use
it to re-promote historical multi-platform tags or delete their release assets.
The DMG contract applies to tags containing the DMG packaging change. Older
ZIP releases and their signed metadata remain intact. A manual-download DMG
may be added to an older release only by wrapping its exact verified public app;
never rebuild different code under an existing version or replace its signed feed.

## 1. Freeze the release commit

On a clean `main` checkout:

1. Move release notes from `Unreleased` into the dated version section.
2. Set the public version and monotonically increasing build number in
   `Resources/Info.plist`. Keep the release notes and tag version aligned.
3. Run the strict macOS Release build and `FuwaLogicTests`, app-icon validation,
   shell checks, checksum-parser tests, update-metadata tests, and
   `python3 scripts/test-macos-only.py`.
4. Complete native interactive acceptance for capture, permissions, freeze,
   privacy boundaries, and updating. Hosted compilation is not interactive
   acceptance. Keep Intel hardware limitations explicit in release notes.

Create and push `v<public-version>` only after the release commit is on `main`.
Require that tag's `CI` workflow to succeed. Windows builds and artifacts are
not part of this release contract.

## 2. Produce the archive on the trusted Mac

```sh
git switch --detach "v<public-version>"
./scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 dist/Fuwa.app
lipo dist/Fuwa.app/Contents/MacOS/Fuwa -verify_arch arm64 x86_64
(cd dist && shasum -a 256 -c "Fuwa-<public-version>.dmg.sha256")
```

Replace the placeholders with the actual version. Confirm the full designated
requirement matches the previous stable package. Stop if identity changes.
The current package has no Apple Developer ID signature or notarization; the
Release notes must say so. Do not substitute an ad-hoc-signed hosted build.

Packaging creates a compressed DMG with the application and an Applications
shortcut. It checks the image, mounts it read-only, verifies the installer layout
and bundle code seal, and writes the SHA-256 file. Sparkle supports DMG update
archives, so the same reviewed image is signed for manual and in-app updates.
See [Sparkle distribution formats](https://sparkle-project.org/documentation/).

The stable local certificate has no Apple Team ID. For that signing profile
only, packaging gives the host `com.apple.security.cs.disable-library-validation`
so it can load the bundled, locally signed Sparkle framework. Other Hardened
Runtime protections remain enabled; Apple team-signed builds receive no such
exception. This does not change system Gatekeeper settings or update signature
verification. See [Apple's library validation rules](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

Packaging also runs `scripts/verify-framework-loading.sh` to load the embedded
framework using the host's signing identity and entitlements. A valid code seal
alone does not prove that dyld will allow the app to start. The probe covers the
trusted Mac's native architecture; it does not replace app launch, capture,
update installation or Intel hardware acceptance.

Promotion independently repeats the bundle, universal-binary, code-seal,
leaf-certificate, and designated-requirement checks on a hosted Mac. Stable
pins live in `scripts/release-signing-pins.json`, extracted from the public
`v0.1.1` archive whose hash is recorded there. The requirement pin describes
the embedded Requirement blob in each Mach-O slice, not a certificate name.
Changing pins is a separate, explicit signing-identity migration.

## 3. Assemble the draft

Create a draft Release for the existing tag and upload exactly two files:

- `Fuwa-<public-version>.dmg`
- `Fuwa-<public-version>.dmg.sha256`

Verify the archive independently and record its SHA-256. Release notes must
state the signing/notarization status and distinguish automated checks from
native interactive acceptance. Do not add historical Windows packages or feeds
to a new Mac-only draft. Existing versioned Windows Releases remain archived
and unsupported; their latest-feed URLs stop being supplied by future releases.

## 4. Promote the exact reviewed bytes

Run **Promote release draft** with the tag, accepted macOS archive SHA-256,
and this exact confirmation (substituting the tag):

```text
publish Fuwa v<public-version> with unnotarized macOS assets
```

The workflow requires:

- The tag commit is on `origin/main`, its version matches `Info.plist`, and
  its tag CI succeeded.
- The stable draft initially contains exactly the two files above, and the
  accepted hash matches the archive and checksum.
- The read-only DMG contains `Fuwa.app` and an `/Applications` shortcut,
  matches the version and bundle ID,
  includes arm64/x86_64, passes deep/strict code sealing, and matches the
  pinned certificate and designated requirement in both Mach-O slices.
- Ed25519 signing uses the existing `FUWA_UPDATER_ED25519_PRIVATE_KEY`, verifies
  valid and altered payloads, and generates the same macOS `appcast.xml` path.
- The final inventory is exactly seven files: the DMG, its `.sha256` and
  `.sig`, `appcast.xml`, `appcast.xml.sig`, `latest.json`, and `latest.json.sig`.
  The manifest contains exactly one `macos-universal` record.
- No asset changes between the final verification snapshot and publication;
  post-publication state, asset inventory, and `/latest` are checked again.

Keep required reviewers on the `release-promotion` GitHub environment. The
workflow signs and uploads metadata, then performs the protected final
publication step. It does not build packages, create tags, or repair drafts.
A partially processed draft must be reviewed before retrying; restore the
reviewed two-file draft rather than weakening the inventory checks.

The updater private key stays in its GitHub Actions secret. Its recovery copy
is the maintainer's macOS login Keychain item for account
`app.yuxino.fuwa.updater`; never commit, log, or attach it to a Release.
