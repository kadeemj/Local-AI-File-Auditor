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

Phases 0–11 are complete.

### Phases 0–10

Engine + app shell + apply/undo + CSV/PDF reports. See commits through `46f8ca4`.

### Phase 11 — Trial and Lemon Squeezy licensing

- Keychain-anchored 14-day offline trial (`TrialClock`, `KeychainStore` / `SecureStore`)
- `LicensingBackend` protocol + `LemonSqueezyClient` (activate/validate/deactivate via `NetworkClient` only) + `MockLicensingBackend` (`TEST-PRO`, `TEST-FAIL*`, `TEST-PACK-*`)
- `LicenseManager` state machine: trial → licensed → 30-day offline grace → expired/degraded
- Degraded mode: past findings/history/reports OK; **Scan and Apply disabled**
- Policy-pack unlock via product/variant name mapping (`PolicyPackCatalog`)
- Settings → License UI; Privacy shows last license network call
- Onboarding starts trial; toolbar/dashboard gate on `canScan`
- DEBUG defaults to mock licensing (`AppPreferences.useMockLicensing`)

## Verification

- 106 engine tests / 24 suites pass (`make test`)
- 15 app tests pass (`make test-app`) — bookmarks, ScanSessionModel, PDF, TrialClock, LicenseManager
- `make build` succeeds; network-policy gate passes (Lemon client uses `NetworkClient` only)

Useful commands:

```sh
swift test --package-path Packages/AuditorCore
make build
make test-app
Scripts/check_network_policy.sh
```

Dogfood licensing in Debug: complete onboarding (starts trial) → Settings → License → activate `TEST-PRO` or expire trial and confirm Scan is disabled while Reports/History still work.

## Important remaining scaffolds

- Findings/scan-cache persistence is still not fully wired (schema exists; findings live in session state + journal).
- EventKit export exists as an engine API but has no UI yet.
- Real Lemon Squeezy product/variant IDs are configured at storefront time (Phase 13).

## Next phase: Phase 12 — Sparkle and release pipeline

Implement:

- Sandboxed Sparkle 2 (`SPUStandardUpdaterController`, installer/downloader XPC entitlements)
- EdDSA keys + appcast host
- `make release` / `make verify` (archive → `-exportArchive` → notarize → staple → DMG → appcast)
- Beta dry run including real self-update before 1.0

Releases must use archive → `-exportArchive`; a plain Release build carries unsuitable debugging/signing properties. Team `JUQMKZZ7TJ` is already set up — do not redo certificates.

## Later phases

- Phase 13: website and hardening (LS products, static site, perf, Gatekeeper, license edge cases)

Continue the established pattern: implement the full phase, add real tests, dogfood through the CLI or app, run package/app/privacy gates, commit with a detailed message, and push `origin/main`.
