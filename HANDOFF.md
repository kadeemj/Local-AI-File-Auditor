# FolderLint — Session Handoff

Status: 2026-07-25. Repository: `/Users/kadeem/Dev/mac_file_auditor`

Current commit: see `git log -1`. Working tree should be clean after Phase 8. Always trust `git log` over this summary.

## Product

FolderLint is “Grammarly for your files and folders”: a privacy-first macOS app that audits user-selected local, cloud-synced, and NAS folders without replacing Finder or importing files into a proprietary library.

Trust model:

- Audit-only by default.
- Every recommendation includes evidence and an explanation.
- All analysis runs on-device.
- Never deletes files; only rename and move operations are allowed.
- Future mutations require approve → preview → restore point → apply → undo.
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

Phases 0–8 are complete.

### Phases 0–7

Engine complete: crawler, hashing, extraction, duplicates, version families, Foundation Models judge, policies/renames/misfiled, dated obligations + EventKit export. See prior commits `2fd67b4`, `7b4897c`, `4ec3fd3`.

### Phase 8 — app shell

- `AppModel` DI root with Application Support GRDB database
- Onboarding: privacy → `NSOpenPanel` folder grant → policy picker
- `FolderAccessManager` + `SecurityScopedBookmark`: create, persist (`watched_folders`), restore, stale re-grant
- `ScanSessionModel` consumes `AsyncStream<ScanEvent>` (mock stream + live engine)
- `NavigationSplitView`: Dashboard / Findings / Renames / Expirations / History+Reports stubs
- Settings: General (mock scan toggle), Folders, Policy, Privacy; License/Updates stubs
- `AuditorEngine.startScan` now runs the real crawl → hash → extract → detect pipeline (`ScanPipeline`); CLI is a thin front-end
- Watched-folder CRUD on `AuditorDatabase`
- `ScanSessionState` pure reducer for UI/tests
- App unit tests: bookmark round-trip + mock stream consumption (`make test-app`)

## Verification

- 95 engine tests / 22 suites pass (`make test`)
- 2 app tests pass (`make test-app`)
- `make build` succeeds; network-policy gate passes
- Sandbox entitlements present: app-sandbox, user-selected read-write, bookmarks.app-scope, calendars
- CLI fixture scan via engine emits exact-duplicate finding

Useful commands:

```sh
swift test --package-path Packages/AuditorCore
make build
make test-app
Scripts/check_network_policy.sh

swift run --package-path Packages/AuditorCore auditor-cli scan <folder> --policy nonprofit
swift run --package-path Packages/AuditorCore auditor-cli scan <folder> --policy nonprofit --json
swift run --package-path Packages/AuditorCore auditor-cli extract <file>
```

Open the Debug app and dogfood: complete onboarding, grant a disposable folder, run Scan (or Mock Scan from the Dashboard). Verify grants survive relaunch; Restore… appears if a bookmarked folder is moved.

## Important remaining scaffolds

- Findings/scan-cache persistence is still not fully wired (schema exists; engine streams findings to UI only).
- `AuditorApply` has early types only; safe apply/undo is Phase 9.
- EventKit export exists as an engine API but has no UI yet.
- History / Reports sidebar entries are placeholders.
- Licensing, Sparkle, reports, and release automation remain future phases.

## Next phase: Phase 9 — review, preview, apply, rollback, undo

Implement:

- Results / Rename / Expirations UIs with evidence panels + Quick Look
- `ApplyEngine`: plan → preview → conflicts → restore point → apply → undo
- History of applied batches with per-batch Undo
- Never delete; archive = move to `_Archive/`

## Later phases

- Phase 10: CSV and PDF reports
- Phase 11: trial and Lemon Squeezy licensing
- Phase 12: Sparkle and scripted release pipeline
- Phase 13: website and hardening

Developer infrastructure is already configured. Do not redo certificates or notarization setup. Releases must use archive → `-exportArchive`; a plain Release build carries unsuitable debugging/signing properties.

Continue the established pattern: implement the full phase, add real tests, dogfood through the CLI or app, run package/app/privacy gates, commit with a detailed message, and push `origin/main`.
