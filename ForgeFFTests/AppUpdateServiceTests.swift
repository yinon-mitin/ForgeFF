import XCTest
@testable import ForgeFF

final class AppUpdateServiceTests: XCTestCase {
    func testVersionComparisonRecognizesNewerRelease() {
        XCTAssertTrue(AppUpdateService.isNewerVersion("2.7.0", than: "2.6.7"))
        XCTAssertTrue(AppUpdateService.isNewerVersion("3.0", than: "2.99.9"))
        XCTAssertFalse(AppUpdateService.isNewerVersion("2.6.7", than: "2.6.7"))
        XCTAssertFalse(AppUpdateService.isNewerVersion("2.6.6", than: "2.6.7"))
    }

    func testVersionComparisonIgnoresLeadingVAndBuildSuffix() {
        XCTAssertTrue(AppUpdateService.isNewerVersion("v2.7.0", than: "2.6.7"))
        XCTAssertFalse(AppUpdateService.isNewerVersion("v2.6.7", than: "2.6.7+267"))
    }

    func testExpectedReleaseAssetNamesAreDerivedFromVersion() {
        XCTAssertEqual(
            AppUpdateService.expectedAssetNames(for: "v2.7.0"),
            ["ForgeFF-2.7.0-macOS.zip", "ForgeFF-2.7.0-macOS.zip.sha256"]
        )
    }

    func testChecksumParserAcceptsStandardSha256sumOutput() throws {
        let checksum = try XCTUnwrap(
            AppUpdateService.parseChecksum(
                "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  ForgeFF-2.7.0-macOS.zip\n"
            )
        )
        XCTAssertEqual(checksum, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
    }

    func testChecksumParserRejectsMalformedOrMismatchedOutput() {
        XCTAssertNil(AppUpdateService.parseChecksum("not-a-checksum  ForgeFF.zip"))
        XCTAssertNil(AppUpdateService.parseChecksum("0123456789abcdef  Other.zip"))
    }
}
