import AuditorCrawl
import AuditorDetect
import AuditorEngine
import AuditorExtract
import AuditorModels
import AuditorPolicy
import Foundation

// Headless scanner for dogfooding and CI. Runs unsandboxed from the terminal.
// The real pipeline lives in AuditorEngine; this is a thin CLI front-end.

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
        auditor-cli 0.3.0 — FolderLint engine

        usage:
          auditor-cli scan <folder> [options]     audit a folder
          auditor-cli extract <file>              debug text/metadata extraction

        scan options:
          --dry-run          crawl statistics only, no analysis
          --duplicates       detect exact duplicate sets (default)
          --include-hidden   include hidden files
          --local-only       skip cloud placeholders entirely (default: metadata-only)
          --policy <id>      active bundled policy: nonprofit or small-business
          --no-content       skip extraction, content duplicates, embeddings, AI rename, and expirations
          --json             machine-readable output
        """)
    exit(2)
}

if arguments.first == "extract", arguments.count >= 2 {
    let url = URL(fileURLWithPath: arguments[1])
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let record = FileRecord(
        path: url.path,
        size: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
        mtimeNanoseconds: 1
    )

    let extractor = DefaultTextExtractor()
    guard extractor.canExtract(from: record) else {
        FileHandle.standardError.write(Data("unsupported file type: \(record.filename)\n".utf8))
        exit(1)
    }

    do {
        let result = try await extractor.extractText(from: record)
        print("file:     \(record.filename)")
        print("method:   \(result.usedOCR ? "Vision OCR" : "text layer / direct")")
        if let metadata = MetadataReader().read(from: record) {
            print("title:    \(metadata.title ?? "—")")
            print("author:   \(metadata.author ?? "—")")
            print("keywords: \(metadata.keywords.isEmpty ? "—" : metadata.keywords.joined(separator: ", "))")
        }
        print("chars:    \(result.text.count)")
        print("--- first 600 characters ---")
        print(String(result.text.prefix(600)))
    } catch {
        FileHandle.standardError.write(Data("extraction failed: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

guard arguments.first == "scan", arguments.count >= 2 else { usage() }

let rootPath = arguments[1]
let asJSON = arguments.contains("--json")
let dryRunOnly = arguments.contains("--dry-run")
let policyID: String?
if let policyFlag = arguments.firstIndex(of: "--policy") {
    guard arguments.indices.contains(policyFlag + 1) else { usage() }
    policyID = arguments[policyFlag + 1]
} else {
    policyID = nil
}

var rules = SkipRules()
if arguments.contains("--include-hidden") { rules.skipHidden = false }
if arguments.contains("--local-only") { rules.cloudMode = .localOnly }

let root = URL(fileURLWithPath: rootPath)
let activePolicy: Policy?
if let policyID {
    do {
        activePolicy = try PolicyLoader().loadBundledPolicy(id: policyID)
    } catch {
        FileHandle.standardError.write(Data("unable to load policy “\(policyID)”: \(error)\n".utf8))
        exit(1)
    }
} else {
    activePolicy = nil
}

if dryRunOnly {
    let clock = ContinuousClock()
    let start = clock.now
    var fileCount = 0
    var totalBytes: Int64 = 0
    var datalessCount = 0
    var byExtension: [String: Int] = [:]

    do {
        for try await batch in FileCrawler().crawl(roots: [root], rules: rules) {
            for record in batch {
                fileCount += 1
                totalBytes += record.size
                if record.isDatalessCloudItem { datalessCount += 1 }
                let ext = (record.filename as NSString).pathExtension.lowercased()
                byExtension[ext.isEmpty ? "(none)" : ext, default: 0] += 1
            }
        }
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }

    let elapsed = start.duration(to: clock.now)
    let topExtensions = byExtension.sorted { $0.value > $1.value }.prefix(10)
    emitReport(
        root: root.path,
        files: fileCount,
        totalBytes: totalBytes,
        cloudPlaceholders: datalessCount,
        topExtensions: Dictionary(uniqueKeysWithValues: topExtensions.map { ($0.key, $0.value) }),
        policy: activePolicy?.id,
        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
        findings: nil,
        asJSON: asJSON,
        policyDisplayName: activePolicy?.displayName
    )
    exit(0)
}

let detectors: [any Detector]
if arguments.contains("--no-content") {
    detectors = [DuplicateDetector(), FilenamePolicyDetector()]
} else {
    detectors = ScanPipeline.defaultDetectors
}

do {
    let engine = try AuditorEngine.makeEphemeral(detectors: detectors)
    let handle = await engine.startScan(ScanConfiguration(
        rootPaths: [root.path],
        skipRules: rules,
        policyID: policyID
    ))

    var findings: [Finding] = []
    var summary: ScanSummary?
    var filesSeen = 0

    for await event in handle.events {
        switch event {
        case .phaseChanged:
            break
        case .progress(let progress):
            filesSeen = progress.filesSeen
        case .finding(let finding):
            findings.append(finding)
        case .completed(let completed):
            summary = completed
        case .failed(let error):
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    findings.sort { ($0.severity, $0.confidence) > ($1.severity, $1.confidence) }
    emitReport(
        root: root.path,
        files: summary?.filesScanned ?? filesSeen,
        totalBytes: summary?.totalBytes ?? 0,
        cloudPlaceholders: summary?.cloudPlaceholders ?? 0,
        topExtensions: [:],
        policy: activePolicy?.id,
        seconds: summary?.duration ?? 0,
        findings: findings,
        asJSON: asJSON,
        policyDisplayName: activePolicy?.displayName
    )
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

func emitReport(
    root: String,
    files: Int,
    totalBytes: Int64,
    cloudPlaceholders: Int,
    topExtensions: [String: Int],
    policy: String?,
    seconds: Double,
    findings: [Finding]?,
    asJSON: Bool,
    policyDisplayName: String?
) {
    if asJSON {
        struct Report: Codable {
            let root: String
            let files: Int
            let totalBytes: Int64
            let cloudPlaceholders: Int
            let topExtensions: [String: Int]
            let policy: String?
            let seconds: Double
            let findings: [Finding]?
        }
        let report = Report(
            root: root,
            files: files,
            totalBytes: totalBytes,
            cloudPlaceholders: cloudPlaceholders,
            topExtensions: topExtensions,
            policy: policy,
            seconds: seconds,
            findings: findings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(data: try! encoder.encode(report), encoding: .utf8)!)
        return
    }

    let formatter = ByteCountFormatter()
    print("FolderLint scan — \(root)")
    print("  files:              \(files)")
    print("  total size:         \(formatter.string(fromByteCount: totalBytes))")
    print("  cloud placeholders: \(cloudPlaceholders)")
    print("  policy:             \(policyDisplayName ?? "universal rules only")")
    print("  elapsed:            \(String(format: "%.3fs", seconds))")
    if !topExtensions.isEmpty {
        print("  top extensions:")
        for (ext, count) in topExtensions.sorted(by: { $0.value > $1.value }).prefix(10) {
            print("    \(ext.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)")
        }
    }

    guard let findings else { return }
    let totalWasted = findings.reduce(Int64(0)) { total, finding in
        switch finding.evidence {
        case .duplicateSet(_, let wasted), .contentDuplicateSet(_, let wasted):
            return total + wasted
        default:
            return total
        }
    }
    print("")
    print("findings: \(findings.count) (\(formatter.string(fromByteCount: totalWasted)) reclaimable)")
    for finding in findings {
        print("")
        print("  [\(finding.severity)] (\(finding.kind)) \(finding.explanation)")
        for file in finding.files {
            print("    - \(file.path)")
        }
    }
}
