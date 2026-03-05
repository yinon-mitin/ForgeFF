import XCTest
@testable import ForgeFF

final class FFmpegCommandBuilderTests: XCTestCase {
    func testOutputURLRespectsOverwriteMode() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceURL = tempRoot.appendingPathComponent("source.mov")
        _ = FileManager.default.createFile(atPath: sourceURL.path, contents: Data())

        var options = ConversionOptions.default
        options.outputTemplate = "same_name"
        let job = VideoJob(sourceURL: sourceURL, options: options)

        let expectedOutput = tempRoot.appendingPathComponent("same_name.mp4")
        _ = FileManager.default.createFile(atPath: expectedOutput.path, contents: Data())

        var overwriteOff = AppSettings.default
        overwriteOff.allowOverwrite = false
        let offURL = FFmpegCommandBuilder.outputURL(for: job, settings: overwriteOff)
        XCTAssertNotEqual(offURL.lastPathComponent, "same_name.mp4")
        XCTAssertTrue(offURL.lastPathComponent.hasPrefix("same_name"))

        var overwriteOn = AppSettings.default
        overwriteOn.allowOverwrite = true
        let onURL = FFmpegCommandBuilder.outputURL(for: job, settings: overwriteOn)
        XCTAssertEqual(onURL.lastPathComponent, "same_name.mp4")
    }

    func testBuildArgumentsMapsSimplePresetOptionsToFFmpegFlags() {
        var options = ConversionOptions.default
        options.videoCodec = .hevc
        options.audioCodec = .aac
        options.qualityProfile = .smaller
        options.useHardwareAcceleration = true
        options.removeMetadata = true
        options.removeChapters = true
        options.removeEmbeddedSubtitles = true
        options.enableHDRToSDR = true
        options.toneMapMode = .reinhard
        options.toneMapPeak = 600
        options.resolutionOverride = .preset(width: 1920, height: 1080, label: "1080p")
        options.videoBitrateKbps = 8_000
        options.frameRateOption = .fps30
        options.audioBitrateKbps = 256
        options.outputTemplate = "{name}_review"

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/source clip.mov"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/source clip.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "120.0",
                size: "1000",
                bitRate: "1000",
                tags: nil
            ),
            streams: [
                .init(
                    index: 0,
                    codecName: "hevc",
                    codecLongName: "HEVC",
                    codecType: "video",
                    width: 3840,
                    height: 2160,
                    pixFmt: nil,
                    avgFrameRate: "24000/1001",
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: "smpte2084",
                    colorSpace: nil,
                    colorPrimaries: nil,
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil
                ),
                .init(
                    index: 1,
                    codecName: "aac",
                    codecLongName: "AAC",
                    codecType: "audio",
                    width: nil,
                    height: nil,
                    pixFmt: nil,
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: nil,
                    colorSpace: nil,
                    colorPrimaries: nil,
                    channelLayout: "stereo",
                    sampleRate: "48000",
                    tags: nil
                )
            ],
            chapters: []
        )

        let settings = AppSettings.default
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: settings)
        let combined = arguments.joined(separator: " ")

        XCTAssertTrue(arguments.contains("-map_metadata"))
        XCTAssertTrue(arguments.contains("-map_chapters"))
        XCTAssertTrue(arguments.contains("-sn"))
        XCTAssertTrue(arguments.contains("-n"))
        XCTAssertFalse(arguments.contains("-y"))
        XCTAssertTrue(arguments.contains("hevc_videotoolbox"))
        XCTAssertTrue(arguments.contains("-r"))
        XCTAssertTrue(combined.contains("tonemap=tonemap=reinhard:peak=600"))
        XCTAssertTrue(arguments.contains("/tmp/source_clip_review.mp4"))
    }

    func testBuildArgumentsUsesCustomFPSAndNoSampleRateFlag() {
        var options = ConversionOptions.default
        options.frameRateOption = .custom
        options.customFrameRate = 29.97
        options.sampleRate = 48_000
        options.audioCodec = .aac

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sample.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let combined = arguments.joined(separator: " ")

        XCTAssertTrue(combined.contains("-r 29.97"))
        XCTAssertFalse(arguments.contains("-ar"))
    }

    func testBuildArgumentsMapsAudioChannels() {
        var options = ConversionOptions.default
        options.audioChannels = 6

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sample.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let combined = arguments.joined(separator: " ")

        XCTAssertTrue(combined.contains("-ac 6"))
    }

    func testBuildArgumentsUsesYOnlyWhenOverwriteEnabled() {
        var options = ConversionOptions.default
        options.audioBitrateKbps = 192
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/overwrite.mov"), options: options)

        var overwriteOff = AppSettings.default
        overwriteOff.allowOverwrite = false
        let offArguments = FFmpegCommandBuilder.buildArguments(for: job, settings: overwriteOff)
        XCTAssertTrue(offArguments.contains("-n"))
        XCTAssertFalse(offArguments.contains("-y"))

        var overwriteOn = AppSettings.default
        overwriteOn.allowOverwrite = true
        let onArguments = FFmpegCommandBuilder.buildArguments(for: job, settings: overwriteOn)
        XCTAssertTrue(onArguments.contains("-y"))
        XCTAssertFalse(onArguments.contains("-n"))
    }

    func testBuildArgumentsOmitsAudioBitrateWhenAutoSelected() {
        var options = ConversionOptions.default
        options.audioCodec = .aac
        options.audioBitrateKbps = nil

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/audioauto.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)

        XCTAssertFalse(arguments.contains("-b:a"))
    }

    func testBuildArgumentsDoesNotAddSubtitleDispositionFlags() {
        var options = ConversionOptions.default
        options.removeEmbeddedSubtitles = true
        options.subtitleAttachments = [
            SubtitleAttachment(
                fileURL: URL(fileURLWithPath: "/tmp/sub.srt"),
                languageCode: "eng"
            )
        ]

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/video.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let combined = arguments.joined(separator: " ")

        XCTAssertFalse(combined.contains("-disposition:s:"))
    }

    func testPresetMappingsForSoftwareCodecs() {
        let capabilities = FFmpegEncoderCapabilities(
            supportsVP9: true,
            supportsSVTAV1: true,
            supportsAOMAV1: true
        )

        assertPreset(
            "MP4 — H.264 (Fast)",
            expectedTokens: ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23"],
            capabilities: capabilities
        )
        assertPreset(
            "MP4 — H.264 (Balanced)",
            expectedTokens: ["-c:v", "libx264", "-preset", "medium", "-crf", "21"],
            capabilities: capabilities
        )
        assertPreset(
            "MP4 — H.264 (High Quality)",
            expectedTokens: ["-c:v", "libx264", "-preset", "slow", "-crf", "19"],
            capabilities: capabilities
        )
        assertPreset(
            "MP4 — HEVC (Fast)",
            expectedTokens: ["-c:v", "libx265", "-preset", "fast", "-crf", "28"],
            capabilities: capabilities
        )
        assertPreset(
            "MP4 — HEVC (Balanced)",
            expectedTokens: ["-c:v", "libx265", "-preset", "medium", "-crf", "26"],
            capabilities: capabilities
        )
        assertPreset(
            "MP4 — HEVC (High Quality)",
            expectedTokens: ["-c:v", "libx265", "-preset", "slow", "-crf", "24"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — VP9 (Balanced)",
            expectedTokens: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — VP9 (High Quality)",
            expectedTokens: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "28", "-row-mt", "1"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — AV1 (Balanced)",
            expectedTokens: ["-c:v", "libsvtav1", "-crf", "30", "-preset", "6"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — AV1 (High Quality)",
            expectedTokens: ["-c:v", "libsvtav1", "-crf", "26", "-preset", "4"],
            capabilities: capabilities
        )
        assertPreset(
            "MOV — ProRes 422 (Editing)",
            expectedTokens: ["-c:v", "prores_ks", "-profile:v", "3"],
            capabilities: capabilities
        )
    }

    func testAV1FallsBackToAOMWhenSVTUnavailable() {
        guard let preset = ConversionPreset.builtIns.first(where: { $0.name == "MKV — AV1 (Balanced)" }) else {
            XCTFail("Preset missing")
            return
        }
        var options = ConversionOptions.default
        options.apply(preset: preset)
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/av1.mkv"), options: options)

        let capabilities = FFmpegEncoderCapabilities(
            supportsVP9: true,
            supportsSVTAV1: false,
            supportsAOMAV1: true
        )
        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: .default, capabilities: capabilities)
        let joined = args.joined(separator: " ")
        XCTAssertTrue(joined.contains("-c:v libaom-av1"))
        XCTAssertTrue(joined.contains("-crf 32"))
        XCTAssertTrue(joined.contains("-cpu-used 6"))
    }

    private func assertPreset(
        _ presetName: String,
        expectedTokens: [String],
        capabilities: FFmpegEncoderCapabilities
    ) {
        guard let preset = ConversionPreset.builtIns.first(where: { $0.name == presetName }) else {
            XCTFail("Missing preset: \(presetName)")
            return
        }

        var options = ConversionOptions.default
        options.apply(preset: preset)
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mov"), options: options)
        var settings = AppSettings.default
        settings.autoUseVideoToolbox = false
        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: settings, capabilities: capabilities)
        let joined = args.joined(separator: " ")
        for token in expectedTokens {
            XCTAssertTrue(joined.contains(token), "Expected token '\(token)' in preset '\(presetName)'")
        }
    }
}
