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
                guard let self else { return }
                self.userPresets = presets
                self.draftOptions = self.normalizedPresetReference(for: self.draftOptions)
            }
            .store(in: &cancellables)

        self.draftOptions = normalizedPresetReference(for: self.draftOptions)
    }

    var activePreset: ConversionPreset {
        referencedPreset ?? ConversionPreset.custom
    }

    var isUsingCustomPreset: Bool {
        referencedPreset == nil && draftOptions.presetName == ConversionPreset.custom.name
    }

    var isPresetCustomized: Bool {
        guard let presetOptions = referencedPresetOptions else { return false }
        return controlledPresetState(presetOptions) != controlledPresetState(draftOptions)
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
        draftOptions.isCustomCommandEnabled
    }

    var hasInvalidCustomInputs: Bool {
        hasInvalidCustomResolution || hasInvalidCustomFPS
    }

    func refreshDraftOptions() {
        draftOptions = normalizedPresetReference(for: queueStore.optionsForSelection(selectedJobIDs))
    }

    func applyDraftOptions() {
        queueStore.applyOptions(draftOptions, to: selectedJobIDs)
    }

    func selectPreset(_ preset: ConversionPreset) {
        isApplyingPreset = true
        draftOptions = normalizedPresetReference(for: queueStore.applyPreset(preset, to: selectedJobIDs))
        isApplyingPreset = false
    }

    func selectUserPreset(_ preset: UserPreset) {
        isApplyingPreset = true
        var options = preset.options
        options.presetName = preset.name
        queueStore.applyOptions(options, to: selectedJobIDs)
        draftOptions = normalizedPresetReference(for: options)
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

    func exportUserPresets(to url: URL) throws {
        try userPresetStore.exportPresets(to: url)
    }

    func importUserPresets(from url: URL) throws {
        try userPresetStore.importPresets(from: url)
        userPresets = userPresetStore.presets
    }

    func deleteUserPreset(id: UUID) {
        let deletedPreset = userPresets.first(where: { $0.id == id })
        userPresetStore.deletePreset(id: id)
        userPresets = userPresetStore.presets
        if draftOptions.presetName == deletedPreset?.name {
            var updated = draftOptions
            updated.presetName = ConversionPreset.custom.name
            draftOptions = updated
            applyDraftOptions()
        }
    }

    func updateOptions(_ mutate: (inout ConversionOptions) -> Void) {
        var updated = draftOptions
        mutate(&updated)
        draftOptions = normalizedPresetReference(for: updated, preferredPresetName: draftOptions.presetName)
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

    private var referencedPreset: ConversionPreset? {
        if let explicitPreset = preset(named: draftOptions.presetName) {
            return explicitPreset
        }
        guard let matchedPresetName = matchingPresetName(for: draftOptions) else {
            return nil
        }
        return preset(named: matchedPresetName)
    }

    private var referencedPresetOptions: ConversionOptions? {
        guard let preset = referencedPreset else { return nil }
        return resolvedOptions(for: preset)
    }

    private func normalizedPresetReference(
        for options: ConversionOptions,
        preferredPresetName: String? = nil
    ) -> ConversionOptions {
        guard !isApplyingPreset else { return options }
        var normalized = options

        if let preferredPresetName,
           preferredPresetName != ConversionPreset.custom.name,
           preset(named: preferredPresetName) != nil {
            normalized.presetName = preferredPresetName
            return normalized
        }

        if let matchedPresetName = matchingPresetName(for: options) {
            normalized.presetName = matchedPresetName
        } else if preset(named: normalized.presetName) == nil {
            normalized.presetName = ConversionPreset.custom.name
        }

        return normalized
    }

    private func matchingPresetName(for candidateOptions: ConversionOptions) -> String? {
        let candidateState = controlledPresetState(candidateOptions)
        for preset in ConversionPreset.builtIns {
            if controlledPresetState(resolvedOptions(for: preset)) == candidateState {
                return preset.name
            }
        }
        for userPreset in userPresets where controlledPresetState(userPreset.options) == candidateState {
            return userPreset.name
        }
        return nil
    }

    private func preset(named name: String) -> ConversionPreset? {
        if let builtIn = ConversionPreset.builtIns.first(where: { $0.name == name }) {
            return builtIn
        }
        if let user = userPresets.first(where: { $0.name == name }) {
            return ConversionPreset(
                name: user.name,
                summary: "Saved user preset.",
                tradeoff: "Applies your saved conversion configuration.",
                kind: user.options.isAudioOnly ? .audioOnly : .video,
                container: user.options.container,
                videoCodec: user.options.isAudioOnly ? nil : user.options.videoCodec,
                audioCodec: user.options.audioCodec,
                quality: user.options.qualityProfile,
                encoderOption: user.options.effectiveEncoderOption,
                enableHardwareAcceleration: user.options.useHardwareAcceleration
            )
        }
        return nil
    }

    private func resolvedOptions(for preset: ConversionPreset) -> ConversionOptions {
        if let userPreset = userPresets.first(where: { $0.name == preset.name }) {
            return userPreset.options
        }

        var options = ConversionOptions.default
        options.apply(preset: preset)
        return options
    }

    private func controlledPresetState(_ options: ConversionOptions) -> PresetControlledState {
        let usesCustomCommand = options.isCustomCommandEnabled
        let normalizedAudioBitrate = options.audioCodec == .copy ? nil : options.effectiveAudioBitrateKbps
        let normalizedAudioChannels = options.audioCodec == .copy ? nil : options.audioChannels
        let normalizedSubtitleMode: SubtitleHandling? = {
            guard !usesCustomCommand, !options.isAudioOnly else { return nil }
            let effectiveMode = options.effectiveSubtitleMode
            if effectiveMode == .addExternal, options.subtitleAttachments.isEmpty {
                return .keep
            }
            return effectiveMode
        }()
        let normalizedSubtitleAttachmentKeys: [String] = {
            guard normalizedSubtitleMode == .addExternal else { return [] }
            return options.subtitleAttachments.map {
                let normalizedLanguageCode = $0.languageCode
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return "\($0.fileURL.standardizedFileURL.path)|\(normalizedLanguageCode.isEmpty ? "eng" : normalizedLanguageCode)"
            }
        }()
        let normalizedHardwareAcceleration: Bool? = {
            guard !usesCustomCommand, !options.isAudioOnly else { return nil }
            switch options.videoCodec {
            case .h264, .hevc:
                return options.qualityProfile == .better ? nil : options.useHardwareAcceleration
            case .proRes, .vp9, .av1:
                return nil
            }
        }()

        return PresetControlledState(
            container: options.container,
            outputTemplate: options.outputTemplate,
            isCustomCommandEnabled: usesCustomCommand,
            customCommandTemplate: usesCustomCommand ? options.effectiveCustomCommandTemplate : nil,
            isAudioOnly: usesCustomCommand ? nil : options.isAudioOnly,
            videoCodec: usesCustomCommand || options.isAudioOnly ? nil : options.videoCodec,
            qualityProfile: usesCustomCommand || options.isAudioOnly ? nil : options.qualityProfile,
            encoderOption: usesCustomCommand || options.isAudioOnly ? nil : options.effectiveEncoderOption,
            resolutionOverride: usesCustomCommand || options.isAudioOnly ? nil : options.resolutionOverride,
            frameRateOption: usesCustomCommand || options.isAudioOnly ? nil : options.frameRateOption,
            customFrameRate: usesCustomCommand || options.isAudioOnly || options.frameRateOption != .custom
                ? nil
                : options.customFrameRate,
            audioCodec: usesCustomCommand ? nil : options.audioCodec,
            audioBitrateKbps: usesCustomCommand ? nil : normalizedAudioBitrate,
            audioChannels: usesCustomCommand ? nil : normalizedAudioChannels,
            subtitleMode: normalizedSubtitleMode,
            subtitleAttachmentKeys: normalizedSubtitleAttachmentKeys,
            externalAudioPaths: usesCustomCommand ? [] : options.externalAudioAttachments.map { $0.fileURL.standardizedFileURL.path },
            removeMetadata: usesCustomCommand ? nil : options.removeMetadata,
            removeChapters: usesCustomCommand ? nil : options.removeChapters,
            webOptimization: usesCustomCommand || !options.isWebOptimizationAvailable ? nil : options.webOptimization,
            enableHDRToSDR: usesCustomCommand || options.isAudioOnly ? nil : options.enableHDRToSDR,
            toneMapMode: usesCustomCommand || options.isAudioOnly || !options.enableHDRToSDR ? nil : options.toneMapMode,
            toneMapPeak: usesCustomCommand || options.isAudioOnly || !options.enableHDRToSDR ? nil : options.toneMapPeak,
            useHardwareAcceleration: normalizedHardwareAcceleration,
            videoBitrateKbps: usesCustomCommand || options.isAudioOnly ? nil : options.videoBitrateKbps
        )
    }
}

private struct PresetControlledState: Equatable {
    let container: OutputContainer
    let outputTemplate: String
    let isCustomCommandEnabled: Bool
    let customCommandTemplate: String?
    let isAudioOnly: Bool?
    let videoCodec: VideoCodec?
    let qualityProfile: QualityProfile?
    let encoderOption: EncoderOption?
    let resolutionOverride: ResolutionOverride?
    let frameRateOption: FrameRateOption?
    let customFrameRate: Double?
    let audioCodec: AudioCodec?
    let audioBitrateKbps: Int?
    let audioChannels: Int?
    let subtitleMode: SubtitleHandling?
    let subtitleAttachmentKeys: [String]
    let externalAudioPaths: [String]
    let removeMetadata: Bool?
    let removeChapters: Bool?
    let webOptimization: Bool?
    let enableHDRToSDR: Bool?
    let toneMapMode: ToneMapMode?
    let toneMapPeak: Double?
    let useHardwareAcceleration: Bool?
    let videoBitrateKbps: Int?
}
