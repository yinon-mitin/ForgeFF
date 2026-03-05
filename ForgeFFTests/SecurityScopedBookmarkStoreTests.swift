import XCTest
@testable import ForgeFF

final class SecurityScopedBookmarkStoreTests: XCTestCase {
    func testStoreResolveAndRemoveBookmark() {
        let expectedURL = URL(fileURLWithPath: "/tmp/example.mov")
        let store = SecurityScopedBookmarkStore(
            makeBookmark: { _ in Data([1, 2, 3]) },
            resolveBookmark: { data in
                data == Data([1, 2, 3]) ? expectedURL : nil
            }
        )

        let jobID = UUID()
        store.store(url: expectedURL, for: jobID)
        XCTAssertEqual(store.resolvedURL(for: jobID), expectedURL)

        store.remove(jobIDs: [jobID])
        XCTAssertNil(store.resolvedURL(for: jobID))
    }
}
