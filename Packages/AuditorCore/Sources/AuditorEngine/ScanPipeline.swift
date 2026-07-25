import AuditorAI
import AuditorCrawl
import AuditorDetect
import AuditorExtract
import AuditorHashing
import AuditorModels
import AuditorPolicy
import Foundation

/// Shared crawl → hash → extract → detect pipeline used by `AuditorEngine`
/// and (thinly) by `auditor-cli`. Extracted text is transient and never persisted.
public enum ScanPipeline {
    public static let defaultDetectors: [any Detector] = [
        DuplicateDetector(),
        ContentDuplicateDetector(),
        VersionChainDetector(),
        FilenamePolicyDetector(),
        RenameSuggester(),
        MisfiledDetector(),
        ExpirationDetector(),
    ]

    static func run(
        config: ScanConfiguration,
        scanID: UUID,
        detectors: [any Detector],
        yield: (ScanEvent) -> Void,
        isCancelled: () -> Bool
    ) async {
        let start = ContinuousClock.now
        yield(.phaseChanged(.enumerating))

        let roots = config.rootPaths.map { URL(fileURLWithPath: $0) }
        var records: [FileRecord] = []
        var filesSeen = 0
        var progress = ScanProgress(filesSeen: 0, bytesHashed: 0, currentPhase: .enumerating)

        do {
            for try await batch in FileCrawler().crawl(roots: roots, rules: config.skipRules) {
                if isCancelled() {
                    yield(.failed(.cancelled))
                    return
                }
                records.append(contentsOf: batch)
                filesSeen += batch.count
                progress.filesSeen = filesSeen
                yield(.progress(progress))
            }
        } catch is CancellationError {
            yield(.failed(.cancelled))
            return
        } catch {
            let path = config.rootPaths.first ?? ""
            yield(.failed(.rootUnreadable(path: path)))
            return
        }

        if isCancelled() {
            yield(.failed(.cancelled))
            return
        }

        let activePolicy: Policy?
        if let policyID = config.policyID {
            do {
                activePolicy = try PolicyLoader().loadBundledPolicy(id: policyID)
            } catch {
                yield(.failed(.storageFailure(message: "unable to load policy “\(policyID)”: \(error)")))
                return
            }
        } else {
            activePolicy = nil
        }

        let needed = detectors.reduce(into: DetectorSignals()) { $0.formUnion($1.requiredSignals) }

        var duplicateGroups: [DuplicateGroup]?
        if needed.contains(.hashes) {
            yield(.phaseChanged(.hashing))
            progress.currentPhase = .hashing
            yield(.progress(progress))
            do {
                let groups = try await StagedHashPipeline().duplicateGroups(in: records, rules: config.skipRules)
                duplicateGroups = groups
                progress.bytesHashed = records.reduce(0) { $0 + $1.size }
                yield(.progress(progress))
            } catch is CancellationError {
                yield(.failed(.cancelled))
                return
            } catch {
                yield(.failed(.storageFailure(message: "hashing failed: \(error)")))
                return
            }
        }

        if isCancelled() {
            yield(.failed(.cancelled))
            return
        }

        var fingerprints: [String: TextFingerprint] = [:]
        var extractedTexts: [String: String] = [:]
        var documentEmbeddings: [String: [Double]] = [:]
        var folderLabelEmbeddings: [String: [Double]] = [:]

        if needed.contains(.textContent) || needed.contains(.embeddings) || needed.contains(.semanticJudge) {
            yield(.phaseChanged(.extracting))
            progress.currentPhase = .extracting
            yield(.progress(progress))

            let extractor = DefaultTextExtractor(enableOCRFallback: false)
            let maxContentBytes: Int64 = 20 << 20
            let candidates = records.filter { extractor.canExtract(from: $0) && $0.size <= maxContentBytes }

            let extracted = await withTaskGroup(of: (String, String, TextFingerprint?)?.self) { group in
                var iterator = candidates.makeIterator()
                var inFlight = 0
                var collected: [(String, String, TextFingerprint?)] = []

                func addNext() {
                    guard let record = iterator.next() else { return }
                    inFlight += 1
                    group.addTask {
                        guard let extracted = try? await extractor.extractText(from: record),
                              !extracted.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { return nil }
                        return (
                            record.path,
                            String(extracted.text.prefix(250_000)),
                            TextFingerprint.compute(from: extracted.text)
                        )
                    }
                }

                for _ in 0..<4 { addNext() }
                while inFlight > 0, let result = await group.next() {
                    if isCancelled() {
                        group.cancelAll()
                        break
                    }
                    inFlight -= 1
                    if let result { collected.append(result) }
                    addNext()
                }
                return collected
            }

            if isCancelled() {
                yield(.failed(.cancelled))
                return
            }

            for (path, text, fingerprint) in extracted {
                extractedTexts[path] = text
                if let fingerprint { fingerprints[path] = fingerprint }
            }

            if needed.contains(.embeddings) {
                let embeddingProvider = SentenceEmbeddingProvider()
                documentEmbeddings = extractedTexts.compactMapValues { embeddingProvider.vector(for: $0) }
                let directories = Set(records.map { ($0.path as NSString).deletingLastPathComponent })
                folderLabelEmbeddings = Dictionary(uniqueKeysWithValues: directories.compactMap { directory in
                    let components = URL(fileURLWithPath: directory).pathComponents.suffix(3)
                    let label = components.joined(separator: " / ")
                    return embeddingProvider.vector(for: label).map { (directory, $0) }
                })
            }
        }

        if isCancelled() {
            yield(.failed(.cancelled))
            return
        }

        yield(.phaseChanged(.detecting))
        progress.currentPhase = .detecting
        yield(.progress(progress))

        let context = DetectionContext(
            scanID: scanID,
            files: records,
            duplicateGroups: duplicateGroups,
            textFingerprints: fingerprints.isEmpty ? nil : fingerprints,
            extractedText: extractedTexts.isEmpty ? nil : extractedTexts,
            documentEmbeddings: documentEmbeddings.isEmpty ? nil : documentEmbeddings,
            folderLabelEmbeddings: folderLabelEmbeddings.isEmpty ? nil : folderLabelEmbeddings,
            policy: activePolicy
        )

        var findings: [Finding] = []
        do {
            for detector in detectors {
                if isCancelled() {
                    yield(.failed(.cancelled))
                    return
                }
                if detector.requiredSignals.contains(.semanticJudge) {
                    yield(.phaseChanged(.judging))
                    progress.currentPhase = .judging
                    yield(.progress(progress))
                }
                let detected = try await detector.detect(context: context)
                for finding in detected {
                    findings.append(finding)
                    yield(.finding(finding))
                }
            }
        } catch is CancellationError {
            yield(.failed(.cancelled))
            return
        } catch {
            yield(.failed(.storageFailure(message: "detection failed: \(error)")))
            return
        }

        findings.sort { ($0.severity, $0.confidence) > ($1.severity, $1.confidence) }
        let elapsed = start.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let totalBytes = records.reduce(Int64(0)) { $0 + $1.size }
        let cloudPlaceholders = records.reduce(0) { $0 + ($1.isDatalessCloudItem ? 1 : 0) }
        yield(.completed(ScanSummary(
            scanID: scanID,
            filesScanned: records.count,
            totalBytes: totalBytes,
            cloudPlaceholders: cloudPlaceholders,
            findingsCount: findings.count,
            duration: seconds
        )))
    }
}
