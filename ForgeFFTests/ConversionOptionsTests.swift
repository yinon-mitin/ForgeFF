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

    func testFormatTransitionSummaryUsesSourceMetadataAndTargetOptions() {
        var options = ConversionOptions.default
        options.container = .mp4
        options.videoCodec = .hevc

        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/sample.mkv"), options: options)
        job.metadata = MediaMetadata(
            format: .init(
                filename: "/tmp/sample.mkv",
                formatName: "matroska,webm",
                formatLongName: "Matroska / WebM",
                duration: "60.0",
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
                    avgFrameRate: "30/1",
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

        XCTAssertEqual(job.formatTransitionSummary, "MATROSKA (H264) → MP4 (HEVC)")
    }

    func testDecodingLegacyExternalAudioURLMigratesToAttachmentArray() throws {
        let legacyJSON = """
        {
          "presetName": "MP4 — H.264 (Fast)",
          "isAudioOnly": false,
          "container": "mp4",
          "videoCodec": "h264",
          "audioCodec": "aac",
          "qualityProfile": "balanced",
          "frameRateOption": "keep",
          "useHardwareAcceleration": true,
          "removeMetadata": false,
          "removeChapters": false,
          "removeEmbeddedSubtitles": false,
          "subtitleAttachments": [],
          "externalAudioURL": "file:///tmp/legacy-voiceover.wav",
          "enableHDRToSDR": false,
          "toneMapMode": "hable",
          "toneMapPeak": 1000,
          "webOptimization": false,
          "outputTemplate": "{name}_{preset}",
          "isCustomCommandOverrideEnabled": false,
          "customCommandTemplate": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ConversionOptions.self, from: legacyJSON)

        XCTAssertEqual(decoded.externalAudioAttachments.count, 1)
        XCTAssertEqual(decoded.externalAudioAttachments.first?.fileURL.path, "/tmp/legacy-voiceover.wav")
    }
}

@MainActor
final class PresetBehaviorTests: XCTestCase {
    private func makeViewModel(fileURL: URL) -> QueueViewModel {
        let settings = SettingsStore(pathDetector: FFmpegPathDetector())
        let history = HistoryStore()
        let queueStore = JobQueueStore(settingsStore: settings, historyStore: history)
        let userPresetStore = UserPresetStore(fileURL: fileURL)
        return QueueViewModel(queueStore: queueStore, userPresetStore: userPresetStore)
    }

    func testManualQualityChangeMarksPresetAsCustomizedButKeepsSelection() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)
        guard let preset = ConversionPreset.builtIns.first else {
            XCTFail("Missing built-in presets")
            return
        }

        viewModel.selectPreset(preset)
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)

        viewModel.updateOptions { $0.qualityProfile = .better }
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)
        XCTAssertTrue(viewModel.isPresetCustomized)
    }

    func testPresetCustomizationClearsWhenSettingsReturnToPresetState() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)
        guard let preset = ConversionPreset.builtIns.first else {
            XCTFail("Missing built-in presets")
            return
        }

        viewModel.selectPreset(preset)
        viewModel.updateOptions { $0.resolutionOverride = .custom(width: 1440, height: 900) }
        XCTAssertTrue(viewModel.isPresetCustomized)

        viewModel.updateOptions { $0.resolutionOverride = .preserve }

        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)
        XCTAssertFalse(viewModel.isPresetCustomized)
    }

    func testProgrammaticPresetApplyDoesNotSwitchToCustom() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)
        guard ConversionPreset.builtIns.count > 1 else {
            XCTFail("Need multiple built-in presets")
            return
        }

        let preset = ConversionPreset.builtIns[1]
        viewModel.selectPreset(preset)
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)
    }

    func testManualEncoderOptionsChangeMarksPresetAsCustomized() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)
        guard let preset = ConversionPreset.builtIns.first else {
            XCTFail("Missing built-in presets")
            return
        }

        viewModel.selectPreset(preset)
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)

        viewModel.updateOptions { $0.encoderOption = .slow }
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)
        XCTAssertTrue(viewModel.isPresetCustomized)
    }

    func testDisablingCustomCommandRestoresPresetMatchWhenNoOtherOverridesRemain() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)
        guard let preset = ConversionPreset.builtIns.first else {
            XCTFail("Missing built-in presets")
            return
        }

        viewModel.selectPreset(preset)
        viewModel.updateOptions {
            $0.isCustomCommandOverrideEnabled = true
            $0.customCommandTemplate = #"ffmpeg -hide_banner -i "{input}" -c:v libx264 -crf 21 "{output}""#
        }
        XCTAssertTrue(viewModel.isPresetCustomized)

        viewModel.updateOptions {
            $0.isCustomCommandOverrideEnabled = false
        }

        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)
        XCTAssertFalse(viewModel.isPresetCustomized)
    }

    func testUserPresetStorePersistsAndDeletes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("user-presets.json")

        let store = UserPresetStore(fileURL: fileURL)
        XCTAssertEqual(store.presets.count, 0)

        var options = ConversionOptions.default
        options.qualityProfile = .better
        store.savePreset(name: "My HQ Preset", options: options)
        XCTAssertEqual(store.presets.count, 1)

        let reloaded = UserPresetStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.presets.count, 1)

        if let id = reloaded.presets.first?.id {
            reloaded.deletePreset(id: id)
        }
        XCTAssertEqual(reloaded.presets.count, 0)
    }

    func testUserPresetStoreExportsAndImportsArchiveSchema() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let storeURL = tempDirectory.appendingPathComponent("user-presets.json")
        let exportURL = tempDirectory.appendingPathComponent("forgeff-presets-v2.json")
        let importURL = tempDirectory.appendingPathComponent("imported-presets.json")

        let store = UserPresetStore(fileURL: storeURL)
        var options = ConversionOptions.default
        options.qualityProfile = .better
        store.savePreset(name: "Archive Preset", options: options)

        try store.exportPresets(to: exportURL)
        let data = try Data(contentsOf: exportURL)
        let archive = try JSONDecoder().decode(UserPresetArchive.self, from: data)
        XCTAssertEqual(archive.schemaVersion, UserPresetArchive.currentSchemaVersion)
        XCTAssertEqual(archive.presets.count, 1)

        let importedStore = UserPresetStore(fileURL: importURL)
        try importedStore.importPresets(from: exportURL)
        XCTAssertEqual(importedStore.presets.count, 1)
        XCTAssertEqual(importedStore.presets.first?.name, "Archive Preset")
    }

    func testDeletingSelectedUserPresetFallsBackToCustom() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let viewModel = makeViewModel(fileURL: fileURL)

        viewModel.saveCurrentAsUserPreset(named: "Temp User Preset")
        guard let preset = viewModel.userPresets.first else {
            XCTFail("Expected saved user preset")
            return
        }
        viewModel.selectUserPreset(preset)
        XCTAssertEqual(viewModel.draftOptions.presetName, preset.name)

        viewModel.deleteUserPreset(id: preset.id)
        XCTAssertEqual(viewModel.draftOptions.presetName, ConversionPreset.custom.name)
    }
}
