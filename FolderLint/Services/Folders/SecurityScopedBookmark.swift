import Foundation

/// Creates and resolves app-scoped security-scoped bookmarks.
/// Separated from `NSOpenPanel` so the encode/resolve path is unit-testable.
enum SecurityScopedBookmark {
    enum BookmarkError: Error, Equatable {
        case creationFailed
        case resolutionFailed
        case staleNeedsRegrant
    }

    struct Resolution: Equatable {
        let url: URL
        let isStale: Bool
    }

    static func create(from url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.creationFailed
        }
    }

    static func resolve(_ data: Data) throws -> Resolution {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return Resolution(url: url, isStale: isStale)
        } catch {
            throw BookmarkError.resolutionFailed
        }
    }
}
