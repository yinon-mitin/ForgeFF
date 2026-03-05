import XCTest
@testable import ForgeFF

final class FilenameRenamerTests: XCTestCase {
    func testBatchRenameAppliesReplacePrefixSuffix() {
        let configuration = BatchRenameConfiguration(
            replaceText: "clip",
            replaceWith: "scene",
            prefix: "final_",
            suffix: "_v2",
            sanitizeFilename: true
        )

        let result = FilenameRenamer.apply(to: "clip take 01", configuration: configuration)

        XCTAssertEqual(result, "final_scene_take_01_v2")
    }

    func testSanitizeReplacesFilesystemUnsafeCharacters() {
        XCTAssertEqual(FilenameRenamer.sanitize("my:file?/name"), "my_file__name")
    }
}
