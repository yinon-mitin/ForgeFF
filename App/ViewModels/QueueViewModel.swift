import Combine
import Foundation

@MainActor
final class QueueViewModel: ObservableObject {
    @Published var selectedJobIDs = Set<UUID>()
    @Published var renameConfiguration = BatchRenameConfiguration()
    @Published var draftOptions: ConversionOptions
    @Published var isAdvancedExpanded = false
    @Published var hasInvalidCustomResolution = false
    @Published var hasInvalidCustomFPS = false
    @Published private(set) var userPresets: [UserPreset] = []

    let queueStore: JobQueueStore
    private let userPresetStore: UserPresetStore
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingPreset = false

    init(
        queueStore: JobQueueStore,
        userPresetStore: UserPresetStore
    ) {
        self.queueStore = queueStore
        self.userPresetStore = userPresetStore
        self.draftOptions = queueStore.optionsForSelection(nil)
        self.userPresets = userPresetStore.presets
        userPresetStore.$presets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presets in
                self?.userPresets = presets
            }
            .store(in: &cancellables)
    }

    var activePreset: ConversionPreset {
        if draftOptions.presetName == ConversionPreset.custom.name {
            return ConversionPreset.custom
        }
        if let builtIn = ConversionPreset.builtIns.first(where: { $0.name == draftOptions.presetName }) {
            return builtIn
        }
        if let user = userPresets.first(where: { $0.name == draftOptions.presetName }) {
            return ConversionPreset(
                name: user.name,
                summary: "Saved user preset.",
                tradeoff: "Applies your saved conversion configuration.",
                kind: user.options.isAudioOnly ? .audioOnly : .video,
                container: user.options.container,
                videoCodec: user.options.isAudioOnly ? nil : user.options.videoCodec,
                audioCodec: user.options.audioCodec,
                quality: user.options.qualityProfile,
                enableHardwareAcceleration: user.options.useHardwareAcceleration
            )
        }
        return ConversionPreset.custom
    }

    var renamePreview: [UUID: String] {
        FilenameRenamer.preview(for: queueStore.jobs, configuration: renameConfiguration)
    }

    var selectedJobs: [VideoJob] {
        queueStore.jobs.filter { selectedJobIDs.contains($0.id) }
    }

    var isAdvancedModified: Bool {
        draftOptions.videoBitrateKbps != nil ||
        draftOptions.subtitleAttachments.contains(where: { $0.languageCode != "eng" }) ||
        !draftOptions.customFFmpegArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasInvalidCustomInputs: Bool {
        hasInvalidCustomResolution || hasInvalidCustomFPS
    }

    func refreshDraftOptions() {
        draftOptions = queueStore.optionsForSelection(selectedJobIDs)
    }

    func applyDraftOptions() {
        queueStore.applyOptions(draftOptions, to: selectedJobIDs)
    }

    func selectPreset(_ preset: ConversionPreset) {
        isApplyingPreset = true
        draftOptions = queueStore.applyPreset(preset, to: selectedJobIDs)
        isApplyingPreset = false
    }

    func selectUserPreset(_ preset: UserPreset) {
        isApplyingPreset = true
        var options = preset.options
        options.presetName = preset.name
        queueStore.applyOptions(options, to: selectedJobIDs)
        draftOptions = options
        isApplyingPreset = false
    }

    func selectCustomPreset() {
        draftOptions.presetName = ConversionPreset.custom.name
        applyDraftOptions()
    }

    func selectPreset(named name: String) {
        if name == ConversionPreset.custom.name {
            selectCustomPreset()
            return
        }
        if let preset = ConversionPreset.builtIns.first(where: { $0.name == name }) {
            selectPreset(preset)
            return
        }
        if let preset = userPresets.first(where: { $0.name == name }) {
            selectUserPreset(preset)
        }
    }

    func selectAdjacentPreset(step: Int) {
        let names = ConversionPreset.builtIns.map(\.name) + userPresets.map(\.name) + [ConversionPreset.custom.name]
        guard !names.isEmpty else { return }
        let currentIndex = names.firstIndex(of: draftOptions.presetName) ?? (names.count - 1)
        let nextIndex = min(max(0, currentIndex + step), names.count - 1)
        selectPreset(named: names[nextIndex])
    }

    func saveCurrentAsUserPreset(named name: String) {
        userPresetStore.savePreset(name: name, options: draftOptions)
        userPresets = userPresetStore.presets
    }

    func deleteUserPreset(id: UUID) {
        let deletedPreset = userPresets.first(where: { $0.id == id })
        userPresetStore.deletePreset(id: id)
        userPresets = userPresetStore.presets
        if draftOptions.presetName == deletedPreset?.name {
            draftOptions.presetName = ConversionPreset.custom.name
            applyDraftOptions()
        }
    }

    func updateOptions(_ mutate: (inout ConversionOptions) -> Void) {
        let previous = draftOptions
        var updated = draftOptions
        mutate(&updated)
        if shouldSwitchToCustom(previous: previous, updated: updated) {
            updated.presetName = ConversionPreset.custom.name
        }
        draftOptions = updated
        applyDraftOptions()
    }

    func applyRenamePreview() {
        if renameConfiguration.sanitizeFilename {
            renameConfiguration = FilenameRenamer.normalizedConfiguration(renameConfiguration, sanitizeFields: true)
        } else {
            renameConfiguration = FilenameRenamer.normalizedConfiguration(renameConfiguration, sanitizeFields: false)
        }
        queueStore.applyBatchRename(configuration: renameConfiguration)
    }

    func removeSelectedJobs() {
        queueStore.remove(jobIDs: selectedJobIDs)
        selectedJobIDs.removeAll()
        refreshDraftOptions()
    }

    func setCustomValidation(resolutionValid: Bool?, fpsValid: Bool?) {
        if let resolutionValid {
            hasInvalidCustomResolution = !resolutionValid
        }
        if let fpsValid {
            hasInvalidCustomFPS = !fpsValid
        }
    }

    private func shouldSwitchToCustom(previous: ConversionOptions, updated: ConversionOptions) -> Bool {
        guard !isApplyingPreset else { return false }
        guard previous.presetName != ConversionPreset.custom.name else { return false }
        return controlledPresetState(previous) != controlledPresetState(updated)
    }

    private func controlledPresetState(_ options: ConversionOptions) -> PresetControlledState {
        PresetControlledState(
            container: options.container,
            videoCodec: options.videoCodec,
            qualityProfile: options.qualityProfile,
            resolutionOverride: options.resolutionOverride,
            frameRateOption: options.frameRateOption,
            customFrameRate: options.customFrameRate,
            audioCodec: options.audioCodec,
            audioBitrateKbps: options.audioBitrateKbps,
            audioChannels: options.audioChannels,
            subtitleMode: options.effectiveSubtitleMode,
            subtitleAttachmentKeys: options.subtitleAttachments.map {
                "\($0.fileURL.path)|\($0.languageCode)"
            },
            removeMetadata: options.removeMetadata,
            removeChapters: options.removeChapters,
            enableHDRToSDR: options.enableHDRToSDR,
            toneMapMode: options.toneMapMode,
            useHardwareAcceleration: options.useHardwareAcceleration
        )
    }
}

private struct PresetControlledState: Equatable {
    let container: OutputContainer
    let videoCodec: VideoCodec
    let qualityProfile: QualityProfile
    let resolutionOverride: ResolutionOverride
    let frameRateOption: FrameRateOption
    let customFrameRate: Double?
    let audioCodec: AudioCodec
    let audioBitrateKbps: Int?
    let audioChannels: Int?
    let subtitleMode: SubtitleHandling
    let subtitleAttachmentKeys: [String]
    let removeMetadata: Bool
    let removeChapters: Bool
    let enableHDRToSDR: Bool
    let toneMapMode: ToneMapMode
    let useHardwareAcceleration: Bool
}
