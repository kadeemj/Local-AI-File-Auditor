# FolderLint release pipeline

Phase 12 distribution path for Developer ID + notarization + Sparkle 2.

## Prerequisites (one-time)

1. **Developer ID Application** certificate for team `JUQMKZZ7TJ` (already on this Mac).
2. **Notary credentials** in Keychain:
   ```sh
   xcrun notarytool store-credentials "notary-profile" \
     --apple-id "…" --team-id JUQMKZZ7TJ --password "@keychain:…"
   ```
3. **Sparkle EdDSA keys** (already generated for account `folderlint`):
   ```sh
   make keys
   ```
   Immediately copy `~/.folderlint/sparkle_eddsa_private.key` into a password
   manager. Losing this key strands every installed copy — they can never update.
4. Optional nicer DMGs: `brew install create-dmg`
5. Sparkle CLI tools on `PATH` or at `/tmp/Sparkle-bin/bin` (see
   [Sparkle releases](https://github.com/sparkle-project/Sparkle/releases)).

## Ship a build

```sh
make release VERSION=0.9.0
```

This always:

1. Regenerates the Xcode project
2. Bumps `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Config/Shared.xcconfig`
3. **Archives** then **`-exportArchive`** with `Config/ExportOptions.plist`
   (developer-id). Never ship a plain Release build from the build folder.
4. Notarizes + staples the `.app`
5. Builds the Sparkle zip from the stapled app (`ditto -c -k --keepParent`)
6. Builds a DMG, notarizes + staples it
7. Refreshes `appcast/appcast.xml`
8. Runs `Scripts/verify.sh`

Artifacts land in `dist/<version>/`. Publish the DMG (download), the zip
(Sparkle), and `appcast.xml` to `https://folderlint.com/`.

## Verify an artifact

```sh
make verify APP=dist/0.9.0/export/FolderLint.app DMG=dist/0.9.0/FolderLint-0.9.0.dmg
```

Checks: `codesign --verify --strict`, sandbox + Sparkle mach-lookup
entitlements, `spctl`, stapler validation. Signing itself never uses `--deep`.

## Sandboxed Sparkle notes

- Info.plist: `SUEnableInstallerLauncherService=YES`, `SUEnableSystemProfiling=NO`
- Entitlements: mach-lookup for `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki`
- Do **not** enable `SUEnableDownloaderService` — the app already has
  `com.apple.security.network.client`
- `SPUStandardUpdaterController` is created once in `AppModel` via `UpdaterService`

## 0.9 beta dry-run checklist

Before 1.0:

- [ ] `make release VERSION=0.9.0` succeeds end-to-end
- [ ] Clean VM / secondary Mac: Gatekeeper accepts DMG, first launch offline works
- [ ] Install 0.9.0, publish 0.9.1 appcast entry, confirm in-app update installs
- [ ] Confirm Little Snitch / network log shows only `api.lemonsqueezy.com` + appcast host
