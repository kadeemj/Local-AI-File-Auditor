# FolderLint

**A private document-governance auditor for Mac.** Grammarly for your files and
folders: FolderLint reviews the folders you already have — local, Box/Drive/
Dropbox-synced, or on external drives — and finds organizational, privacy, and
document-quality problems before they become operational or compliance problems.

- **Audit-only by default.** Every recommendation comes with evidence and an
  explanation. Changes happen only through an approve → preview → restore-point
  → apply → undo workflow. FolderLint never deletes files.
- **100% local analysis.** On-device AI (Apple Foundation Models, Natural
  Language, Vision). The only network calls are license validation and update
  checks — see [docs/NETWORK_POLICY.md](docs/NETWORK_POLICY.md).
- **Sandboxed by choice.** macOS enforces that FolderLint can only read folders
  you explicitly select, even though the app is distributed outside the App Store.

## What it detects (v1)

1. Duplicates — exact (hash), content-level (same text, different file), and
   version families (`Policy_FINAL_v2_NEW.pdf`)
2. Filename policy violations, with side-by-side AI rename suggestions
3. Misfiled documents, with recommended destinations and evidence
4. Expiring documents — contracts, insurance certificates, licenses — with the
   date's *meaning* understood, not just matched

## Repository layout

| Path | Purpose |
|---|---|
| `Packages/AuditorCore/` | The scanning engine (SPM package, headlessly testable) |
| `FolderLint/` | SwiftUI app target |
| `Config/` | xcconfig build settings |
| `Scripts/` | Build gates + release pipeline |
| `project.yml` | XcodeGen source of truth for the Xcode project |
| `docs/NETWORK_POLICY.md` | The complete, auditable list of network connections |

## Development

Requirements: Xcode 26+, macOS 26+, `brew install xcodegen`.

```sh
make test       # engine test suite (Swift Testing)
make test-app   # app unit tests (bookmarks + ScanSessionModel)
make generate   # regenerate FolderLint.xcodeproj from project.yml
make build      # Debug build of the app
```

The implementation plan and phase status live in the project plan document.
Phases 0–10 are implemented: onboarding, scan, approve/apply/undo, and
CSV/PDF audit reports. Licensing is Phase 11.
