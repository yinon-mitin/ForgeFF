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

@MainActor
final class PresetBehaviorTests: XCTestCase {
    private func makeViewModel(fileURL: URL) -> QueueViewModel {
        let settings = SettingsStore(pathDetector: FFmpegPathDetector())
        let history = HistoryStore()
        let queueStore = JobQueueStore(settingsStore: settings, historyStore: history)
        let userPresetStore = UserPresetStore(fileURL: fileURL)
        return QueueViewModel(queueStore: queueStore, userPresetStore: userPresetStore)
    }

    func testManualQualityChangeSwitchesPresetToCustom() {
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
        XCTAssertEqual(viewModel.draftOptions.presetName, ConversionPreset.custom.name)
    }

    func testManualResolutionCustomChangeSwitchesPresetToCustom() {
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

        XCTAssertEqual(viewModel.draftOptions.presetName, ConversionPreset.custom.name)
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
