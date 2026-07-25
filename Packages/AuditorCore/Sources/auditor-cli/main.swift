import AuditorCrawl
import AuditorModels
import Foundation

// Headless scanner for dogfooding and CI. Runs unsandboxed from the terminal.
// Phase 1: dry-run crawl statistics. Phase 2 adds duplicate findings + JSON output.

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
        auditor-cli 0.1.0 — FolderLint engine

        usage: auditor-cli scan <folder> [options]

        options:
          --dry-run          crawl and report statistics without any analysis (default)
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

let root = URL(fileURLWithPath: rootPath)
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

if asJSON {
    struct DryRunReport: Codable {
        let root: String
        let files: Int
        let totalBytes: Int64
        let cloudPlaceholders: Int
        let topExtensions: [String: Int]
        let seconds: Double
    }
    let report = DryRunReport(
        root: root.path,
        files: fileCount,
        totalBytes: totalBytes,
        cloudPlaceholders: datalessCount,
        topExtensions: Dictionary(uniqueKeysWithValues: topExtensions.map { ($0.key, $0.value) }),
        seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try! encoder.encode(report), encoding: .utf8)!)
} else {
    let formatter = ByteCountFormatter()
    print("FolderLint dry run — \(root.path)")
    print("  files:              \(fileCount)")
    print("  total size:         \(formatter.string(fromByteCount: totalBytes))")
    print("  cloud placeholders: \(datalessCount)")
    print("  elapsed:            \(elapsed)")
    print("  top extensions:")
    for (ext, count) in topExtensions {
        print("    \(ext.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)")
    }
}
