import Foundation

/// Builds throwaway directory trees for tests. Trees are generated (not checked in)
/// because git does not preserve mtimes, and version-chain heuristics depend on them.
public struct FixtureBuilder {
    public struct Spec {
        let relativePath: String
        let content: Data
        let mtime: Date?
    }

    private var specs: [Spec] = []
    private var emptyDirs: [String] = []

    public init() {}

    /// Adds a file with explicit content (for duplicate/content tests).
    public func file(_ relativePath: String, content: Data, mtime: Date? = nil) -> FixtureBuilder {
        var copy = self
        copy.specs.append(Spec(relativePath: relativePath, content: content, mtime: mtime))
        return copy
    }

    /// Adds a file of a given size filled with a repeating byte derived from the path,
    /// so different paths get different content by default.
    public func file(_ relativePath: String, size: Int = 16, mtime: Date? = nil) -> FixtureBuilder {
        let byte = UInt8(truncatingIfNeeded: relativePath.utf8.reduce(7) { $0 &* 31 &+ Int($1) })
        return file(relativePath, content: Data(repeating: byte, count: size), mtime: mtime)
    }

    public func directory(_ relativePath: String) -> FixtureBuilder {
        var copy = self
        copy.emptyDirs.append(relativePath)
        return copy
    }

    /// Materializes the tree under a fresh temp directory and returns its root.
    /// Callers remove it in teardown (or let the OS reap the temp dir).
    public func build() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for dir in emptyDirs {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(dir, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        for spec in specs {
            let url = root.appendingPathComponent(spec.relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try spec.content.write(to: url)
            if let mtime = spec.mtime {
                try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
            }
        }

        return root
    }
}

extension Date {
    /// `.daysAgo(30)` — readable relative mtimes in fixtures.
    public static func daysAgo(_ days: Int) -> Date {
        Date(timeIntervalSinceNow: -Double(days) * 86_400)
    }
}
