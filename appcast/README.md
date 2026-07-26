# Appcast feed (Sparkle)

Production feed URL (also in `FolderLint/Info.plist` as `SUFeedURL`):

`https://folderlint.com/appcast.xml`

This directory is the source of truth that gets published to that host (GitHub
Pages or the Phase 13 static site). `make release VERSION=x.y.z` refreshes
`appcast.xml` and copies signed `FolderLint-*.zip` update archives here.

## Key material

- Public key: `SUPublicEDKey` in Info.plist
- Private key: macOS Keychain account `folderlint`, backed up at
  `~/.folderlint/sparkle_eddsa_private.key`

Never commit the private key. Run `make keys` to print / re-export.
