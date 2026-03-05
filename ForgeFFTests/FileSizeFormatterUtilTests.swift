import XCTest
@testable import ForgeFF

final class FileSizeFormatterUtilTests: XCTestCase {
    func testFormatsReadableSize() {
        let rendered = FileSizeFormatterUtil.string(from: 1_048_576)
        XCTAssertFalse(rendered.isEmpty)
        XCTAssertNotEqual(rendered, "—")
    }
}
