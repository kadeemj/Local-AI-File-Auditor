# FolderLint — Session Handoff

Status: 2026-07-25. Repository: `/Users/kadeem/Dev/mac_file_auditor`

Current commit: see `git log -1`. Always trust `git log` over this summary.

## Product

FolderLint is “Grammarly for your files and folders”: a privacy-first macOS app that audits user-selected local, cloud-synced, and NAS folders without replacing Finder or importing files into a proprietary library.

Trust model:

- Audit-only by default.
- Every recommendation includes evidence and an explanation.
- All analysis runs on-device.
- Never deletes files; only rename and move operations are allowed.
- Mutations require approve → preview → restore point → apply → undo.
- Network access is restricted to license validation and update checks.

First market: nonprofits and other small organizations using shared cloud folders without a records manager.

## Locked decisions

- Name: FolderLint
- Bundle ID: `com.folderlint.app`
- Stack: Swift 6, SwiftUI, macOS 26 minimum, Apple Silicon
- Sandbox: enabled, including security-scoped folder grants
- Distribution: direct Developer ID download, notarized DMG, Sparkle 2
- Apple team: `JUQMKZZ7TJ` — Kadeem’s personal team
- Persistence: GRDB/SQLite, never SwiftData
- AI: deterministic rules first; Apple Foundation Models only for validated semantic judgments; rules-only fallback always
- File changes: rename and move only, never delete
- Licensing: Lemon Squeezy
- No telemetry or crash SDKs

Full design and 14-phase roadmap:

`~/.claude/plans/local-ai-file-auditor-abundant-goose.md`

## Current implementation state

Phases 0–12 are complete (Phase 12 pipeline is wired; 0.9 beta dry-run is the remaining gate before 1.0).

### Phases 0–11

Engine + app shell + apply/undo + reports + licensing. See commits through `e1708b4`.

### Phase 12 — Sparkle + release pipeline

- Sparkle ≥2.8 via SPM; `UpdaterService` owns one `SPUStandardUpdaterController` in `AppModel`
- Sandbox: `SUEnableInstallerLauncherService`, mach-lookup `-spks`/`-spki`; no Downloader XPC (app has network.client)
- Info.plist: `SUFeedURL=https://folderlint.com/appcast.xml`, `SUPublicEDKey`, profiling off
- Settings → Updates UI + menu “Check for Updates…”
- Scripts: `release.sh`, `notarize.sh`, `make_dmg.sh`, `update_appcast.sh`, `verify.sh`, `generate_sparkle_keys.sh`
- `make release VERSION=x.y.z` / `make verify APP=…` / `make keys`
- `Config/ExportOptions.plist` (developer-id); docs in `docs/RELEASE.md`
- EdDSA private key: Keychain account `folderlint`, backup at `~/.folderlint/sparkle_eddsa_private.key` (**never commit**; back up to password manager)

## Verification

- Engine + app tests + network-policy gate (see latest `make test` / `make test-app`)
- Full notarized release + real self-update is the 0.9 beta dry-run (checklist in `docs/RELEASE.md`)

Useful commands:

```sh
make generate && make build && make test-app
Scripts/check_network_policy.sh
make keys
make release VERSION=0.9.0   # when ready for beta dry-run
make verify APP=dist/0.9.0/export/FolderLint.app DMG=dist/0.9.0/FolderLint-0.9.0.dmg
```

## Important remaining scaffolds

- Findings/scan-cache persistence is still not fully wired (schema exists; findings live in session state + journal).
- EventKit export exists as an engine API but has no UI yet.
- Real Lemon Squeezy product/variant IDs and folderlint.com hosting are Phase 13.
- **0.9 beta dry-run** (Gatekeeper + real Sparkle self-update) before calling distribution done.

## Next phase: Phase 13 — website and hardening

Implement:

- Static site + network policy page; publish appcast
- Lemon Squeezy products/variants/checkout
- 100k-file perf pass; clean-VM offline Gatekeeper; license + apply/undo abuse cases

Releases must use archive → `-exportArchive`; never `codesign --deep`. Team `JUQMKZZ7TJ` is already set up.

Continue the established pattern: implement the full phase, add real tests, dogfood, run gates, commit with a detailed message, and push `origin/main`.
