import AuditorModels
import Foundation

/// Shared "which copy should the user keep" heuristic (from the plan): prefer
/// the copy outside derivative locations, with the cleanest name, earliest
/// created as tiebreak. Lower ranks first.
enum KeeperRanking {
    static func rank(_ record: FileRecord) -> (Int, Int, TimeInterval) {
        let name = record.filename.lowercased()
        var penalty = 0

        if name.contains("copy") { penalty += 3 }
        if name.range(of: #"\(\d+\)"#, options: .regularExpression) != nil { penalty += 3 }
        for token in ["final", "draft", "old", "new", "backup", "bak"] where name.contains(token) {
            penalty += 1
        }
        if record.path.contains("/Downloads/") { penalty += 4 }

        return (penalty, record.filename.count, record.createdAt?.timeIntervalSince1970 ?? .infinity)
    }
}
