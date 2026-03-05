import SwiftUI

struct PresetOptionsPanelView: View {
    @EnvironmentObject private var queueStore: JobQueueStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var viewModel: QueueViewModel
    @State private var customWidthInput = "1920"
    @State private var customHeightInput = "1080"
    @State private var customFPSInput = "30"

    var body: some View {
        List {
            presetsSection
            defaultsSection
            essentialsSection
            subtitlesSection
            cleanupSection
            hdrSection
            advancedSection
            renameSection
        }
        .listStyle(.sidebar)
        .textFieldStyle(.roundedBorder)
        .navigationTitle("Options")
        .onAppear {
            syncCustomInputsFromOptions()
            refreshCustomValidationState()
            normalizeVideoCodecSelection()
        }
        .onChange(of: viewModel.draftOptions.resolutionOverride) { _ in
            syncCustomInputsFromOptions()
            refreshCustomValidationState()
        }
        .onChange(of: viewModel.draftOptions.frameRateOption) { _ in
            syncCustomInputsFromOptions()
            refreshCustomValidationState()
        }
        .onChange(of: settingsStore.encoderCapabilities) { _ in
            normalizeVideoCodecSelection()
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
            Menu {
                Section("H.264 / HEVC") {
                    presetButton(named: "MP4 — H.264 (Fast)")
                    presetButton(named: "MP4 — H.264 (Balanced)")
                    presetButton(named: "MP4 — H.264 (High Quality)")
                    presetButton(named: "MP4 — HEVC (Fast)")
                    presetButton(named: "MP4 — HEVC (Balanced)")
                    presetButton(named: "MP4 — HEVC (High Quality)")
                }
                Section("Modern Codecs") {
                    presetButton(named: "MKV — VP9 (Balanced)")
                    presetButton(named: "MKV — VP9 (High Quality)")
                    presetButton(named: "MKV — AV1 (Balanced)")
                    presetButton(named: "MKV — AV1 (High Quality)")
                }
                Section("Editing / Custom") {
                    presetButton(named: "MOV — ProRes 422 (Editing)")
                    presetButton(named: "Custom (Simple)")
                }
            } label: {
                Text("Preset: \(activePresetDisplayName)")
            }

            Text(viewModel.activePreset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.activePreset.tradeoff)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultsSection: some View {
        Section("Defaults") {
            Button("Choose default output folder") {
                settingsStore.chooseDefaultOutputDirectory()
            }
            if let outputFolder = settingsStore.defaultOutputDirectoryURL {
                Text(outputFolder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Toggle("Use Apple VideoToolbox by default", isOn: settingsBinding(\.autoUseVideoToolbox))
            Toggle("Allow overwrite (off recommended)", isOn: settingsBinding(\.allowOverwrite))
        }
    }

    private var essentialsSection: some View {
        Section("Essentials") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Container")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: OutputContainer.allCases,
                    selection: containerBinding,
                    title: { $0.fileExtension.uppercased() }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Video codec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: allowedVideoCodecs,
                    selection: optionsBinding(\.videoCodec),
                    title: { $0.displayName },
                    isDisabled: { codec in
                        viewModel.draftOptions.isAudioOnly || isVideoCodecUnavailable(codec)
                    },
                    helpText: { codec in
                        videoCodecHelpText(codec)
                    }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: QualityProfile.allCases,
                    selection: optionsBinding(\.qualityProfile),
                    title: { $0.displayName }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: resolutionChoices,
                    selection: resolutionChoiceBinding,
                    title: { $0.label },
                    isDisabled: { _ in viewModel.draftOptions.isAudioOnly }
                )
            }

            if resolutionChoiceBinding.wrappedValue == .custom {
                HStack(spacing: 8) {
                    TextField("Width", text: $customWidthInput)
                        .onChange(of: customWidthInput) { _ in applyCustomResolutionIfValid() }
                    TextField("Height", text: $customHeightInput)
                        .onChange(of: customHeightInput) { _ in applyCustomResolutionIfValid() }
                }
                .onAppear { applyCustomResolutionIfValid() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("FPS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: fpsChoices,
                    selection: fpsChoiceBinding,
                    title: { $0.label },
                    isDisabled: { _ in viewModel.draftOptions.isAudioOnly }
                )
            }

            if fpsChoiceBinding.wrappedValue == .custom {
                TextField("Custom FPS", text: $customFPSInput)
                    .onChange(of: customFPSInput) { _ in applyCustomFPSIfValid() }
                    .onAppear { applyCustomFPSIfValid() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: [AudioCodec.copy, .aac, .mp3],
                    selection: optionsBinding(\.audioCodec),
                    title: { $0.displayName }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Audio bitrate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: AudioBitrateChoice.allCases,
                    selection: audioBitrateChoiceBinding,
                    title: { $0.displayName },
                    isDisabled: { _ in viewModel.draftOptions.audioCodec == .copy }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Audio channels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WrappingPills(
                    options: AudioChannelChoice.allCases,
                    selection: audioChannelBinding,
                    title: { $0.displayName }
                )
            }

        }
    }

    private var subtitlesSection: some View {
        Section("Subtitles") {
            WrappingPills(options: SubtitleHandling.allCases, selection: subtitleModeBinding, title: { $0.displayName })

            if subtitleMode == .addExternal {
                Button(viewModel.draftOptions.subtitleAttachments.isEmpty ? "Add external subtitle file…" : "Replace subtitle file…") {
                    handleAddExternalSubtitleSelection(previousMode: .addExternal)
                }
                if let subtitle = viewModel.draftOptions.subtitleAttachments.first {
                    Text(subtitle.fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Clear external subtitle") {
                        applySubtitleMode(.keep)
                    }
                }
            }
        }
    }

    private var cleanupSection: some View {
        Section("Cleanup") {
            Toggle("Remove metadata", isOn: optionsBinding(\.removeMetadata))
            Toggle("Remove chapters", isOn: optionsBinding(\.removeChapters))
        }
    }

    private var hdrSection: some View {
        Section("HDR → SDR") {
            Toggle("Enable tone map", isOn: optionsBinding(\.enableHDRToSDR))
                .disabled(viewModel.draftOptions.isAudioOnly)
            Picker("Tone map method", selection: optionsBinding(\.toneMapMode)) {
                ForEach(ToneMapMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(!viewModel.draftOptions.enableHDRToSDR || viewModel.draftOptions.isAudioOnly)
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.isAdvancedExpanded) {
                GroupBox("Binaries") {
                    VStack(alignment: .leading, spacing: 10) {
                        binaryRow(
                            title: "ffmpeg",
                            path: settingsStore.ffmpegURL?.path,
                            onChange: { settingsStore.chooseBinary(for: \.ffmpegBinaryPath) },
                            onReset: { settingsStore.resetBinaryToAuto(for: \.ffmpegBinaryPath) }
                        )
                        binaryRow(
                            title: "ffprobe",
                            path: settingsStore.ffprobeURL?.path,
                            onChange: { settingsStore.chooseBinary(for: \.ffprobeBinaryPath) },
                            onReset: { settingsStore.resetBinaryToAuto(for: \.ffprobeBinaryPath) }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Video bitrate override (kbps)", text: fieldBinding(viewModel.draftOptions.videoBitrateKbps) { newValue in
                    viewModel.updateOptions { $0.videoBitrateKbps = newValue }
                })
                TextField("Subtitle language", text: subtitleLanguageBinding)
            } label: {
                HStack {
                    Text("Advanced")
                    if viewModel.isAdvancedModified {
                        Text("Advanced modified")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var renameSection: some View {
        Section("Rename") {
            TextField("Prefix", text: $viewModel.renameConfiguration.prefix)
            TextField("Suffix", text: $viewModel.renameConfiguration.suffix)
            TextField("Replace", text: $viewModel.renameConfiguration.replaceText)
            TextField("With", text: $viewModel.renameConfiguration.replaceWith)
            Toggle("Sanitize filenames", isOn: $viewModel.renameConfiguration.sanitizeFilename)

            GroupBox("Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before: \(renamePreview.before)")
                    Text("After:  \(renamePreview.after)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Apply Rename") {
                viewModel.applyRenamePreview()
            }

            if let selectedJobID = viewModel.selectedJobIDs.first, viewModel.selectedJobIDs.count == 1 {
                Button("Choose Output Folder for Selection") {
                    queueStore.selectedJobID = selectedJobID
                    queueStore.chooseOutputDirectoryForSelectedJob()
                }
            }
        }
    }

    private var containerBinding: Binding<OutputContainer> {
        Binding(
            get: { viewModel.draftOptions.container },
            set: { newValue in
                viewModel.updateOptions {
                    $0.container = newValue
                    if !$0.isAudioOnly {
                        let validCodecs = VideoCodec.allowedCodecs(for: newValue)
                        if !validCodecs.contains($0.videoCodec) {
                            $0.videoCodec = validCodecs.first ?? .h264
                        }
                    }
                }
            }
        )
    }

    private var subtitleModeBinding: Binding<SubtitleHandling> {
        Binding(
            get: { subtitleMode },
            set: { newValue in
                switch newValue {
                case .keep:
                    applySubtitleMode(.keep)
                case .remove:
                    applySubtitleMode(.remove)
                case .addExternal:
                    handleAddExternalSubtitleSelection(previousMode: subtitleMode)
                }
            }
        )
    }

    private var subtitleMode: SubtitleHandling {
        viewModel.draftOptions.effectiveSubtitleMode
    }

    private var allowedVideoCodecs: [VideoCodec] {
        VideoCodec.allowedCodecs(for: viewModel.draftOptions.container)
    }

    private var resolutionChoices: [ResolutionChoice] {
        [
            .keep,
            .preset(.preset720p),
            .preset(.preset1080p),
            .preset(.preset2k),
            .preset(.preset4k),
            .custom
        ]
    }

    private var resolutionChoiceBinding: Binding<ResolutionChoice> {
        Binding(
            get: {
                switch viewModel.draftOptions.resolutionOverride {
                case .preserve:
                    return .keep
                case let .preset(width, _, _):
                    switch width {
                    case 1280: return .preset(.preset720p)
                    case 1920: return .preset(.preset1080p)
                    case 2560: return .preset(.preset2k)
                    default: return .preset(.preset4k)
                    }
                case .custom:
                    return .custom
                }
            },
            set: { newChoice in
                viewModel.updateOptions {
                    switch newChoice {
                    case .keep:
                        $0.resolutionOverride = .preserve
                    case let .preset(value):
                        $0.resolutionOverride = value
                    case .custom:
                        $0.resolutionOverride = .custom(width: Int(customWidthInput) ?? 1920, height: Int(customHeightInput) ?? 1080)
                    }
                }
                viewModel.setCustomValidation(resolutionValid: true, fpsValid: nil)
            }
        )
    }

    private var fpsChoices: [FPSChoice] {
        [.keep, .fps24, .fps30, .fps60, .custom]
    }

    private var fpsChoiceBinding: Binding<FPSChoice> {
        Binding(
            get: {
                switch viewModel.draftOptions.frameRateOption {
                case .keep: return .keep
                case .fps24: return .fps24
                case .fps30: return .fps30
                case .fps60: return .fps60
                case .custom: return .custom
                }
            },
            set: { newChoice in
                viewModel.updateOptions {
                    switch newChoice {
                    case .keep:
                        $0.frameRateOption = .keep
                        $0.customFrameRate = nil
                    case .fps24:
                        $0.frameRateOption = .fps24
                        $0.customFrameRate = nil
                    case .fps30:
                        $0.frameRateOption = .fps30
                        $0.customFrameRate = nil
                    case .fps60:
                        $0.frameRateOption = .fps60
                        $0.customFrameRate = nil
                    case .custom:
                        $0.frameRateOption = .custom
                    }
                }
                viewModel.setCustomValidation(resolutionValid: nil, fpsValid: true)
            }
        )
    }

    private var audioChannelBinding: Binding<AudioChannelChoice> {
        Binding(
            get: { AudioChannelChoice(channelCount: viewModel.draftOptions.audioChannels) },
            set: { newValue in
                viewModel.updateOptions {
                    $0.audioChannels = newValue.channelCount
                }
            }
        )
    }

    private var audioBitrateChoiceBinding: Binding<AudioBitrateChoice> {
        Binding(
            get: { AudioBitrateChoice(kbps: viewModel.draftOptions.audioBitrateKbps) },
            set: { newValue in
                viewModel.updateOptions {
                    $0.audioBitrateKbps = newValue.kbps
                }
            }
        )
    }

    private var activePresetDisplayName: String {
        viewModel.activePreset.name
    }

    private var resolutionDisplay: String {
        switch viewModel.draftOptions.resolutionOverride {
        case .preserve:
            return "Keep"
        case let .preset(_, _, label):
            return label
        case let .custom(width, height):
            return "Custom (\(width)x\(height))"
        }
    }

    private var fpsDisplay: String {
        viewModel.draftOptions.frameRateOption.displayName
    }

    private var renamePreview: (before: String, after: String) {
        let before = queueStore.jobs.first?.sourceDisplayName ?? "Example Video 001.mkv"
        let url = URL(fileURLWithPath: before)
        let baseName = url.deletingPathExtension().lastPathComponent
        let extensionPart = url.pathExtension
        let renamed = FilenameRenamer.apply(to: baseName, configuration: viewModel.renameConfiguration)
        let after = extensionPart.isEmpty ? renamed : "\(renamed).\(extensionPart)"
        return (before, after)
    }

    private func optionsBinding<Value>(_ keyPath: WritableKeyPath<ConversionOptions, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.draftOptions[keyPath: keyPath] },
            set: { newValue in
                viewModel.updateOptions { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func fieldBinding(_ value: Int?, set: @escaping (Int?) -> Void) -> Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { newValue in
                set(Int(newValue))
            }
        )
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func binaryRow(
        title: String,
        path: String?,
        onChange: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(path ?? "Not detected")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Button("Change…", action: onChange)
                Button("Reset to Auto", action: onReset)
            }
        }
    }

    private func presetButton(named name: String) -> some View {
        Button(name) {
            guard let preset = ConversionPreset.builtIns.first(where: { $0.name == name }) else { return }
            viewModel.selectPreset(preset)
        }
    }

    private func applySubtitleMode(_ mode: SubtitleHandling, attachmentURL: URL? = nil) {
        viewModel.updateOptions {
            $0.subtitleMode = mode
            switch mode {
            case .keep:
                $0.removeEmbeddedSubtitles = false
                if attachmentURL == nil {
                    $0.subtitleAttachments = []
                }
            case .remove:
                $0.removeEmbeddedSubtitles = true
                $0.subtitleAttachments = []
            case .addExternal:
                $0.removeEmbeddedSubtitles = false
                if let attachmentURL {
                    $0.subtitleAttachments = [SubtitleAttachment(fileURL: attachmentURL, languageCode: "eng")]
                }
            }
        }
    }

    private func handleAddExternalSubtitleSelection(previousMode: SubtitleHandling) {
        let previousAttachmentURL = viewModel.draftOptions.subtitleAttachments.first?.fileURL
        let subtitleURL = queueStore.chooseSubtitleAttachmentURL()
        let resolved = ConversionOptions.resolveExternalSubtitleSelection(
            previousMode: previousMode,
            previousAttachmentURL: previousAttachmentURL,
            pickedURL: subtitleURL
        )
        applySubtitleMode(resolved.mode, attachmentURL: resolved.attachmentURL)

        guard let subtitleURL = subtitleURL else { return }

        let ext = subtitleURL.pathExtension.lowercased()
        if resolved.mode == .addExternal && viewModel.draftOptions.container != .mkv && ext != "srt" {
            queueStore.alertMessage = "Use MKV for best subtitle support with this subtitle format."
        }
    }

    private func isVideoCodecUnavailable(_ codec: VideoCodec) -> Bool {
        switch codec {
        case .vp9:
            return !settingsStore.encoderCapabilities.supportsVP9
        case .av1:
            return !settingsStore.encoderCapabilities.supportsAV1
        default:
            return false
        }
    }

    private func videoCodecHelpText(_ codec: VideoCodec) -> String? {
        guard isVideoCodecUnavailable(codec) else { return nil }
        return "Not available in your FFmpeg build"
    }

    private func normalizeVideoCodecSelection() {
        guard !viewModel.draftOptions.isAudioOnly else { return }
        let selectable = allowedVideoCodecs.filter { !isVideoCodecUnavailable($0) }
        guard let fallback = selectable.first else { return }
        if !selectable.contains(viewModel.draftOptions.videoCodec) {
            viewModel.updateOptions { $0.videoCodec = fallback }
        }
    }

    private func syncCustomInputsFromOptions() {
        if case let .custom(width, height) = viewModel.draftOptions.resolutionOverride {
            customWidthInput = "\(width)"
            customHeightInput = "\(height)"
        }
        if viewModel.draftOptions.frameRateOption == .custom,
           let customFPS = viewModel.draftOptions.customFrameRate {
            customFPSInput = String(customFPS)
        }
    }

    private func refreshCustomValidationState() {
        if resolutionChoiceBinding.wrappedValue == .custom {
            let valid = (Int(customWidthInput) ?? 0) > 0 && (Int(customHeightInput) ?? 0) > 0
            viewModel.setCustomValidation(resolutionValid: valid, fpsValid: nil)
        } else {
            viewModel.setCustomValidation(resolutionValid: true, fpsValid: nil)
        }

        if fpsChoiceBinding.wrappedValue == .custom {
            let valid = (Double(customFPSInput) ?? 0) > 0
            viewModel.setCustomValidation(resolutionValid: nil, fpsValid: valid)
        } else {
            viewModel.setCustomValidation(resolutionValid: nil, fpsValid: true)
        }
    }

    private func applyCustomResolutionIfValid() {
        guard resolutionChoiceBinding.wrappedValue == .custom else {
            viewModel.setCustomValidation(resolutionValid: true, fpsValid: nil)
            return
        }

        guard let width = Int(customWidthInput), width > 0,
              let height = Int(customHeightInput), height > 0 else {
            viewModel.setCustomValidation(resolutionValid: false, fpsValid: nil)
            return
        }

        viewModel.setCustomValidation(resolutionValid: true, fpsValid: nil)
        viewModel.updateOptions {
            $0.resolutionOverride = .custom(width: width, height: height)
        }
    }

    private func applyCustomFPSIfValid() {
        guard fpsChoiceBinding.wrappedValue == .custom else {
            viewModel.setCustomValidation(resolutionValid: nil, fpsValid: true)
            return
        }

        guard let fps = Double(customFPSInput), fps > 0 else {
            viewModel.setCustomValidation(resolutionValid: nil, fpsValid: false)
            return
        }

        viewModel.setCustomValidation(resolutionValid: nil, fpsValid: true)
        viewModel.updateOptions {
            $0.frameRateOption = .custom
            $0.customFrameRate = fps
        }
    }

    private var subtitleLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.draftOptions.subtitleAttachments.first?.languageCode ?? "eng" },
            set: { newValue in
                guard var attachment = viewModel.draftOptions.subtitleAttachments.first else { return }
                attachment.languageCode = newValue
                viewModel.updateOptions { $0.subtitleAttachments = [attachment] }
            }
        )
    }

}

private extension SubtitleHandling {
    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .remove: return "Remove"
        case .addExternal: return "Add External"
        }
    }
}

private enum ResolutionChoice: Hashable {
    case keep
    case preset(ResolutionOverride)
    case custom

    var label: String {
        switch self {
        case .keep:
            return "Keep"
        case let .preset(value):
            return value.displayName
        case .custom:
            return "Custom…"
        }
    }
}

private enum FPSChoice: String, CaseIterable, Hashable {
    case keep
    case fps24
    case fps30
    case fps60
    case custom

    var label: String {
        switch self {
        case .keep: return "Keep"
        case .fps24: return "24"
        case .fps30: return "30"
        case .fps60: return "60"
        case .custom: return "Custom…"
        }
    }
}

private enum AudioChannelChoice: String, CaseIterable, Hashable {
    case keep
    case mono
    case stereo
    case surround51

    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .surround51: return "5.1"
        }
    }

    var channelCount: Int? {
        switch self {
        case .keep: return nil
        case .mono: return 1
        case .stereo: return 2
        case .surround51: return 6
        }
    }

    init(channelCount: Int?) {
        switch channelCount {
        case 1: self = .mono
        case 2: self = .stereo
        case 6: self = .surround51
        default: self = .keep
        }
    }
}

private enum AudioBitrateChoice: CaseIterable, Hashable {
    case auto
    case kbps(Int)

    static let allCases: [AudioBitrateChoice] = [
        .auto,
        .kbps(96),
        .kbps(128),
        .kbps(160),
        .kbps(192),
        .kbps(256),
        .kbps(320)
    ]

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case let .kbps(value): return "\(value)k"
        }
    }

    var kbps: Int? {
        switch self {
        case .auto: return nil
        case let .kbps(value): return value
        }
    }

    init(kbps: Int?) {
        guard let kbps else {
            self = .auto
            return
        }
        self = .kbps(kbps)
    }
}
