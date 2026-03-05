import XCTest
@testable import ForgeFF

final class ConversionOptionsTests: XCTestCase {
    func testResolutionOrderIncludes2KInExpectedPosition() {
        XCTAssertEqual(
            ConversionOptions.orderedResolutionChoices,
            [.preserve, .preset720p, .preset1080p, .preset2k, .preset4k]
        )
    }

    func test2KPresetDimensionsAre1440p() {
        XCTAssertEqual(ResolutionOverride.preset2k.dimensions?.0, 2560)
        XCTAssertEqual(ResolutionOverride.preset2k.dimensions?.1, 1440)
        XCTAssertEqual(ResolutionOverride.preset2k.displayName, "2K (1440p)")
    }

    func testContainerCodecGatingRules() {
        XCTAssertEqual(VideoCodec.allowedCodecs(for: .mp4), [.h264, .hevc, .av1])
        XCTAssertEqual(VideoCodec.allowedCodecs(for: .mov), [.h264, .hevc, .proRes])
        XCTAssertEqual(VideoCodec.allowedCodecs(for: .mkv), [.h264, .hevc, .vp9, .av1])
    }

    func testExternalSubtitleSelectionStoresPickedURL() {
        let picked = URL(fileURLWithPath: "/tmp/subtitle.srt")
        let result = ConversionOptions.resolveExternalSubtitleSelection(
            previousMode: .keep,
            previousAttachmentURL: nil,
            pickedURL: picked
        )
        XCTAssertEqual(result.mode, .addExternal)
        XCTAssertEqual(result.attachmentURL, picked)
    }

    func testExternalSubtitleCancelKeepsPreviousMode() {
        let previous = URL(fileURLWithPath: "/tmp/prev.srt")
        let keepResult = ConversionOptions.resolveExternalSubtitleSelection(
            previousMode: .keep,
            previousAttachmentURL: nil,
            pickedURL: nil
        )
        XCTAssertEqual(keepResult.mode, .keep)
        XCTAssertNil(keepResult.attachmentURL)

        let externalResult = ConversionOptions.resolveExternalSubtitleSelection(
            previousMode: .addExternal,
            previousAttachmentURL: previous,
            pickedURL: nil
        )
        XCTAssertEqual(externalResult.mode, .addExternal)
        XCTAssertEqual(externalResult.attachmentURL, previous)
    }
}
