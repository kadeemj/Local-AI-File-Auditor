# FolderLint — Session Handoff

Status as of 2026-07-25. Paste this file (or point a fresh chat at it) to resume work with full context. It reflects the actual repo state as of commit `becfc69` — always trust `git log` over this document if they disagree.

## What FolderLint is

**Positioning: "Grammarly for your files and folders."** A privacy-first macOS app that audits the folders a user already has (local, Box/Drive/Dropbox-synced, NAS) and finds organizational, privacy, and document-quality problems — without replacing Finder or requiring files to be imported into a database (the anti-DEVONthink differentiator). Every recommendation must show evidence and an explanation; the product never says "AI thinks this is wrong."

**Trust model:** audit-only by default. Findings only become file changes through an explicit approve → preview → restore-point → apply → undo workflow, and FolderLint **never deletes** — only renames/moves. All analysis is on-device. The only network calls anywhere in the app are license validation and update checks (this is an engineered, testable claim, not a slogan — see Network Policy below).

**First market:** small organizations using cloud folders without a records manager — nonprofits first (a "Nonprofit File Governance Pack" policy template ships in v1), then consultants, small law/accounting firms, property managers.

**v1 scope — five detector functions:**
1. Duplicates — three levels: exact (hash), content (same text, different bytes/format), version families (`Policy_FINAL_v2_NEW.pdf`)
2. Filename policy auditing (deterministic lint against a naming template)
3. AI filename recommendations (Foundation Models fills the template's slots)
4. Wrong-folder / misfiled document detection (embedding-based folder profiles)
5. Contract/document expiration extraction (understands date *meaning*, not just presence)

Explicitly **deferred**: sensitive-info scanning (false-positive/legal risk — ship after the org engine validates), metadata *editing*, Finder Sync extension, menu bar item, FSEvents continuous monitoring, team approval workflows, direct cloud APIs, Mac App Store build, CI, any telemetry.

## Locked decisions (do not relitigate without a reason)

| Decision | Choice | Why |
|---|---|---|
| Name | **FolderLint**, bundle ID `com.folderlint.app` | Rebranded from a placeholder ID early, before TCC grants/Keychain items/Sparkle baked the old one in |
| Stack | Swift 6 + SwiftUI, macOS 26 (Tahoe) min, Apple Silicon | Native, on-device AI story |
| Sandbox | **App Sandbox ON**, even though direct-distributed (not App Store) | Makes "can't read what you didn't select" OS-enforced, not just a policy promise |
| Distribution | Direct download: Developer ID + notarized DMG, Sparkle 2 | No App Store sandbox/payment constraints |
| Apple team | **JUQMKZZ7TJ** (Kadeem's personal/iCloud team) — NOT the lavalabs.ai team (7M89HM3W7T) | User's explicit choice; Gatekeeper will show "Kadeem Jeffery," not "FolderLint," unless an org is enrolled later |
| Persistence | **GRDB (SQLite)** everywhere, no SwiftData | Bulk scan-cache writes (100k+ rows), real indexes, headless-testable |
| AI | Deterministic rules first; **Apple Foundation Models** (on-device) for semantic judgment; rules-only fallback always | Product must be fully useful with Apple Intelligence off/unavailable |
| Mutation policy | Rename + move only, **never delete**; "archive" = move to `_Archive/` | Trust feature; every applied batch is journaled and undoable |
| Licensing | Lemon Squeezy — Personal $79/yr, Professional $129/yr, Small Team $99/mo, Business $199/mo, Consultant $399/mo, policy packs as add-ons | Merchant-of-record, unauthenticated license-key API, no backend to run |

Full original design rationale (all alternatives considered, not just the winners) is in the plan file: `~/.claude/plans/local-ai-file-auditor-abundant-goose.md`. That plan also has the complete 14-phase roadmap and per-phase deliverables — treat it as the spec; this handoff is the status report.

## Apple developer infrastructure (already set up — do not redo)

- Developer ID Application certificate installed in login keychain: `Developer ID Application: Kadeem Jeffery (JUQMKZZ7TJ)`
- Notarization credentials stored as keychain profile **`notary-profile`** (ASC API key `9538C9Q9A5` at `~/.appstoreconnect/private_keys/AuthKey_9538C9Q9A5.p8`, issuer `286eeebe-7c65-49fa-965a-9c5adb7fe88f`)
- **Full release chain verified end-to-end** on 2026-07-25: archive → `-exportArchive` (developer-id method, `ExportOptions.plist`) → notarize (Accepted) → staple → `spctl` confirms "Notarized Developer ID"
- **Critical gotcha already learned:** a plain `xcodebuild build` Release binary fails notarization (no secure timestamp, carries the debugger `get-task-allow` entitlement). Releases **must** go through `archive` + `-exportArchive`, never a plain build.
- Not yet done: nothing blocking — Phase 12 will just script the manual sequence above into `Scripts/release.sh`

## Repo layout

```
mac_file_auditor/                       (GitHub: kadeemj/Local-AI-File-Auditor)
├── FolderLint.xcodeproj                # generated by XcodeGen — do not hand-edit
├── project.yml                         # ← the real source of truth for the Xcode project; `make generate`
├── Config/                             # Shared/Debug/Release/Signing.xcconfig
├── ExportOptions.plist                 # developer-id export config (Phase 12 proof)
├── FolderLint/                         # SwiftUI app target (currently a placeholder shell — Phase 8+)
│   ├── App/                            # FolderLintApp, AppModel, RootView
│   ├── Services/Network/NetworkClient.swift   # the ONLY networking file in the app (host allowlist)
│   ├── FolderLint.entitlements         # app-sandbox, user-selected r/w, bookmarks, network.client
│   └── Info.plist
├── Packages/AuditorCore/               # THE ENGINE — everything real is here right now
│   ├── Package.swift
│   ├── Sources/
│   │   ├── AuditorModels/              # FileRecord, Finding, Evidence, RecommendedAction, ScanEvent…
│   │   ├── AuditorCrawl/               # FileCrawler (real, tested)
│   │   ├── AuditorHashing/             # SHA256Hasher, StagedHashPipeline, TextFingerprint (MinHash),
│   │   │                               #   ContentDuplicateFinder (LSH)
│   │   ├── AuditorExtract/             # DefaultTextExtractor (PDFKit→Vision OCR→docx/plain), MetadataReader
│   │   ├── AuditorPolicy/              # Policy model + bundled nonprofit/small-business JSON templates
│   │   ├── AuditorDetect/              # Detector protocol; DuplicateDetector, ContentDuplicateDetector,
│   │   │                               #   VersionChainDetector, VersionTokenParser, ClusterRanker,
│   │   │                               #   KeeperRanking (shared heuristic)
│   │   ├── AuditorAI/                  # ModelAvailability only so far — Phase 5 fills this in
│   │   ├── AuditorStore/               # GRDB schema (scans, scan_cache, findings, watched_folders,
│   │   │                               #   folder_profiles, apply_journal) — schema exists, mostly unused so far
│   │   ├── AuditorApply/               # ApplyOperation/ApplyPlan types only — engine logic is Phase 9
│   │   ├── AuditorEngine/              # AuditorEngine/ScanHandle — scaffold only, not wired to real pipeline yet
│   │   └── auditor-cli/                # main.swift — REAL, working: `scan` and `extract` subcommands
│   └── Tests/                          # 48 tests, 13 suites, all green
├── Scripts/check_network_policy.sh     # build-phase gate: fails build if URLSession appears outside
│                                        #   Services/Network/ — tested both directions, works
├── docs/NETWORK_POLICY.md              # the auditable privacy claim, written, not yet published to a website
└── Makefile                            # generate / build / test / clean / verify (verify is a stub)
```

## What's actually implemented and tested (Phases 0–4, commits `e19488f`..`becfc69`)

Run `cd Packages/AuditorCore && swift test` — **48 tests, 13 suites, all passing** as of this handoff.

- **Phase 0 (scaffold):** AuditorCore SPM package skeleton, sandboxed app target that builds, network-policy build gate verified in both directions (fails when `URLSession` appears outside `Services/Network/`, passes otherwise).
- **Phase 1 (crawl):** `FileCrawler` — `FileManager.enumerator` with prefetched resource keys, batched `AsyncThrowingStream` (512/batch), skip rules (hidden/packages/denylist/min-size), symlinks skipped, cloud-placeholder flagging with a `localOnly` mode, cooperative cancellation. Verified against the real `~/Dev` tree: 991 files in 135ms.
- **Phase 2 (exact duplicates):** `SHA256Hasher` (partial = head+tail+size, full = streaming 1MiB chunks + `F_NOCACHE`), `StagedHashPipeline` (size→partial→full funnel, hardlink dedupe by file ID, bounded concurrency), `DuplicateDetector` with a deterministic keeper heuristic (penalize "copy"/"(n)"/status words/Downloads location).
- **Phase 3 (text extraction):** `DefaultTextExtractor` routes by extension — PDF text layer via PDFKit, falls back to **Vision OCR** when the layer is trivial (<16 chars, i.e. a scan), `.docx` via ZIPFoundation + `XMLParser` (`<w:t>`/`<w:p>`/`<w:tab>`/`<w:br>`), plain text with UTF-8→Latin-1 fallback, images straight to OCR. 2MB text cap. Cloud placeholders structurally refused. `MetadataReader` reads PDF `documentAttributes`. `DocumentFixtures` test helper generates *real* PDFs/images/docx on the fly (Core Text rendering, not mocks). Verified against a real file from the user's iCloud Drive.
- **Phase 4 (content dups + version families) — the heuristic heart:**
  - `TextFingerprint`: 128-lane MinHash over 5-word shingles of aggressively normalized text (handles OCR's unstable whitespace — this was a real bug caught by testing: "GRANTAGREEMENT" vs "GRANT AGREEMENT").
  - `ContentDuplicateFinder`: LSH banding (32 bands × 4 rows) to avoid O(n²), union-find merges verified pairs, reports the weakest pairwise similarity honestly.
  - `VersionTokenParser`: **32-row TDD table.** Parses explicit versions (v2/rev3/version 4), copy markers, Finder `(n)` counters, Dropbox/OneDrive conflicted copies, ISO and US dates, a ranked status-word vocabulary (signed=5 > approved=4 > final=3 > … > old/backup=-3), bare years (kept separate from real dates). **Key bug fixed during implementation:** regex `\b` treats `_` as a word character, so `Policy_FINAL_v2` silently matched nothing until separators were pre-normalized to spaces.
  - `ClusterRanker`: deterministic priority — non-conflicted > non-derivative > explicit version > date > status > loose counter > mtime — with confidence scoring that *penalizes* contradictions (e.g., v1 has a newer mtime than v2) rather than hiding them, caps confidence when only bare years or only mtime differ (prevents "Chapter 1"/"Chapter 2" or "invoice 2024"/"invoice 2025" from being treated as versions), and penalizes wild size divergence.
  - `VersionChainDetector`: clusters by (directory, extension, normalized stem); reports only ≥0.5 confidence. **The 0.4–0.85 band is deliberately reserved for Foundation Models judging in Phase 5** — it isn't dropped, just not yet routed anywhere.
  - `ContentDuplicateDetector`: collapses byte-identical cluster members down to one best-ranked representative so exact and content duplicate findings never overlap/double-report.
  - CLI (`auditor-cli scan <folder>`) now runs all three duplicate detectors together with bounded-concurrency fingerprinting (OCR opt-out by default in bulk scans — OCR is expensive, so `extract` is the tool for single-file OCR debugging).

**Not yet implemented** (schema/types exist as placeholders only): `AuditorAI` real Foundation Models integration, `AuditorStore` actual read/write usage by the engine, `AuditorApply` engine logic, `AuditorEngine` real pipeline wiring, the entire app UI beyond a placeholder screen, licensing/Sparkle/release scripting.

## Next up: Phase 5 — Foundation Models judge

Per the plan: `@Generable VersionChainJudgment { canonicalIndex, stalenessRanking, confidence, rationale }`, fed only filenames + metadata (never file content) for clusters in the 0.4–0.85 ambiguous confidence band that `VersionChainDetector` currently reports at ≥0.5 only. Needs: availability gating (`SystemLanguageModel.default.availability`, checked per-scan not per-launch), permutation validation of the model's output, and graceful fallback to the existing `ClusterRanker` rules on any guardrail/unavailability/malformed-output case — the product must stay fully useful with Apple Intelligence off. `MockJudge` for unit tests; one availability-gated smoke test only.

After Phase 5, the remaining phases (see the plan file for full detail) are: 6 policy engine + filename lint + AI rename + misfiled detector, 7 expirations, 8 app shell, 9 apply/undo engine, 10 reports, 11 trial/licensing, 12 Sparkle + release pipeline scripting, 13 website/hardening.

## Useful commands

```sh
cd Packages/AuditorCore && swift test                 # 48 tests, ~0.3s
swift build --product auditor-cli
.build/debug/auditor-cli scan <folder>                 # duplicates + content dups + version chains
.build/debug/auditor-cli scan <folder> --json           # machine-readable
.build/debug/auditor-cli extract <file>                 # debug single-file text/metadata extraction
cd /Users/kadeem/Dev/mac_file_auditor
make generate && make build                              # regenerate Xcode project + Debug build
```

## Working style notes for whoever picks this up

- Every phase so far: real implementation + real tests (generated fixtures, not mocks, wherever feasible) + a working CLI demonstration against either a synthetic scenario matching the brief's examples or a real file from the user's Mac + a git commit with a detailed message + a push to `origin/main`. Keep that pattern.
- The user (Kadeem) approves plans via the plan-mode workflow before implementation starts; within an approved phase, proceed autonomously through implement → test → verify → commit → push without re-asking, and give a concise end-of-phase summary.
- Long-lived context about this project also lives in Claude's memory system (`project_folderlint` entry) — that's a shorter pointer/summary; this file is the detailed one.
