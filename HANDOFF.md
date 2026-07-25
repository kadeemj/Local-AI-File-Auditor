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

Phases 0–9 are complete.

### Phases 0–8

Engine + app shell: crawl, hash, extract, detectors, Foundation Models, policies, expirations/EventKit, onboarding, security-scoped bookmarks, NavigationSplitView, live/mock scans. See commits through `da0ce52`.

### Phase 9 — review, apply, undo

- `ApplyEngine.plan/apply/undo`: rename, move, archive→`_Archive/`; never delete
- Conflicts: missing source, destination exists, in-plan collision, changed-since-scan, dataless cloud placeholders
- Journal-first restore point in GRDB (`apply_journal` + v2 size/mtime metadata); mid-batch failure rolls file ops back
- Undo refuses if an applied file changed afterward; journal survives DB relaunch
- Findings UI: Approve / Dismiss, evidence panel, Quick Look
- Apply tab: preview operations + conflicts, Apply button
- History tab: applied batches with per-batch Undo
- Mock Scan materializes a disposable on-disk fixture so apply/undo can be dogfooded without a folder grant

## Verification

- 102 engine tests / 23 suites pass (`make test`)
- 3 app tests pass (`make test-app`)
- `make build` succeeds; network-policy gate passes
- ApplyEngine round-trip, collision, changed-since-scan, changed-since-apply, journal relaunch, and move tests pass

Useful commands:

```sh
swift test --package-path Packages/AuditorCore
make build
make test-app
Scripts/check_network_policy.sh

swift run --package-path Packages/AuditorCore auditor-cli scan <folder> --policy nonprofit
```

Dogfood in the app: Mock Scan → Approve rename/archive/move findings → Apply tab → Apply → History → Undo.

## Important remaining scaffolds

- Findings/scan-cache persistence is still not fully wired (schema exists; findings live in session state + journal).
- EventKit export exists as an engine API but has no UI yet.
- Reports sidebar entry is a placeholder.
- Licensing, Sparkle, reports, and release automation remain future phases.

## Next phase: Phase 10 — CSV and PDF reports

Implement:

- `CSVExporter` (findings flat file)
- `PDFReportRenderer` via SwiftUI `ImageRenderer`
- Summary page, findings by severity, applied-changes log
- Consultant-facing artifact polish

## Later phases

- Phase 11: trial and Lemon Squeezy licensing
- Phase 12: Sparkle and scripted release pipeline
- Phase 13: website and hardening

Developer infrastructure is already configured. Do not redo certificates or notarization setup. Releases must use archive → `-exportArchive`; a plain Release build carries unsuitable debugging/signing properties.

Continue the established pattern: implement the full phase, add real tests, dogfood through the CLI or app, run package/app/privacy gates, commit with a detailed message, and push `origin/main`.
