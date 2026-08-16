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
        XCTAssertTrue(summary.contains("50% of input"))
    }

    func testOutputSummaryKeepsPrecisionForSmallRelativeSize() {
        let summary = FileSizeFormatterUtil.outputSummary(outputBytes: 67, sourceBytes: 1_000)
        XCTAssertTrue(summary.contains("6.7% of input"))
    }
}
