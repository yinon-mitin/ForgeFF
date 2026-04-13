import XCTest
@testable import ForgeFF

final class FileSizeFormatterUtilTests: XCTestCase {
    func testFormatsReadableSize() {
        let rendered = FileSizeFormatterUtil.string(from: 1_048_576)
        XCTAssertFalse(rendered.isEmpty)
        XCTAssertNotEqual(rendered, "—")
    }

    func testOutputSummaryUsesOutputPrefix() {
        let summary = FileSizeFormatterUtil.outputSummary(outputBytes: 1_048_576, sourceBytes: 2_097_152)
        XCTAssertTrue(summary.hasPrefix("Output: "))
        XCTAssertTrue(summary.contains("("))
    }
}
