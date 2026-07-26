# FolderLint Network Policy

FolderLint is a local-first document-governance auditor. **Your files, their
contents, and everything FolderLint learns about them never leave your Mac.**

This document is the complete list of network connections the app ever makes.
It is published verbatim on the website and enforced in the codebase.

## The only connections

| Purpose | Host | When | What is sent |
|---|---|---|---|
| License activation/validation | `api.lemonsqueezy.com` | When you enter a license key, then at most once per 24 hours | Your license key, an instance name (your Mac's name, e.g. "Kadeem's MacBook Pro"), and the activation instance ID |
| Update check (Sparkle) | `folderlint.com` (appcast + update archives) | On your schedule, after you consent to automatic checks | A GET request for `https://folderlint.com/appcast.xml`; the app version is part of the standard user agent. System profiling is disabled (`SUEnableSystemProfiling=false`). |

That is the entire list. Specifically, FolderLint **never** transmits:

- File names, file contents, or folder structures
- Extracted text, hashes, fingerprints, or embeddings
- Findings, reports, or audit history
- Analytics, telemetry, or crash reports of any kind

## How this is enforced

1. All AI analysis runs on-device (Apple Foundation Models, Natural Language,
   and Vision frameworks). There is no cloud AI fallback — if on-device AI is
   unavailable, FolderLint degrades to deterministic rules.
2. The app is **sandboxed**: macOS itself prevents FolderLint from reading any
   folder you did not explicitly select.
3. A single source file (`FolderLint/Services/Network/NetworkClient.swift`)
   contains the app's only networking code, with a hardcoded host allowlist.
   A build-phase script (`Scripts/check_network_policy.sh`) fails the build if
   networking APIs appear anywhere else.
4. App Transport Security is fully strict — no arbitrary-loads exceptions.

## Verify it yourself

- Run [Little Snitch](https://www.obdev.at/products/littlesnitch/) or any
  outbound firewall during a full scan-and-review session: you will see at most
  the two hosts above.
- Stream the app's own logs:
  `log stream --predicate 'process == "FolderLint"'`
- Offline use: everything except license validation and updates works with no
  network at all. Licensed copies keep working offline for 30 days between
  validations.
