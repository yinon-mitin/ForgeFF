import XCTest
@testable import ForgeFF

final class WrappingPillsLayoutTests: XCTestCase {
    func testWrappedRowsWrapsWhenWidthIsSmall() {
        let rows = WrappingPillsLayoutHelper.wrappedRows(
            widths: [80, 80, 80],
            maxWidth: 170,
            spacing: 8
        )

        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    func testWrappedRowsStaysSingleRowWhenWidthFits() {
        let rows = WrappingPillsLayoutHelper.wrappedRows(
            widths: [80, 80, 80],
            maxWidth: 280,
            spacing: 8
        )

        XCTAssertEqual(rows, [[0, 1, 2]])
    }
}
