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

Phases 0–10 are complete.

### Phases 0–9

Engine + app shell + apply/undo. See commits through `5f418a1`.

### Phase 10 — CSV and PDF reports

- `AuditorReports`: `AuditReport`, `ReportFormatting`, `CSVExporter` (RFC 4180 escaping)
- CLI: `auditor-cli scan <folder> --csv <path>`
- App Reports tab: summary cards, Export CSV… / Export PDF…
- `PDFReportRenderer` via SwiftUI `ImageRenderer`: summary page, findings by severity, applied-changes log
- Consultant artifact stays on-device; no network involvement

## Verification

- 106 engine tests / 24 suites pass (`make test`)
- 4 app tests pass (`make test-app`) — includes PDF render smoke
- `make build` succeeds; network-policy gate passes
- CLI CSV dogfood emits findings flat file with correct header/escaping

Useful commands:

```sh
swift test --package-path Packages/AuditorCore
make build
make test-app
Scripts/check_network_policy.sh

swift run --package-path Packages/AuditorCore auditor-cli scan <folder> --policy nonprofit --csv ~/Desktop/audit.csv
```

Dogfood in the app: Mock Scan → Reports → Export CSV / Export PDF.

## Important remaining scaffolds

- Findings/scan-cache persistence is still not fully wired (schema exists; findings live in session state + journal).
- EventKit export exists as an engine API but has no UI yet.
- Licensing, Sparkle, and release automation remain future phases.

## Next phase: Phase 11 — trial and Lemon Squeezy licensing

Implement:

- Keychain-anchored 14-day offline trial
- Lemon Squeezy license activate/validate/deactivate
- `LicenseManager` state machine + degraded modes
- Policy-pack unlock path
- Settings → License UI

## Later phases

- Phase 12: Sparkle and scripted release pipeline
- Phase 13: website and hardening

Developer infrastructure is already configured. Do not redo certificates or notarization setup. Releases must use archive → `-exportArchive`; a plain Release build carries unsuitable debugging/signing properties.

Continue the established pattern: implement the full phase, add real tests, dogfood through the CLI or app, run package/app/privacy gates, commit with a detailed message, and push `origin/main`.
