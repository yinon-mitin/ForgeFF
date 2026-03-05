import Foundation

final class SecurityScopedBookmarkStore {
    typealias BookmarkMaker = (URL) -> Data?
    typealias BookmarkResolver = (Data) -> URL?

    private var bookmarks: [UUID: Data] = [:]
    private let makeBookmark: BookmarkMaker
    private let resolveBookmark: BookmarkResolver

    init(
        makeBookmark: @escaping BookmarkMaker = { url in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolveBookmark: @escaping BookmarkResolver = { data in
            var isStale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )
        }
    ) {
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
    }

    func store(url: URL, for jobID: UUID) {
        bookmarks[jobID] = makeBookmark(url)
    }

    func resolvedURL(for jobID: UUID) -> URL? {
        guard let bookmark = bookmarks[jobID] else { return nil }
        return resolveBookmark(bookmark)
    }

    func remove(jobIDs: Set<UUID>) {
        for id in jobIDs {
            bookmarks.removeValue(forKey: id)
        }
    }
}
