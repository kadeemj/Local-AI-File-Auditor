// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AuditorCore",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "AuditorEngine", targets: ["AuditorEngine"]),
        .library(name: "AuditorModels", targets: ["AuditorModels"]),
        .executable(name: "auditor-cli", targets: ["auditor-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        // Pure Sendable value types; no dependencies.
        .target(name: "AuditorModels"),

        // Traversal, skip rules, security-scope handling.
        .target(name: "AuditorCrawl", dependencies: ["AuditorModels"]),

        // Staged content hashing + text fingerprints.
        .target(name: "AuditorHashing", dependencies: ["AuditorModels"]),

        // Text + metadata extraction (PDFKit, Vision OCR, docx).
        .target(name: "AuditorExtract", dependencies: [
            "AuditorModels",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),

        // Policy model, naming template DSL, bundled templates.
        .target(
            name: "AuditorPolicy",
            dependencies: ["AuditorModels"],
            resources: [.copy("Templates")]
        ),

        // Foundation Models / NLEmbedding wrappers; the only target importing FoundationModels.
        .target(name: "AuditorAI", dependencies: ["AuditorModels"]),

        // Detector protocol + the five v1 detectors.
        .target(name: "AuditorDetect", dependencies: [
            "AuditorModels", "AuditorHashing", "AuditorExtract", "AuditorPolicy", "AuditorAI",
        ]),

        // GRDB persistence: scan cache, findings, folder profiles, apply journal.
        .target(name: "AuditorStore", dependencies: [
            "AuditorModels",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),

        // Apply engine: plan → preview → restore point → apply → undo.
        .target(name: "AuditorApply", dependencies: ["AuditorModels", "AuditorStore"]),

        // Orchestration: AuditorEngine actor, ScanIndex, ScanHandle.
        .target(name: "AuditorEngine", dependencies: [
            "AuditorModels", "AuditorCrawl", "AuditorHashing", "AuditorExtract",
            "AuditorPolicy", "AuditorDetect", "AuditorAI", "AuditorStore", "AuditorApply",
        ]),

        // Headless scanner for dogfooding and CI. Runs unsandboxed from the terminal.
        .executableTarget(name: "auditor-cli", dependencies: ["AuditorEngine"]),

        // Shared test helpers (FixtureBuilder). Not in `products`; test-only by convention.
        .target(name: "AuditorTestSupport", dependencies: ["AuditorModels"]),

        .testTarget(name: "AuditorModelsTests", dependencies: ["AuditorModels"]),
        .testTarget(name: "AuditorAITests", dependencies: ["AuditorAI"]),
        .testTarget(name: "AuditorCrawlTests", dependencies: ["AuditorCrawl", "AuditorTestSupport"]),
        .testTarget(name: "AuditorHashingTests", dependencies: ["AuditorHashing", "AuditorTestSupport"]),
        .testTarget(name: "AuditorExtractTests", dependencies: [
            "AuditorExtract", "AuditorTestSupport",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        .testTarget(name: "AuditorDetectTests", dependencies: ["AuditorDetect", "AuditorHashing", "AuditorTestSupport"]),
        .testTarget(name: "AuditorStoreTests", dependencies: ["AuditorStore"]),
        .testTarget(name: "AuditorPolicyTests", dependencies: ["AuditorPolicy"]),
    ],
    swiftLanguageModes: [.v6]
)
