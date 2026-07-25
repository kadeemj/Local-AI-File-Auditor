import AuditorCrawl
import AuditorDetect
import AuditorHashing
import AuditorModels
import Foundation

// Headless scanner for dogfooding and CI. Runs unsandboxed from the terminal.

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
        auditor-cli 0.1.0 — FolderLint engine

        usage: auditor-cli scan <folder> [options]

        options:
          --dry-run          crawl statistics only, no analysis
          --duplicates       detect exact duplicate sets (default)
          --include-hidden   include hidden files
          --local-only       skip cloud placeholders entirely (default: metadata-only)
          --json             machine-readable output
        """)
    exit(2)
}

guard arguments.first == "scan", arguments.count >= 2 else { usage() }

let rootPath = arguments[1]
let asJSON = arguments.contains("--json")
var rules = SkipRules()
if arguments.contains("--include-hidden") { rules.skipHidden = false }
if arguments.contains("--local-only") { rules.cloudMode = .localOnly }

let dryRunOnly = arguments.contains("--dry-run")

let root = URL(fileURLWithPath: rootPath)
let clock = ContinuousClock()
let start = clock.now

var fileCount = 0
var totalBytes: Int64 = 0
var datalessCount = 0
var byExtension: [String: Int] = [:]
var records: [FileRecord] = []

do {
    for try await batch in FileCrawler().crawl(roots: [root], rules: rules) {
        for record in batch {
            fileCount += 1
            totalBytes += record.size
            if record.isDatalessCloudItem { datalessCount += 1 }
            let ext = (record.filename as NSString).pathExtension.lowercased()
            byExtension[ext.isEmpty ? "(none)" : ext, default: 0] += 1
        }
        if !dryRunOnly { records.append(contentsOf: batch) }
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

var findings: [Finding] = []
if !dryRunOnly {
    do {
        let groups = try await StagedHashPipeline().duplicateGroups(in: records, rules: rules)
        let context = DetectionContext(scanID: UUID(), files: records, duplicateGroups: groups)
        findings = try await DuplicateDetector().detect(context: context)
            .sorted { $0.severity > $1.severity }
    } catch {
        FileHandle.standardError.write(Data("error during duplicate analysis: \(error)\n".utf8))
        exit(1)
    }
}

let elapsed = start.duration(to: clock.now)
let topExtensions = byExtension.sorted { $0.value > $1.value }.prefix(10)

if asJSON {
    struct Report: Codable {
        let root: String
        let files: Int
        let totalBytes: Int64
        let cloudPlaceholders: Int
        let topExtensions: [String: Int]
        let seconds: Double
        let findings: [Finding]?
    }
    let report = Report(
        root: root.path,
        files: fileCount,
        totalBytes: totalBytes,
        cloudPlaceholders: datalessCount,
        topExtensions: Dictionary(uniqueKeysWithValues: topExtensions.map { ($0.key, $0.value) }),
        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
        findings: dryRunOnly ? nil : findings
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    print(String(data: try! encoder.encode(report), encoding: .utf8)!)
} else {
    let formatter = ByteCountFormatter()
    print("FolderLint scan — \(root.path)")
    print("  files:              \(fileCount)")
    print("  total size:         \(formatter.string(fromByteCount: totalBytes))")
    print("  cloud placeholders: \(datalessCount)")
    print("  elapsed:            \(elapsed)")
    print("  top extensions:")
    for (ext, count) in topExtensions {
        print("    \(ext.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)")
    }

    if !dryRunOnly {
        let totalWasted = findings.reduce(Int64(0)) { total, finding in
            if case .duplicateSet(_, let wasted) = finding.evidence { return total + wasted }
            return total
        }
        print("")
        print("findings: \(findings.count) duplicate sets, \(formatter.string(fromByteCount: totalWasted)) reclaimable")
        for finding in findings {
            print("")
            print("  [\(finding.severity)] \(finding.explanation)")
            for file in finding.files {
                print("    - \(file.path)")
            }
        }
    }
}
