# DMG distribution verification

Future packaging and signed release metadata use only Fuwa-<version>.dmg. The initial draft still contains two files and the signed release still contains seven. Installation documentation now says to open the image and drag Fuwa into Applications. Existing ZIP releases and signed feeds retain their reviewed bytes.

Checks on Apple Silicon/macOS 27.0.1:

- Complete strict Release packaging to an isolated output directory passed, including stable app signature, Sparkle framework loading, signed DMG creation, image integrity, read-only mounting, installer layout, mounted bundle seal and SHA-256 generation.
- Six portable installer-layout checks passed, including incorrect destination, missing executable, external app shortcut and unexpected hidden payload rejection.
- Signed-update metadata fixtures passed with DMG records and rejection of a relabeled ZIP record, altered hashes, malformed feeds and invalid signatures.
- Release contract/checksum checks passed. Both workflows parsed and all embedded shell blocks passed syntax checks. Full promotion is not executed for an existing published tag.
- The current 1.2.0 manual installer uses the original public universal application. Its ZIP matched the published digest c2ed4bd0e4b84498b96e0d1ea733112c534407c9937ca3ef4ea72b0a5c5014df, and both binary slices matched the stable designated requirement pin. No different code was rebuilt under 1.2.0.
- The 1.2.0 DMG passed integrity, read-only layout and app signature checks. SHA-256: f35e41742ddd44503e97fe1691aac10212e59aba7bff790accc194bb92f5442e.

The DMG uses the existing local signature; Apple Developer ID signing/notarization is unchanged. Complete Sparkle installation from a DMG and physical Intel hardware are not claimed. The development application remains running; no installed application or user pin was replaced during DMG verification.
