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
                    profile: nil,
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
                    tags: nil,
                    sideDataList: nil
                ),
                .init(
                    index: 1,
                    codecName: "aac",
                    codecLongName: "AAC",
                    profile: nil,
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
                    tags: nil,
                    sideDataList: nil
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

    func testBuildArgumentsMaps71AudioChannels() {
        var options = ConversionOptions.default
        options.audioChannels = 8
        options.audioCodec = .aac

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sample_71.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let combined = arguments.joined(separator: " ")

        XCTAssertTrue(combined.contains("-ac 8"))
    }

    func testCustomCommandTemplateValidationRequiresInputAndOutputPlaceholders() {
        let missingInput = FFmpegCommandBuilder.validateCustomCommandTemplate(
            "ffmpeg -hide_banner -c:v libx264 \"{output}\"",
            enabled: true
        )
        XCTAssertNotNil(missingInput.errorMessage)

        let missingOutput = FFmpegCommandBuilder.validateCustomCommandTemplate(
            "ffmpeg -hide_banner -i \"{input}\" -c:v libx264",
            enabled: true
        )
        XCTAssertNotNil(missingOutput.errorMessage)
    }

    func testBuildInvocationSubstitutesCustomTemplatePlaceholders() throws {
        var options = ConversionOptions.default
        options.isCustomCommandOverrideEnabled = true
        options.customCommandTemplate = "ffmpeg -hide_banner -i \"{input}\" -c:v libx264 \"{output}\""
        let inputURL = URL(fileURLWithPath: "/tmp/in sample.mov")
        let job = VideoJob(sourceURL: inputURL, options: options)
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")

        let invocation = try FFmpegCommandBuilder.buildInvocation(
            for: job,
            ffmpegURL: ffmpegURL,
            settings: .default
        )

        XCTAssertEqual(invocation.executableURL, ffmpegURL)
        XCTAssertTrue(invocation.arguments.contains(inputURL.path))
        XCTAssertTrue(invocation.commandLine.contains("/opt/homebrew/bin/ffmpeg"))
    }

    func testCustomCommandTokenizerPreservesQuotedSegments() {
        let tokens = FFmpegCommandBuilder.tokenizeCommandTemplate(
            "ffmpeg -i \"{input}\" -metadata title=\"My Movie\" \"{output}\""
        )
        XCTAssertEqual(tokens, ["ffmpeg", "-i", "{input}", "-metadata", "title=My Movie", "{output}"])
    }

    func testBuildInvocationUsesNormalCommandBuilderWhenCustomTemplateDisabled() throws {
        var options = ConversionOptions.default
        options.isCustomCommandOverrideEnabled = false
        options.customCommandTemplate = "ffmpeg -i \"{input}\" \"{output}\""
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/normal.mov"), options: options)
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")

        let invocation = try FFmpegCommandBuilder.buildInvocation(
            for: job,
            ffmpegURL: ffmpegURL,
            settings: .default
        )

        XCTAssertEqual(invocation.executableURL, ffmpegURL)
        XCTAssertTrue(invocation.arguments.contains("-i"))
    }

    func testBuildInvocationUsesResolvedFFmpegPathWhenTemplateStartsWithFFmpeg() throws {
        var options = ConversionOptions.default
        options.isCustomCommandOverrideEnabled = true
        options.customCommandTemplate = "ffmpeg -hide_banner -i \"{input}\" -c:v libx264 \"{output}\""
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/custom.mov"), options: options)

        let invocation = try FFmpegCommandBuilder.buildInvocation(
            for: job,
            ffmpegURL: ffmpegURL,
            settings: .default
        )

        XCTAssertEqual(invocation.executableURL, ffmpegURL)
        XCTAssertFalse(invocation.arguments.isEmpty)
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

    func testBuildArgumentsAddsFaststartWhenWebOptimizationEnabledForMP4() {
        var options = ConversionOptions.default
        options.container = .mp4
        options.webOptimization = true

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/web-faststart.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-movflags +faststart"))
    }

    func testBuildArgumentsIgnoresFaststartWhenWebOptimizationEnabledForMKV() {
        var options = ConversionOptions.default
        options.container = .mkv
        options.webOptimization = true

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/web-faststart.mkv"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertFalse(joined.contains("-movflags +faststart"))
    }

    func testBuildArgumentsMapsMultipleExternalAudioTracksInOrder() {
        var options = ConversionOptions.default
        options.externalAudioAttachments = [
            ExternalAudioAttachment(fileURL: URL(fileURLWithPath: "/tmp/voiceover.wav")),
            ExternalAudioAttachment(fileURL: URL(fileURLWithPath: "/tmp/commentary.flac"))
        ]

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/video.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-i /tmp/video.mov"))
        XCTAssertTrue(joined.contains("-i /tmp/voiceover.wav"))
        XCTAssertTrue(joined.contains("-i /tmp/commentary.flac"))
        XCTAssertTrue(joined.contains("-map 1:a:0?"))
        XCTAssertTrue(joined.contains("-map 2:a:0?"))
        XCTAssertTrue(arguments.contains("-shortest"))
    }

    func testBuildArgumentsMapsMultipleExternalSubtitlesAfterExternalAudioInputs() {
        var options = ConversionOptions.default
        options.subtitleMode = .addExternal
        options.externalAudioAttachments = [
            ExternalAudioAttachment(fileURL: URL(fileURLWithPath: "/tmp/voiceover.wav")),
            ExternalAudioAttachment(fileURL: URL(fileURLWithPath: "/tmp/commentary.flac"))
        ]
        options.subtitleAttachments = [
            SubtitleAttachment(fileURL: URL(fileURLWithPath: "/tmp/sub-en.srt"), languageCode: "eng"),
            SubtitleAttachment(fileURL: URL(fileURLWithPath: "/tmp/sub-es.srt"), languageCode: "spa")
        ]

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/video.mov"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/video.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "120",
                size: "1000",
                bitRate: "1000",
                tags: nil
            ),
            streams: [
                .init(
                    index: 0,
                    codecName: "h264",
                    codecLongName: nil,
                    profile: nil,
                    codecType: "video",
                    width: 1920,
                    height: 1080,
                    pixFmt: nil,
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: nil,
                    colorSpace: nil,
                    colorPrimaries: nil,
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )

        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-map 3:0"))
        XCTAssertTrue(joined.contains("-map 4:0"))
        XCTAssertTrue(joined.contains("-metadata:s:s:0 language=eng"))
        XCTAssertTrue(joined.contains("-metadata:s:s:1 language=spa"))
    }

    func testOutputSizeEstimatorKnownBitrateAndDuration() {
        let bytes = OutputSizeEstimator.estimateFromTotalBitrate(
            durationSeconds: 120,
            totalBitrateBitsPerSecond: 8_000_000
        )
        XCTAssertEqual(bytes, 120_000_000)
    }

    func testOutputSizeEstimatorVeryFastProducesLargerEstimateThanSlowAtSameQuality() {
        var fastOptions = ConversionOptions.default
        fastOptions.videoCodec = .h264
        fastOptions.qualityProfile = .balanced
        fastOptions.encoderOption = .veryFast

        var slowOptions = fastOptions
        slowOptions.encoderOption = .slow

        let fastEstimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: fastOptions))
        let slowEstimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: slowOptions))

        XCTAssertNotNil(fastEstimate)
        XCTAssertNotNil(slowEstimate)
        XCTAssertGreaterThan(fastEstimate?.outputBytes ?? 0, slowEstimate?.outputBytes ?? 0)
    }

    func testOutputSizeEstimatorDownscaleTo1080pReducesEstimate() {
        var preserveOptions = ConversionOptions.default
        preserveOptions.videoCodec = .hevc
        preserveOptions.qualityProfile = .balanced
        preserveOptions.resolutionOverride = .preserve

        var downscaledOptions = preserveOptions
        downscaledOptions.resolutionOverride = .preset1080p

        let preserveEstimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: preserveOptions))
        let downscaledEstimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: downscaledOptions))

        XCTAssertNotNil(preserveEstimate)
        XCTAssertNotNil(downscaledEstimate)
        XCTAssertGreaterThan(preserveEstimate?.outputBytes ?? 0, downscaledEstimate?.outputBytes ?? 0)
    }

    func testOutputSizeEstimatorAudioCopyUsesKnownSourceAudioBitrate() {
        var options = ConversionOptions.default
        options.isAudioOnly = true
        options.audioCodec = .copy

        let estimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: options))

        XCTAssertEqual(estimate?.outputBytes, 2_880_000)
    }

    func testOutputSizeEstimatorUsesExplicitAudioBitrateSelection() {
        var options = ConversionOptions.default
        options.isAudioOnly = true
        options.audioCodec = .aac
        options.audioBitrateKbps = 256

        let estimate = OutputSizeEstimator.estimate(for: makeEstimatorJob(options: options))

        XCTAssertEqual(estimate?.outputBytes, 3_840_000)
    }

    func testPresetMappingsForSoftwareCodecs() {
        let capabilities = FFmpegEncoderCapabilities(
            supportsX264: true,
            supportsX265: true,
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
            expectedTokens: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-cpu-used", "4", "-row-mt", "1"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — VP9 (High Quality)",
            expectedTokens: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "28", "-cpu-used", "2", "-row-mt", "1"],
            capabilities: capabilities
        )
        assertPreset(
            "MKV — AV1 (Balanced)",
            expectedTokens: ["-c:v", "libsvtav1", "-crf", "30", "-preset", "5"],
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
            supportsX264: true,
            supportsX265: true,
            supportsVP9: true,
            supportsSVTAV1: false,
            supportsAOMAV1: true
        )
        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: .default, capabilities: capabilities)
        let joined = args.joined(separator: " ")
        XCTAssertTrue(joined.contains("-c:v libaom-av1"))
        XCTAssertTrue(joined.contains("-crf 32"))
        XCTAssertTrue(joined.contains("-cpu-used 4"))
    }

    func testEncoderOptionVeryFastMapsToX264Preset() {
        var options = ConversionOptions.default
        options.videoCodec = .h264
        options.useHardwareAcceleration = false
        options.encoderOption = .veryFast
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/h264_speed.mov"), options: options)

        var settings = AppSettings.default
        settings.autoUseVideoToolbox = false
        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: settings)
        let joined = args.joined(separator: " ")
        XCTAssertTrue(joined.contains("-preset veryfast"))
    }

    func testEncoderOptionFastMapsToVP9CPUUsed5() {
        var options = ConversionOptions.default
        options.videoCodec = .vp9
        options.container = .mkv
        options.useHardwareAcceleration = false
        options.encoderOption = .fast
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/vp9_speed.mkv"), options: options)

        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = args.joined(separator: " ")
        XCTAssertTrue(joined.contains("-cpu-used 5"))
    }

    func testEncoderOptionSlowMapsToSVTAV1Preset4() {
        var options = ConversionOptions.default
        options.videoCodec = .av1
        options.container = .mkv
        options.useHardwareAcceleration = false
        options.encoderOption = .slow
        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/av1_speed.mkv"), options: options)
        let capabilities = FFmpegEncoderCapabilities(
            supportsX264: true,
            supportsX265: true,
            supportsVP9: true,
            supportsSVTAV1: true,
            supportsAOMAV1: true
        )

        var settings = AppSettings.default
        settings.autoUseVideoToolbox = false
        let args = FFmpegCommandBuilder.buildArguments(for: job, settings: settings, capabilities: capabilities)
        let joined = args.joined(separator: " ")
        XCTAssertTrue(joined.contains("-preset 4"))
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

    private func makeEstimatorJob(options: ConversionOptions) -> VideoJob {
        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/estimate-source.mov"), options: options)
        job.inputFileSizeBytes = 240_000_000
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/estimate-source.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "120.0",
                size: "240000000",
                bitRate: "16000000",
                tags: nil
            ),
            streams: [
                .init(
                    index: 0,
                    codecName: "h264",
                    codecLongName: "H.264",
                    profile: nil,
                    codecType: "video",
                    width: 3840,
                    height: 2160,
                    pixFmt: "yuv420p",
                    avgFrameRate: "30000/1001",
                    rFrameRate: "30000/1001",
                    bitRate: "14000000",
                    colorTransfer: nil,
                    colorSpace: nil,
                    colorPrimaries: nil,
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                ),
                .init(
                    index: 1,
                    codecName: "aac",
                    codecLongName: "AAC",
                    profile: nil,
                    codecType: "audio",
                    width: nil,
                    height: nil,
                    pixFmt: nil,
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: "192000",
                    colorTransfer: nil,
                    colorSpace: nil,
                    colorPrimaries: nil,
                    channelLayout: "stereo",
                    sampleRate: "48000",
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )
        return job
    }
}
