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
        XCTAssertEqual(FilenameRenamer.sanitize("my:file?/name"), "my_file_name")
    }

    func testSanitizeReplacesWhitespaceSequencesWithUnderscore() {
        XCTAssertEqual(FilenameRenamer.sanitize("my   file\tname"), "my_file_name")
    }

    func testSanitizeKeepsWhitespaceAsUnderscoreInsteadOfDroppingIt() {
        XCTAssertEqual(FilenameRenamer.sanitize("a b"), "a_b")
        XCTAssertEqual(FilenameRenamer.sanitize("  a   b  "), "_a_b_")
    }

    func testNormalizeInputFieldRemovesPathCharactersAndControls() {
        let result = FilenameRenamer.normalizeInputField(
            "  ../bad:/\\name\t",
            sanitize: false,
            fieldKind: .filenameComponent
        )
        XCTAssertEqual(result, "badname")
    }

    func testReplaceFieldKeepsSpacesWhenSanitizeOn() {
        let result = FilenameRenamer.normalizeInputField(
            "Season 01",
            sanitize: true,
            fieldKind: .searchPattern
        )
        XCTAssertEqual(result, "Season 01")
    }

    func testPrefixUsesUnderscoreWhenSanitizeOn() {
        let result = FilenameRenamer.normalizeInputField(
            "Season 01",
            sanitize: true,
            fieldKind: .filenameComponent
        )
        XCTAssertEqual(result, "Season_01")
    }

    func testApplyFallsBackToOriginalWhenResultBecomesEmpty() {
        let configuration = BatchRenameConfiguration(
            replaceText: "clip",
            replaceWith: "",
            prefix: "",
            suffix: "",
            sanitizeFilename: false
        )

        let result = FilenameRenamer.apply(to: "clip", configuration: configuration, originalFallback: "clip")
        XCTAssertEqual(result, "clip")
    }
}
