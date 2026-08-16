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
        XCTAssertTrue(combined.contains("libplacebo=tonemapping=bt.2390"))
        XCTAssertTrue(combined.contains("peak_detect=true"))
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

    func testBuildArgumentsAddsHVC1TagForHEVCInMP4() {
        var options = ConversionOptions.default
        options.container = .mp4
        options.videoCodec = .hevc
        options.useHardwareAcceleration = true

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hevc-preview.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-tag:v hvc1"))
    }

    func testBuildArgumentsAddsHVC1TagForHEVCInMOV() {
        var options = ConversionOptions.default
        options.container = .mov
        options.videoCodec = .hevc
        options.useHardwareAcceleration = false

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hevc-preview.mov"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-tag:v hvc1"))
    }

    func testBuildArgumentsDoesNotAddHVC1TagForHEVCInMKV() {
        var options = ConversionOptions.default
        options.container = .mkv
        options.videoCodec = .hevc

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hevc-preview.mkv"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertFalse(joined.contains("-tag:v hvc1"))
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

    func testTelegramPresetProducesStreamable420PMP4Arguments() throws {
        let preset = try XCTUnwrap(
            ConversionPreset.builtIns.first { $0.name == ConversionPreset.telegramPresetName }
        )
        var options = ConversionOptions.default
        options.apply(preset: preset)

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sony-a7m4-422.mp4"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-c:v libx264"))
        XCTAssertTrue(joined.contains("-preset medium"))
        XCTAssertTrue(joined.contains("-crf 19"))
        XCTAssertTrue(joined.contains("-pix_fmt yuv420p"))
        XCTAssertTrue(joined.contains("-c:a aac"))
        XCTAssertTrue(joined.contains("-b:a 192k"))
        XCTAssertTrue(joined.contains("-ac 2"))
        XCTAssertTrue(joined.contains("-movflags +faststart"))
        XCTAssertFalse(arguments.contains("-r"))
        XCTAssertFalse(arguments.contains("-vf"))
    }

    func testSmallestFilePresetProducesStreamableHEVCArguments() throws {
        let preset = try XCTUnwrap(
            ConversionPreset.builtIns.first { $0.name == ConversionPreset.efficientHEVCPresetName }
        )
        var options = ConversionOptions.default
        options.apply(preset: preset)

        let job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sony-a7m4-422.mp4"), options: options)
        let arguments = FFmpegCommandBuilder.buildArguments(for: job, settings: .default)
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("-c:v libx265"))
        XCTAssertTrue(joined.contains("-preset medium"))
        XCTAssertTrue(joined.contains("-pix_fmt yuv420p"))
        XCTAssertTrue(joined.contains("-tag:v hvc1"))
        XCTAssertTrue(joined.contains("-c:a aac"))
        XCTAssertTrue(joined.contains("-b:a 192k"))
        XCTAssertTrue(joined.contains("-ac 2"))
        XCTAssertTrue(joined.contains("-movflags +faststart"))
        XCTAssertFalse(arguments.contains("-r"))
        XCTAssertFalse(arguments.contains("-vf"))
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

    func testProgressParserIgnoresFinalStatusWithoutTimestamp() {
        XCTAssertNil(FFmpegRunner.parseProgress(line: "frame=100 time=N/A speed=N/A", totalDuration: 10))
    }

    func testProgressParserReadsCurrentOutputSize() {
        let progress = FFmpegRunner.parseProgress(
            line: "frame=100 size=1024KiB time=00:00:05.00 speed=1.0x",
            totalDuration: 10
        )
        XCTAssertEqual(progress?.outputBytes, 1_048_576)
    }

    func testProgressParserReadsCurrentFramesPerSecond() {
        let progress = FFmpegRunner.parseProgress(
            line: "frame=100 fps=38.7 size=1024KiB time=00:00:05.00 speed=1.55x",
            totalDuration: 10
        )
        XCTAssertEqual(progress?.framesPerSecond, 38.7)
    }

    func testRunningOutputEstimateRefinesFromObservedBytes() {
        let refined = OutputSizeEstimator.refinedEstimate(
            observedOutputBytes: 50_000_000,
            encodedRatio: 0.5,
            previousEstimate: 140_000_000
        )
        XCTAssertEqual(refined, 121_000_000)
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

    func testBuildArgumentsUsesZscaleToneMappingWhenLibplaceboUnavailable() {
        var options = ConversionOptions.default
        options.enableHDRToSDR = true
        options.toneMapMode = .hable
        options.toneMapPeak = 1000

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hdr-fallback.mov"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/hdr-fallback.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "10",
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
                    pixFmt: "yuv420p10le",
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: "smpte2084",
                    colorSpace: "bt2020nc",
                    colorPrimaries: "bt2020",
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )

        let filterCapabilities = FFmpegFilterCapabilities(
            hasScanned: true,
            supportsLibplacebo: false,
            supportsZscale: false,
            supportsTonemap: true,
            supportsColorspace: true,
            supportsFormat: true,
            supportsEq: true
        )

        let unsupportedError = FFmpegCommandBuilder.toneMappingSupportError(
            for: job,
            filterCapabilities: filterCapabilities
        )
        XCTAssertNotNil(unsupportedError)

        let zscaleCapabilities = FFmpegFilterCapabilities(
            hasScanned: true,
            supportsLibplacebo: false,
            supportsZscale: true,
            supportsTonemap: true,
            supportsColorspace: true,
            supportsFormat: true,
            supportsEq: true
        )

        let arguments = FFmpegCommandBuilder.buildArguments(
            for: job,
            settings: .default,
            capabilities: .none,
            filterCapabilities: zscaleCapabilities
        )
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("zscale=t=linear:npl=100"))
        XCTAssertTrue(joined.contains("tonemap=tonemap=hable:desat=0.15"))
        XCTAssertTrue(joined.contains("zscale=p=bt709:t=bt709:m=bt709:r=tv"))
        XCTAssertTrue(joined.contains("eq=gamma=1.05:contrast=1.02:brightness=0.02"))
        XCTAssertTrue(joined.contains("format=yuv420p"))
        XCTAssertFalse(joined.contains("libplacebo="))
    }

    func testBuildArgumentsUsesZscaleToneMappingForHLG() {
        var options = ConversionOptions.default
        options.enableHDRToSDR = true
        options.toneMapMode = .reinhard
        options.toneMapPeak = 100

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hdr-hlg.mov"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/hdr-hlg.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "10",
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
                    pixFmt: "yuv420p10le",
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: "arib-std-b67",
                    colorSpace: "bt2020nc",
                    colorPrimaries: "bt2020",
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )

        let filterCapabilities = FFmpegFilterCapabilities(
            hasScanned: true,
            supportsLibplacebo: false,
            supportsZscale: true,
            supportsTonemap: true,
            supportsColorspace: true,
            supportsFormat: true,
            supportsEq: true
        )

        let arguments = FFmpegCommandBuilder.buildArguments(
            for: job,
            settings: .default,
            capabilities: .none,
            filterCapabilities: filterCapabilities
        )
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("zscale=t=linear:npl=100"))
        XCTAssertTrue(joined.contains("tonemap=tonemap=reinhard:desat=0.15"))
        XCTAssertTrue(joined.contains("format=yuv420p"))
    }

    func testBuildArgumentsPrefersLibplaceboWhenAvailable() {
        var options = ConversionOptions.default
        options.enableHDRToSDR = true
        options.toneMapMode = .reinhard

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hdr-libplacebo.mov"), options: options)
        job.metadata = makeHDRMetadata(filePath: "/tmp/hdr-libplacebo.mov", colorTransfer: "smpte2084")
        let filterCapabilities = FFmpegFilterCapabilities(
            hasScanned: true,
            supportsLibplacebo: true,
            supportsZscale: true,
            supportsTonemap: true,
            supportsColorspace: true,
            supportsFormat: true,
            supportsEq: true
        )

        let arguments = FFmpegCommandBuilder.buildArguments(
            for: job,
            settings: .default,
            capabilities: .none,
            filterCapabilities: filterCapabilities
        )
        let joined = arguments.joined(separator: " ")

        XCTAssertTrue(joined.contains("libplacebo=tonemapping=bt.2390"))
        XCTAssertFalse(joined.contains("zscale=t=linear"))
    }

    func testBuildInvocationRejectsUnsupportedToneMappingWhenRequiredFiltersAreMissing() {
        var options = ConversionOptions.default
        options.enableHDRToSDR = true

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/hdr-unsupported.mov"), options: options)
        job.metadata = makeHDRMetadata(filePath: "/tmp/hdr-unsupported.mov", colorTransfer: "smpte2084")

        XCTAssertThrowsError(
            try FFmpegCommandBuilder.buildInvocation(
                for: job,
                ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
                settings: .default,
                capabilities: .none,
                filterCapabilities: .none
            )
        ) { error in
            XCTAssertEqual(
                error as? FFmpegCommandBuilder.CommandInvocationError,
                .unsupportedToneMapping(
                    "HDR tone mapping requires Apple's avconvert or an FFmpeg build with libplacebo or zscale."
                )
            )
        }
    }

    func testToneMappingSupportErrorIgnoresSDRSources() {
        var options = ConversionOptions.default
        options.enableHDRToSDR = true

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sdr-source.mov"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/sdr-source.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "10",
                size: "1000",
                bitRate: "1000",
                tags: nil
            ),
            streams: [
                .init(
                    index: 0,
                    codecName: "h264",
                    codecLongName: "H.264",
                    profile: nil,
                    codecType: "video",
                    width: 1920,
                    height: 1080,
                    pixFmt: "yuv420p",
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: "bt709",
                    colorSpace: "bt709",
                    colorPrimaries: "bt709",
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )

        XCTAssertNil(FFmpegCommandBuilder.toneMappingSupportError(for: job, filterCapabilities: .none))
    }

    func testBuildInvocationUsesIntermediateVideoSourceWhilePreservingOriginalAncillaryStreams() throws {
        var options = ConversionOptions.default
        options.enableHDRToSDR = false
        options.externalAudioAttachments = [ExternalAudioAttachment(fileURL: URL(fileURLWithPath: "/tmp/commentary.m4a"))]
        options.subtitleMode = .addExternal
        options.subtitleAttachments = [SubtitleAttachment(fileURL: URL(fileURLWithPath: "/tmp/captions.srt"), languageCode: "eng")]

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/original-hdr.mov"), options: options)
        job.outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/original-hdr.mov",
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "10",
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
                    pixFmt: "yuv420p10le",
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: "smpte2084",
                    colorSpace: "bt2020nc",
                    colorPrimaries: "bt2020",
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
                ),
                .init(
                    index: 2,
                    codecName: "mov_text",
                    codecLongName: "mov_text",
                    profile: nil,
                    codecType: "subtitle",
                    width: nil,
                    height: nil,
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
            chapters: [
                .init(chapterID: 0, startTime: "0", endTime: "10", tags: ["title": "Intro"])
            ]
        )

        let invocation = try FFmpegCommandBuilder.buildInvocation(
            for: job,
            ffmpegURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            settings: .default,
            capabilities: .none,
            filterCapabilities: .none,
            sourceLayout: .toneMappedIntermediate(
                videoSourceURL: URL(fileURLWithPath: "/tmp/intermediate-sdr.mp4"),
                originalMediaSourceURL: URL(fileURLWithPath: "/tmp/original-hdr.mov")
            )
        )

        let joined = invocation.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("-i /tmp/intermediate-sdr.mp4"))
        XCTAssertTrue(joined.contains("-i /tmp/original-hdr.mov"))
        XCTAssertTrue(joined.contains("-map 0:v:0"))
        XCTAssertTrue(joined.contains("-map 2:a:0?"))
        XCTAssertTrue(joined.contains("-map 1:s?"))
        XCTAssertTrue(joined.contains("-map 3:0"))
        XCTAssertTrue(joined.contains("-map_metadata 1"))
        XCTAssertTrue(joined.contains("-map_chapters 1"))
    }

    func testAVConvertPresetMatchesSourceDimensions() {
        XCTAssertEqual(
            AVConvertPreset.bestMatch(
                for: makeHDRMetadata(
                    filePath: "/tmp/1080p-hdr.mov",
                    width: 1920,
                    height: 1080,
                    colorTransfer: "smpte2084"
                )
            ),
            .preset1920x1080
        )
        XCTAssertEqual(
            AVConvertPreset.bestMatch(
                for: makeHDRMetadata(
                    filePath: "/tmp/2160p-hdr.mov",
                    width: 3840,
                    height: 2160,
                    colorTransfer: "smpte2084"
                )
            ),
            .preset3840x2160
        )
        XCTAssertEqual(
            AVConvertPreset.bestMatch(
                for: makeHDRMetadata(
                    filePath: "/tmp/8k-hdr.mov",
                    width: 7680,
                    height: 4320,
                    colorTransfer: "smpte2084"
                )
            ),
            .presetHighestQuality
        )
    }

    func testProgressEmissionGateThrottlesFrequentUpdatesAndAllowsCompletion() {
        let gate = ProcessProgressEmissionGate(minimumInterval: 0.1)

        XCTAssertTrue(gate.shouldEmit(now: 10))
        XCTAssertFalse(gate.shouldEmit(now: 10.05))
        XCTAssertTrue(gate.shouldEmit(now: 10.101))
        XCTAssertTrue(gate.shouldEmit(now: 10.11, force: true))
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

    private func makeHDRMetadata(
        filePath: String,
        width: Int = 3840,
        height: Int = 2160,
        colorTransfer: String
    ) -> MediaMetadata {
        MediaMetadata(
            format: .init(
                filename: filePath,
                formatName: "mov",
                formatLongName: "QuickTime / MOV",
                duration: "10",
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
                    width: width,
                    height: height,
                    pixFmt: "yuv420p10le",
                    avgFrameRate: nil,
                    rFrameRate: nil,
                    bitRate: nil,
                    colorTransfer: colorTransfer,
                    colorSpace: "bt2020nc",
                    colorPrimaries: "bt2020",
                    channelLayout: nil,
                    sampleRate: nil,
                    tags: nil,
                    sideDataList: nil
                )
            ],
            chapters: []
        )
    }
}
