import XCTest
@testable import ForgeFF

final class FFmpegPathDetectorTests: XCTestCase {
    func testDetectPrefersHomebrewPaths() {
        let detector = FFmpegPathDetector(
            isExecutable: { path in
                path == "/opt/homebrew/bin/ffmpeg" || path == "/opt/homebrew/bin/ffprobe"
            },
            commandLookup: { _ in nil },
            pathExists: { path in path == "/opt/homebrew/bin" }
        )

        let result = detector.detect(currentFFmpegPath: "", currentFFprobePath: "")

        XCTAssertEqual(result.ffmpegPath, "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(result.ffprobePath, "/opt/homebrew/bin/ffprobe")
        XCTAssertTrue(result.isConfigured)
    }

    func testShouldShowOnboardingWhenOneBinaryMissing() {
        XCTAssertTrue(FFmpegPathDetector.shouldShowOnboarding(ffmpegPath: "", ffprobePath: ""))
    }

    func testParseEncoderAvailabilityFromFFmpegOutput() {
        let output = """
         V..... libx264              H.264 / AVC
         V..... libvpx-vp9           VP9
         V..... libsvtav1            SVT-AV1
        """

        let capabilities = FFmpegEncoderDiscovery.parseEncodersOutput(output)
        XCTAssertTrue(capabilities.supportsVP9)
        XCTAssertTrue(capabilities.supportsSVTAV1)
        XCTAssertFalse(capabilities.supportsAOMAV1)
        XCTAssertTrue(capabilities.supportsAV1)
    }
}
