import AuditorEngine
import AuditorModels
import Foundation

// Headless scanner for dogfooding and CI. Grows real subcommands in Phase 1
// (scan --dry-run, JSON/CSV output). Runs unsandboxed from the terminal.

let version = "0.1.0"
print("auditor-cli \(version) — FolderLint engine scaffold")
print("usage (Phase 1): auditor-cli scan <folder> [--dry-run] [--json]")
