import AppKit
import SwiftUI

struct PresetOptionsPanelView: View {
    @EnvironmentObject private var queueStore: JobQueueStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @ObservedObject var viewModel: QueueViewModel
    let isSidebarVisible: Bool
    @State private var customWidthInput = "1920"
    @State private var customHeightInput = "1080"
    @State private var customFPSInput = "30"
    @State private var isCodecHelpPopoverPresented = false
    @State private var isSavePresetPresented = false
    @State private var presetNameInput = ""
    @State private var presetPendingDeletion: UserPreset?
    @StateObject private var sidebarFocusRouter = SidebarFocusRouter()
    @FocusState private var focusedField: FocusField?

    var body: some View {
        panelBody
    }

    private var panelBody: AnyView {
        AnyView(
            ScrollViewReader { proxy in
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .navigationTitle("Options")
                .background(Color.clear)
                .onAppear {
                    syncCustomInputsFromOptions()
                    refreshCustomValidationState()
                    normalizeVideoCodecSelection()
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.setSidebarVisible(isSidebarVisible)
                    sidebarFocusRouter.setCoarseScrollRequest { target, anchor in
                        let _ = anchor
                        if target == .presets {
                            withTransaction(Transaction(animation: nil)) {
                                proxy.scrollTo(target.scrollID, anchor: .center)
                            }
                            return
                        }
                        withTransaction(Transaction(animation: nil)) {
                            proxy.scrollTo(target.headerScrollID, anchor: .center)
                        }
                        DispatchQueue.main.async {
                            withTransaction(Transaction(animation: nil)) {
                                proxy.scrollTo(target.scrollID, anchor: .center)
                            }
                        }
                    }
                }
                .onDisappear {
                    sidebarFocusRouter.detach()
                }
                .onChange(of: viewModel.draftOptions.resolutionOverride) { _ in
                    syncCustomInputsFromOptions()
                    refreshCustomValidationState()
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    if resolutionChoiceBinding.wrappedValue != .custom {
                        sidebarFocusRouter.reconcileFocus(
                            reason: "Resolution custom removed",
                            preferredFallback: .resolution
                        )
                    } else {
                        sidebarFocusRouter.reconcileFocus(reason: "Resolution mode changed")
                    }
                    sidebarFocusRouter.invalidate()
                }
                .onChange(of: viewModel.draftOptions.frameRateOption) { _ in
                    syncCustomInputsFromOptions()
                    refreshCustomValidationState()
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    if fpsChoiceBinding.wrappedValue != .custom {
                        sidebarFocusRouter.reconcileFocus(
                            reason: "FPS custom removed",
                            preferredFallback: .fps
                        )
                    } else {
                        sidebarFocusRouter.reconcileFocus(reason: "FPS mode changed")
                    }
                    sidebarFocusRouter.invalidate()
                }
                .onChange(of: viewModel.draftOptions.audioCodec) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Audio codec changed",
                        preferredFallback: .audioCodec
                    )
                }
                .onChange(of: viewModel.draftOptions.enableHDRToSDR) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "HDR tone map availability changed",
                        preferredFallback: .hdrEnable
                    )
                }
                .onChange(of: settingsStore.encoderCapabilities) { _ in
                    normalizeVideoCodecSelection()
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                }
                .onChange(of: viewModel.isAdvancedExpanded) { _ in
                    if !viewModel.isAdvancedExpanded,
                       let focusedTarget = sidebarFocusRouter.currentFocusedTarget,
                       isAdvancedControlTarget(focusedTarget) {
                        sidebarFocusRouter.focus(.advancedHeader)
                    }
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Advanced visibility changed",
                        preferredFallback: .advancedHeader
                    )
                }
                .onChange(of: viewModel.selectedJobIDs) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(reason: "Selection changed")
                }
                .onChange(of: isSidebarVisible) { isVisible in
                    sidebarFocusRouter.setSidebarVisible(isVisible)
                }
                .onChange(of: focusedField) { field in
                    guard let field else { return }
                    switch field {
                    case .customWidth, .customHeight:
                        sidebarFocusRouter.activeTarget = field == .customWidth ? .resolutionCustomWidth : .resolutionCustomHeight
                    case .customFPS:
                        sidebarFocusRouter.activeTarget = .fpsCustomValue
                    case .renamePrefix:
                        sidebarFocusRouter.activeTarget = .renamePrefix
                    case .renameSuffix:
                        sidebarFocusRouter.activeTarget = .renameSuffix
                    case .renameReplace:
                        sidebarFocusRouter.activeTarget = .renameReplace
                    case .renameWith:
                        sidebarFocusRouter.activeTarget = .renameWith
                    case .videoBitrate:
                        sidebarFocusRouter.activeTarget = .advancedVideoBitrate
                    case .subtitleLanguage:
                        sidebarFocusRouter.activeTarget = .advancedSubtitleLanguage
                    case .customFFmpegArgs:
                        sidebarFocusRouter.activeTarget = .advancedCustomArgs
                    }
                }
                .sheet(isPresented: $isSavePresetPresented) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save Preset")
                            .font(.headline)
                        TextField("Preset name", text: $presetNameInput)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isSavePresetPresented = false
                            }
                            Button("Save") {
                                commitSavePreset()
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(presetNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .frame(width: 320)
                }
                .alert(
                    "Delete preset?",
                    isPresented: Binding(
                        get: { presetPendingDeletion != nil },
                        set: { isPresented in
                            if !isPresented {
                                presetPendingDeletion = nil
                            }
                        }
                    ),
                    presenting: presetPendingDeletion
                ) { preset in
                    Button("Delete", role: .destructive) {
                        viewModel.deleteUserPreset(id: preset.id)
                        presetPendingDeletion = nil
                    }
                    Button("Cancel", role: .cancel) {
                        presetPendingDeletion = nil
                    }
                } message: { preset in
                    Text("\"\(preset.name)\" will be removed.")
                }
            }
        )
    }

    private var presetsSection: AnyView {
        AnyView(
            Section("Presets") {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .presets,
                onKeyDown: handlePresetKey
            ) {
                HStack(spacing: 8) {
                    Menu {
                        Section("Built-in") {
                            ForEach(ConversionPreset.builtIns) { preset in
                                Button(preset.name) {
                                    viewModel.selectPreset(preset)
                                }
                            }
                        }
                        Section("Custom") {
                            Button(ConversionPreset.custom.name) {
                                viewModel.selectCustomPreset()
                            }
                        }
                        if !viewModel.userPresets.isEmpty {
                            Section("My Presets") {
                                ForEach(viewModel.userPresets) { preset in
                                    Button(preset.name) {
                                        viewModel.selectUserPreset(preset)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Save Current as Preset…") {
                            presetNameInput = draftSuggestedPresetName
                            isSavePresetPresented = true
                        }
                        if !viewModel.userPresets.isEmpty {
                            Menu("Delete My Preset") {
                                ForEach(viewModel.userPresets) { preset in
                                    Button(preset.name) {
                                        presetPendingDeletion = preset
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("Preset: \(activePresetDisplayName)")
                    }

                    Button("Save…") {
                        presetNameInput = draftSuggestedPresetName
                        isSavePresetPresented = true
                    }
                }
            }

            Text(viewModel.activePreset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.activePreset.tradeoff)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        )
    }

    private var defaultsSection: AnyView {
        AnyView(
            Section("Defaults") {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .chooseDefaultOutputFolder,
                onKeyDown: buttonKeyHandler {
                    settingsStore.chooseDefaultOutputDirectory()
                }
            ) {
                Button("Choose default output folder") {
                    settingsStore.chooseDefaultOutputDirectory()
                }
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .chooseOutputFolderForSelection,
                isEnabled: !viewModel.selectedJobIDs.isEmpty,
                onKeyDown: buttonKeyHandler {
                    queueStore.chooseOutputDirectory(for: viewModel.selectedJobIDs)
                }
            ) {
                Button(selectionOutputFolderTitle) {
                    queueStore.chooseOutputDirectory(for: viewModel.selectedJobIDs)
                }
                .disabled(viewModel.selectedJobIDs.isEmpty)
            }
            if let outputFolder = settingsStore.defaultOutputDirectoryURL {
                Text(outputFolder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            FocusableContainer(
                router: sidebarFocusRouter,
                target: .videoToolboxDefault,
                onKeyDown: toggleKeyHandler(settingsBinding(\.autoUseVideoToolbox))
            ) {
                Toggle("Use Apple VideoToolbox by default", isOn: settingsBinding(\.autoUseVideoToolbox))
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .allowOverwrite,
                onKeyDown: toggleKeyHandler(settingsBinding(\.allowOverwrite))
            ) {
                Toggle("Allow overwrite (off recommended)", isOn: settingsBinding(\.allowOverwrite))
            }
        }
        )
    }

    private var essentialsSection: AnyView {
        AnyView(
            Section("Essentials") {
            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .container)
                Text("Container")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .container,
                    onKeyDown: pillKeyHandler(options: OutputContainer.allCases, selection: containerBinding)
                ) {
                    WrappingPills(
                        options: OutputContainer.allCases,
                        selection: containerBinding,
                        title: { $0.fileExtension.uppercased() }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .videoCodec)
                Text("Video codec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .videoCodec,
                    onKeyDown: pillKeyHandler(options: allowedVideoCodecs, selection: optionsBinding(\.videoCodec))
                ) {
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
                if settingsStore.encoderCapabilities.missingModernVideoEncoders {
                    HStack(spacing: 8) {
                        Text("AV1/VP9 encoders not available in your FFmpeg build.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Button("How to fix") {
                            isCodecHelpPopoverPresented = true
                        }
                        .buttonStyle(.link)
                        .popover(isPresented: $isCodecHelpPopoverPresented, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Install or update FFmpeg")
                                    .font(.headline)
                                Text("brew install ffmpeg")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("If already installed, reinstall/update FFmpeg and verify encoders:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("ffmpeg -encoders | grep -E \"svtav1|aom|vpx-vp9\"")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Divider()
                                capabilityLine("libx264", available: settingsStore.encoderCapabilities.supportsX264)
                                capabilityLine("libx265", available: settingsStore.encoderCapabilities.supportsX265)
                                capabilityLine("libvpx-vp9", available: settingsStore.encoderCapabilities.supportsVP9)
                                capabilityLine("libsvtav1/libaom-av1", available: settingsStore.encoderCapabilities.supportsAV1)
                            }
                            .padding(12)
                            .frame(width: 360)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .quality)
                Text("Quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .quality,
                    onKeyDown: pillKeyHandler(options: QualityProfile.allCases, selection: optionsBinding(\.qualityProfile))
                ) {
                    WrappingPills(
                        options: QualityProfile.allCases,
                        selection: optionsBinding(\.qualityProfile),
                        title: { $0.displayName }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .resolution)
                Text("Resolution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .resolution,
                    onKeyDown: pillKeyHandler(options: resolutionChoices, selection: resolutionChoiceBinding)
                ) {
                    WrappingPills(
                        options: resolutionChoices,
                        selection: resolutionChoiceBinding,
                        title: { $0.label },
                        isDisabled: { _ in viewModel.draftOptions.isAudioOnly }
                    )
                }
            }

            if resolutionChoiceBinding.wrappedValue == .custom {
                HStack(spacing: 8) {
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .resolutionCustomWidth,
                        onFocusGained: { focusedField = .customWidth },
                        onKeyDown: { _ in false }
                    ) {
                        TextField("Width", text: $customWidthInput)
                            .focused($focusedField, equals: .customWidth)
                            .onChange(of: customWidthInput) { _ in applyCustomResolutionIfValid() }
                    }
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .resolutionCustomHeight,
                        onFocusGained: { focusedField = .customHeight },
                        onKeyDown: { _ in false }
                    ) {
                        TextField("Height", text: $customHeightInput)
                            .focused($focusedField, equals: .customHeight)
                            .onChange(of: customHeightInput) { _ in applyCustomResolutionIfValid() }
                    }
                }
                .onAppear { applyCustomResolutionIfValid() }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .fps)
                Text("FPS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .fps,
                    onKeyDown: pillKeyHandler(options: fpsChoices, selection: fpsChoiceBinding)
                ) {
                    WrappingPills(
                        options: fpsChoices,
                        selection: fpsChoiceBinding,
                        title: { $0.label },
                        isDisabled: { _ in viewModel.draftOptions.isAudioOnly }
                    )
                }
            }

            if fpsChoiceBinding.wrappedValue == .custom {
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .fpsCustomValue,
                    onFocusGained: { focusedField = .customFPS },
                    onKeyDown: { _ in false }
                ) {
                    TextField("Custom FPS", text: $customFPSInput)
                        .focused($focusedField, equals: .customFPS)
                        .onChange(of: customFPSInput) { _ in applyCustomFPSIfValid() }
                        .onAppear { applyCustomFPSIfValid() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .audioCodec)
                Text("Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .audioCodec,
                    onKeyDown: pillKeyHandler(options: [AudioCodec.copy, .aac, .mp3], selection: optionsBinding(\.audioCodec))
                ) {
                    WrappingPills(
                        options: [AudioCodec.copy, .aac, .mp3],
                        selection: optionsBinding(\.audioCodec),
                        title: { $0.displayName }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .audioBitrate)
                Text("Audio bitrate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .audioBitrate,
                    isEnabled: viewModel.draftOptions.audioCodec != .copy,
                    onKeyDown: pillKeyHandler(
                        options: AudioBitrateChoice.allCases,
                        selection: audioBitrateChoiceBinding,
                        isEnabled: { viewModel.draftOptions.audioCodec != .copy }
                    )
                ) {
                    WrappingPills(
                        options: AudioBitrateChoice.allCases,
                        selection: audioBitrateChoiceBinding,
                        title: { $0.displayName },
                        isDisabled: { _ in viewModel.draftOptions.audioCodec == .copy }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .audioChannels)
                Text("Audio channels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .audioChannels,
                    isEnabled: viewModel.draftOptions.audioCodec != .copy,
                    onKeyDown: pillKeyHandler(
                        options: AudioChannelChoice.allCases,
                        selection: audioChannelBinding,
                        isEnabled: { viewModel.draftOptions.audioCodec != .copy }
                    )
                ) {
                    WrappingPills(
                        options: AudioChannelChoice.allCases,
                        selection: audioChannelBinding,
                        title: { $0.displayName },
                        isDisabled: { _ in viewModel.draftOptions.audioCodec == .copy }
                    )
                }
            }

            if viewModel.draftOptions.audioCodec == .mp3,
               audioChannelBinding.wrappedValue == .surround71 {
                Text("MP3 does not reliably support 7.1. Output will be encoded as Stereo.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

        }
        )
    }

    private var subtitlesSection: AnyView {
        AnyView(
            Section("Subtitles") {
            VStack(alignment: .leading, spacing: 6) {
                headerAnchor(for: .subtitles)
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .subtitles,
                    onKeyDown: pillKeyHandler(options: SubtitleHandling.allCases, selection: subtitleModeBinding)
                ) {
                    WrappingPills(options: SubtitleHandling.allCases, selection: subtitleModeBinding, title: { $0.displayName })
                }
            }

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
        )
    }

    private var cleanupSection: AnyView {
        AnyView(
            Section("Cleanup") {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .cleanupMetadata,
                onKeyDown: toggleKeyHandler(optionsBinding(\.removeMetadata))
            ) {
                Toggle("Remove metadata", isOn: optionsBinding(\.removeMetadata))
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .cleanupChapters,
                onKeyDown: toggleKeyHandler(optionsBinding(\.removeChapters))
            ) {
                Toggle("Remove chapters", isOn: optionsBinding(\.removeChapters))
            }
        }
        )
    }

    private var hdrSection: AnyView {
        AnyView(
            Section("HDR → SDR") {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .hdrEnable,
                onKeyDown: toggleKeyHandler(optionsBinding(\.enableHDRToSDR))
            ) {
                Toggle("Enable tone map", isOn: optionsBinding(\.enableHDRToSDR))
                    .disabled(viewModel.draftOptions.isAudioOnly)
            }
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .hdrToneMap,
                    onKeyDown: toneMapKeyHandler
                ) {
                Picker("Tone map method", selection: optionsBinding(\.toneMapMode)) {
                    ForEach(ToneMapMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.draftOptions.enableHDRToSDR || viewModel.draftOptions.isAudioOnly)
            }
        }
        )
    }

    private var advancedSection: AnyView {
        AnyView(
            Section {
            DisclosureGroup(isExpanded: $viewModel.isAdvancedExpanded) {
                GroupBox("Binaries") {
                    VStack(alignment: .leading, spacing: 10) {
                        binaryRow(
                            title: "ffmpeg",
                            path: settingsStore.ffmpegURL?.path,
                            changeTarget: .advancedFFmpegChange,
                            resetTarget: .advancedFFmpegReset,
                            onChange: { settingsStore.chooseBinary(for: \.ffmpegBinaryPath) },
                            onReset: { settingsStore.resetBinaryToAuto(for: \.ffmpegBinaryPath) }
                        )
                        binaryRow(
                            title: "ffprobe",
                            path: settingsStore.ffprobeURL?.path,
                            changeTarget: .advancedFFprobeChange,
                            resetTarget: .advancedFFprobeReset,
                            onChange: { settingsStore.chooseBinary(for: \.ffprobeBinaryPath) },
                            onReset: { settingsStore.resetBinaryToAuto(for: \.ffprobeBinaryPath) }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .advancedVideoBitrate,
                    onFocusGained: { focusedField = .videoBitrate },
                    onKeyDown: { _ in false }
                ) {
                    TextField("Video bitrate override (kbps)", text: fieldBinding(viewModel.draftOptions.videoBitrateKbps) { newValue in
                        viewModel.updateOptions { $0.videoBitrateKbps = newValue }
                    })
                    .focused($focusedField, equals: .videoBitrate)
                }
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .advancedSubtitleLanguage,
                    onFocusGained: { focusedField = .subtitleLanguage },
                    onKeyDown: { _ in false }
                ) {
                    TextField("Subtitle language", text: subtitleLanguageBinding)
                        .focused($focusedField, equals: .subtitleLanguage)
                }

                VStack(alignment: .leading, spacing: 6) {
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .advancedCustomArgs,
                        onFocusGained: { focusedField = .customFFmpegArgs },
                        onKeyDown: { _ in false }
                    ) {
                        TextField("Custom FFmpeg Arguments (optional)", text: optionsBinding(\.customFFmpegArguments))
                            .focused($focusedField, equals: .customFFmpegArgs)
                    }
                    HStack(spacing: 10) {
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .advancedCustomArgsReset,
                            onKeyDown: buttonKeyHandler {
                                viewModel.updateOptions { $0.customFFmpegArguments = "" }
                            }
                        ) {
                            Button("Reset") {
                                viewModel.updateOptions { $0.customFFmpegArguments = "" }
                            }
                            .disabled(viewModel.draftOptions.customFFmpegArguments.isEmpty)
                        }
                    }
                    if let error = customArgumentValidation.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } label: {
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .advancedHeader,
                    onKeyDown: advancedHeaderKeyHandler
                ) {
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
        )
    }

    private var renameSection: AnyView {
        AnyView(
            Section("Rename") {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renamePrefix,
                onFocusGained: { focusedField = .renamePrefix },
                onKeyDown: { _ in false }
            ) {
                TextField("Prefix", text: renameFieldBinding(\.prefix))
                    .focused($focusedField, equals: .renamePrefix)
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renameSuffix,
                onFocusGained: { focusedField = .renameSuffix },
                onKeyDown: { _ in false }
            ) {
                TextField("Suffix", text: renameFieldBinding(\.suffix))
                    .focused($focusedField, equals: .renameSuffix)
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renameReplace,
                onFocusGained: { focusedField = .renameReplace },
                onKeyDown: { _ in false }
            ) {
                TextField("Replace", text: renameFieldBinding(\.replaceText))
                    .focused($focusedField, equals: .renameReplace)
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renameWith,
                onFocusGained: { focusedField = .renameWith },
                onKeyDown: { _ in false }
            ) {
                TextField("With", text: renameFieldBinding(\.replaceWith))
                    .focused($focusedField, equals: .renameWith)
            }
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renameSanitize,
                onKeyDown: toggleKeyHandler($viewModel.renameConfiguration.sanitizeFilename)
            ) {
                Toggle("Sanitize filenames", isOn: $viewModel.renameConfiguration.sanitizeFilename)
            }

            GroupBox("Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before: \(renamePreview.before)")
                    Text("After:  \(renamePreview.after)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FocusableContainer(
                router: sidebarFocusRouter,
                target: .renameApply,
                onKeyDown: buttonKeyHandler {
                    viewModel.applyRenamePreview()
                }
            ) {
                Button("Apply Rename") {
                    viewModel.applyRenamePreview()
                }
            }
        }
        )
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

    private var customArgumentValidation: FFmpegCommandBuilder.CustomArgumentsValidation {
        FFmpegCommandBuilder.validateCustomArguments(viewModel.draftOptions.customFFmpegArguments)
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

    private var selectionOutputFolderTitle: String {
        let count = viewModel.selectedJobIDs.count
        if count <= 1 {
            return "Choose output folder for selection"
        }
        return "Choose output folder for selected (\(count))"
    }

    private var focusOrder: [SidebarFocusTarget] {
        var order: [SidebarFocusTarget] = [
            .presets,
            .chooseDefaultOutputFolder,
            .chooseOutputFolderForSelection,
            .videoToolboxDefault,
            .allowOverwrite,
            .container,
            .videoCodec,
            .quality,
            .resolution,
            .fps,
            .audioCodec,
            .audioBitrate,
            .audioChannels,
            .subtitles,
            .cleanupMetadata,
            .cleanupChapters,
            .hdrEnable,
            .hdrToneMap,
            .advancedHeader,
            .renamePrefix,
            .renameSuffix,
            .renameReplace,
            .renameWith,
            .renameSanitize,
            .renameApply
        ]

        if resolutionChoiceBinding.wrappedValue == .custom,
           let resolutionIndex = order.firstIndex(of: .resolution) {
            order.insert(contentsOf: [.resolutionCustomWidth, .resolutionCustomHeight], at: resolutionIndex + 1)
        }

        if fpsChoiceBinding.wrappedValue == .custom,
           let fpsIndex = order.firstIndex(of: .fps) {
            order.insert(.fpsCustomValue, at: fpsIndex + 1)
        }

        if viewModel.isAdvancedExpanded {
            let advancedTargets: [SidebarFocusTarget] = [
                .advancedFFmpegChange,
                .advancedFFmpegReset,
                .advancedFFprobeChange,
                .advancedFFprobeReset,
                .advancedVideoBitrate,
                .advancedSubtitleLanguage,
                .advancedCustomArgs,
                .advancedCustomArgsReset
            ]
            if let headerIndex = order.firstIndex(of: .advancedHeader) {
                order.insert(contentsOf: advancedTargets, at: headerIndex + 1)
            }
        }

        return order
    }

    private func isAdvancedControlTarget(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case .advancedFFmpegChange,
             .advancedFFmpegReset,
             .advancedFFprobeChange,
             .advancedFFprobeReset,
             .advancedVideoBitrate,
             .advancedSubtitleLanguage,
             .advancedCustomArgs,
             .advancedCustomArgsReset:
            return true
        default:
            return false
        }
    }

    private func isFocusTargetEnabled(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case .chooseOutputFolderForSelection:
            return !viewModel.selectedJobIDs.isEmpty
        case .audioBitrate, .audioChannels:
            return viewModel.draftOptions.audioCodec != .copy
        case .hdrToneMap:
            return viewModel.draftOptions.enableHDRToSDR
        case .advancedFFmpegChange,
             .advancedFFmpegReset,
             .advancedFFprobeChange,
             .advancedFFprobeReset,
             .advancedVideoBitrate,
             .advancedSubtitleLanguage,
             .advancedCustomArgs,
             .advancedCustomArgsReset:
            return viewModel.isAdvancedExpanded
        default:
            return true
        }
    }

    private func advancedHeaderKeyHandler(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76, 49: // return/enter/space
            viewModel.isAdvancedExpanded.toggle()
            return true
        case 124: // right arrow
            if !viewModel.isAdvancedExpanded {
                viewModel.isAdvancedExpanded = true
            }
            return true
        case 123: // left arrow
            if viewModel.isAdvancedExpanded {
                viewModel.isAdvancedExpanded = false
            }
            return true
        default:
            return false
        }
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

    @ViewBuilder
    private func headerAnchor(for target: SidebarFocusTarget) -> some View {
        Color.clear
            .frame(height: 0)
            .id(target.headerScrollID)
            .accessibilityHidden(true)
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

    private func buttonKeyHandler(_ action: @escaping () -> Void) -> (NSEvent) -> Bool {
        { event in
            if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 { // return/enter/space
                action()
                return true
            }
            return false
        }
    }

    private func toggleKeyHandler(_ binding: Binding<Bool>) -> (NSEvent) -> Bool {
        { event in
            if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 || event.keyCode == 123 || event.keyCode == 124 {
                binding.wrappedValue.toggle()
                return true
            }
            return false
        }
    }

    private func handlePresetKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126:
            viewModel.selectAdjacentPreset(step: -1)
            return true
        case 124, 125:
            viewModel.selectAdjacentPreset(step: 1)
            return true
        case 36, 76, 49:
            return true
        default:
            return false
        }
    }

    private func toneMapKeyHandler(_ event: NSEvent) -> Bool {
        guard viewModel.draftOptions.enableHDRToSDR else { return false }
        let modes = ToneMapMode.allCases
        guard let index = modes.firstIndex(of: viewModel.draftOptions.toneMapMode) else { return false }
        switch event.keyCode {
        case 123, 126:
            viewModel.updateOptions { $0.toneMapMode = modes[max(0, index - 1)] }
            return true
        case 124, 125:
            viewModel.updateOptions { $0.toneMapMode = modes[min(modes.count - 1, index + 1)] }
            return true
        default:
            return false
        }
    }

    private func pillKeyHandler<Option: Equatable>(
        options: [Option],
        selection: Binding<Option>,
        isEnabled: @escaping () -> Bool = { true }
    ) -> (NSEvent) -> Bool {
        { event in
            guard isEnabled() else { return false }
            guard let index = options.firstIndex(of: selection.wrappedValue) else { return false }
            switch event.keyCode {
            case 123:
                selection.wrappedValue = options[max(0, index - 1)]
                return true
            case 124:
                selection.wrappedValue = options[min(options.count - 1, index + 1)]
                return true
            case 36, 76, 49:
                return true
            default:
                return false
            }
        }
    }

    private func renameFieldBinding(_ keyPath: WritableKeyPath<BatchRenameConfiguration, String>) -> Binding<String> {
        Binding(
            get: { viewModel.renameConfiguration[keyPath: keyPath] },
            set: { newValue in
                let sanitized = FilenameRenamer.normalizeInputField(
                    newValue,
                    sanitize: viewModel.renameConfiguration.sanitizeFilename,
                    fieldKind: keyPath == \.replaceText ? .searchPattern : .filenameComponent
                )
                viewModel.renameConfiguration[keyPath: keyPath] = sanitized
            }
        )
    }

    @ViewBuilder
    private func binaryRow(
        title: String,
        path: String?,
        changeTarget: SidebarFocusTarget,
        resetTarget: SidebarFocusTarget,
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
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: changeTarget,
                    onKeyDown: buttonKeyHandler(onChange)
                ) {
                    Button("Change…", action: onChange)
                }
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: resetTarget,
                    onKeyDown: buttonKeyHandler(onReset)
                ) {
                    Button("Reset to Auto", action: onReset)
                }
            }
        }
    }

    private var draftSuggestedPresetName: String {
        if activePresetDisplayName == ConversionPreset.custom.name {
            return "My Preset"
        }
        return "\(activePresetDisplayName) Copy"
    }

    private func commitSavePreset() {
        let trimmed = presetNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCurrentAsUserPreset(named: trimmed)
        isSavePresetPresented = false
        presetNameInput = ""
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

    @ViewBuilder
    private func capabilityLine(_ name: String, available: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .orange)
            Text(name)
                .font(.caption)
            Spacer()
        }
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

private enum FocusField: Hashable {
    case customWidth
    case customHeight
    case customFPS
    case videoBitrate
    case subtitleLanguage
    case customFFmpegArgs
    case renamePrefix
    case renameSuffix
    case renameReplace
    case renameWith
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
    case surround71

    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .surround51: return "5.1"
        case .surround71: return "7.1"
        }
    }

    var channelCount: Int? {
        switch self {
        case .keep: return nil
        case .mono: return 1
        case .stereo: return 2
        case .surround51: return 6
        case .surround71: return 8
        }
    }

    init(channelCount: Int?) {
        switch channelCount {
        case 1: self = .mono
        case 2: self = .stereo
        case 6: self = .surround51
        case 8: self = .surround71
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
