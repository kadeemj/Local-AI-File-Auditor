import AuditorCrawl
import AuditorDetect
import AuditorExtract
import AuditorHashing
import AuditorModels
import Foundation

// Headless scanner for dogfooding and CI. Runs unsandboxed from the terminal.

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
        auditor-cli 0.1.0 — FolderLint engine

        usage:
          auditor-cli scan <folder> [options]     audit a folder
          auditor-cli extract <file>              debug text/metadata extraction

        scan options:
          --dry-run          crawl statistics only, no analysis
          --duplicates       detect exact duplicate sets (default)
          --include-hidden   include hidden files
          --local-only       skip cloud placeholders entirely (default: metadata-only)
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

        // Content fingerprints for text-extractable files (OCR is opt-in via
        // `extract`, not paid on every bulk scan).
        var fingerprints: [String: TextFingerprint] = [:]
        if !arguments.contains("--no-content") {
            let extractor = DefaultTextExtractor(enableOCRFallback: false)
            let maxContentBytes: Int64 = 20 << 20
            let candidates = records.filter { extractor.canExtract(from: $0) && $0.size <= maxContentBytes }

            fingerprints = await withTaskGroup(of: (String, TextFingerprint)?.self) { group in
                var iterator = candidates.makeIterator()
                var inFlight = 0
                var collected: [String: TextFingerprint] = [:]
                func addNext() {
                    guard let record = iterator.next() else { return }
                    inFlight += 1
                    group.addTask {
                        guard let extracted = try? await extractor.extractText(from: record),
                              let fingerprint = TextFingerprint.compute(from: extracted.text)
                        else { return nil }
                        return (record.path, fingerprint)
                    }
                }
                for _ in 0..<4 { addNext() }
                while inFlight > 0, let result = await group.next() {
                    inFlight -= 1
                    if let (path, fingerprint) = result { collected[path] = fingerprint }
                    addNext()
                }
                return collected
            }
        }

        let context = DetectionContext(
            scanID: UUID(),
            files: records,
            duplicateGroups: groups,
            textFingerprints: fingerprints.isEmpty ? nil : fingerprints
        )

        findings = try await DuplicateDetector().detect(context: context)
        findings += try await ContentDuplicateDetector().detect(context: context)
        findings += try await VersionChainDetector().detect(context: context)
        findings.sort { ($0.severity, $0.confidence) > ($1.severity, $1.confidence) }
    } catch {
        FileHandle.standardError.write(Data("error during analysis: \(error)\n".utf8))
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
}
