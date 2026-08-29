import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetOptionsPanelView: View {
    @EnvironmentObject private var queueStore: JobQueueStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var commandHandler: AppCommandHandler

    @ObservedObject var viewModel: QueueViewModel
    let isSidebarVisible: Bool
    @State private var customWidthInput = "1920"
    @State private var customHeightInput = "1080"
    @State private var customFPSInput = "30"
    @State private var isCodecHelpPopoverPresented = false
    @State private var isSavePresetPresented = false
    @State private var isPresetLibraryPresented = false
    @State private var presetNameInput = ""
    @State private var presetPendingDeletion: UserPreset?
    @State private var isMoreSettingsExpanded = false
    @State private var isRenameExpanded = false
    @State private var isDefaultOutputFolderDropTargeted = false
    @State private var isSelectionOutputFolderDropTargeted = false
    @State private var isToneMapSupportHelpPresented = false
    @StateObject private var sidebarFocusRouter = SidebarFocusRouter()
    @FocusState private var focusedField: FocusField?

    private let customCommandExampleTemplate =
        "ffmpeg -hide_banner -i \"{input}\" -c:v libx264 -preset medium -crf 21 \"{output}\""

    var body: some View {
        panelBody
    }

    private var panelBody: AnyView {
        AnyView(
            ScrollViewReader { proxy in
                List {
                    presetsSection
                    simpleDefaultsSection
                    if isMoreSettingsExpanded {
                        moreSettingsContentSection
                    }
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .navigationTitle("Options")
                .background(Color.clear)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    pinnedSidebarActions
                }
                .onAppear {
                    syncCustomInputsFromOptions()
                    refreshCustomValidationState()
                    normalizeVideoCodecSelection()
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.setSidebarVisible(isSidebarVisible)
                    commandHandler.onToggleMoreSettings = {
                        isMoreSettingsExpanded.toggle()
                    }
                    sidebarFocusRouter.setCoarseScrollRequest { target, anchor in
                        let _ = anchor
                        if isPresetHeaderTarget(target) {
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
                    commandHandler.onToggleMoreSettings = {}
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
                .onChange(of: viewModel.draftOptions.container) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Container changed",
                        preferredFallback: .container
                    )
                }
                .onChange(of: viewModel.draftOptions.videoCodec) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Video codec changed",
                        preferredFallback: .videoCodec
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
                .onChange(of: settingsStore.filterCapabilities) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Tone mapping capabilities changed",
                        preferredFallback: viewModel.draftOptions.enableHDRToSDR ? .hdrToneMappingEngine : .hdrEnable
                    )
                }
                .onChange(of: settingsStore.avconvertCapabilities) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Apple tone mapping availability changed",
                        preferredFallback: viewModel.draftOptions.enableHDRToSDR ? .hdrToneMappingEngine : .hdrEnable
                    )
                }
                .onChange(of: settingsStore.settings.preferredToneMappingBackendRawValue) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Tone mapping engine changed",
                        preferredFallback: viewModel.draftOptions.enableHDRToSDR ? .hdrToneMappingEngine : .hdrEnable
                    )
                }
                .onChange(of: viewModel.isAdvancedExpanded) { _ in
                    if !viewModel.isAdvancedExpanded,
                       let focusedTarget = sidebarFocusRouter.currentFocusedTarget,
                       isAdvancedControlTarget(focusedTarget) {
                        sidebarFocusRouter.focus(.advancedTogglePill)
                    }
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Advanced visibility changed",
                        preferredFallback: .advancedTogglePill
                    )
                }
                .onChange(of: viewModel.draftOptions.isCustomCommandEnabled) { enabled in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    if !enabled,
                       sidebarFocusRouter.currentFocusedTarget == .advancedCustomCommandTemplate {
                        sidebarFocusRouter.focus(.advancedCustomCommandToggle)
                    }
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Custom command visibility changed",
                        preferredFallback: .advancedCustomCommandToggle
                    )
                }
                .onChange(of: isMoreSettingsExpanded) { _ in
                    if !isMoreSettingsExpanded,
                       let focusedTarget = sidebarFocusRouter.currentFocusedTarget,
                       isMoreSettingsChildTarget(focusedTarget) {
                        sidebarFocusRouter.focus(.moreSettingsTogglePill)
                    }
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "More Settings visibility changed",
                        preferredFallback: .moreSettingsTogglePill
                    )
                }
                .onChange(of: isRenameExpanded) { _ in
                    if !isRenameExpanded,
                       let focusedTarget = sidebarFocusRouter.currentFocusedTarget,
                       isRenameControlTarget(focusedTarget) {
                        sidebarFocusRouter.focus(.renameTogglePill)
                    }
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Rename visibility changed",
                        preferredFallback: .renameTogglePill
                    )
                }
                .onChange(of: viewModel.draftOptions.externalAudioAttachments.map(\.id)) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "External audio visibility changed",
                        preferredFallback: .externalAudioAdd
                    )
                }
                .onChange(of: viewModel.draftOptions.subtitleAttachments.map(\.id)) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Subtitle attachment visibility changed",
                        preferredFallback: subtitleMode == .addExternal ? .subtitleAdd : .subtitles
                    )
                }
                .onChange(of: viewModel.selectedJobIDs) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(reason: "Selection changed")
                }
                .onChange(of: settingsStore.defaultOutputDirectoryURL) { _ in
                    sidebarFocusRouter.configureOrder(focusOrder, logicalIsEnabled: isFocusTargetEnabled)
                    sidebarFocusRouter.reconcileFocus(
                        reason: "Default output folder availability changed",
                        preferredFallback: .chooseDefaultOutputFolder
                    )
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
                    case let .subtitleLanguage(id):
                        sidebarFocusRouter.activeTarget = .subtitleLanguage(id)
                    case .customFFmpegArgs:
                        sidebarFocusRouter.activeTarget = .advancedCustomCommandTemplate
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
                VStack(alignment: .leading, spacing: 9) {
                    sidebarReadableText(
                        "Pick a preset, then start. Open More Settings only when you need to fine-tune it.",
                        font: .caption,
                        color: .secondary
                    )

                    VStack(spacing: 7) {
                        ForEach(primaryPresetCards) { card in
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .presetCard(card.presetName),
                                onKeyDown: presetCardKeyHandler(card)
                            ) {
                                Button {
                                    viewModel.selectPreset(named: card.presetName)
                                } label: {
                                    presetCard(for: card)
                                }
                                .buttonStyle(.plain)
                                .disabled(isPrimaryPresetUnavailable(card))
                                .help(primaryPresetHelpText(card))
                            }
                        }
                    }

                    if shouldShowCurrentPresetStatus {
                        currentPresetStatusCard
                    }

                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .morePresets,
                        onKeyDown: buttonKeyHandler {
                            isPresetLibraryPresented.toggle()
                        }
                    ) {
                        Button {
                            isPresetLibraryPresented.toggle()
                        } label: {
                            pillActionButtonLabel(
                                "More Presets",
                                systemImage: "slider.horizontal.3",
                                prominence: .secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isPresetLibraryPresented, arrowEdge: .bottom) {
                            presetLibraryPopover
                        }
                    }
                }
                .help("Pick a starting preset. Manual changes keep the preset selected until the export no longer matches it.")
            }
        )
    }

    private var simpleDefaultsSection: AnyView {
        AnyView(
            Section("Output") {
                outputSummaryView

                outputActionCardContainer(
                    isDropTargeted: isDefaultOutputFolderDropTargeted
                ) {
                    HStack(alignment: .center, spacing: 10) {
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .chooseDefaultOutputFolder,
                            onKeyDown: buttonKeyHandler {
                                settingsStore.chooseDefaultOutputDirectory()
                                queueStore.applyDefaultOutputDirectoryToUnsetJobs()
                            }
                        ) {
                            Button {
                                settingsStore.chooseDefaultOutputDirectory()
                                queueStore.applyDefaultOutputDirectoryToUnsetJobs()
                            } label: {
                                outputActionCardContent(
                                    title: "Choose default folder",
                                    subtitle: "Click or drop a folder for new exports.",
                                    systemImage: "folder"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .resetDefaultOutputFolder,
                                isEnabled: settingsStore.defaultOutputDirectoryURL != nil,
                                onKeyDown: buttonKeyHandler {
                                    settingsStore.resetDefaultOutputDirectory()
                                }
                            ) {
                                SidebarPillButton(
                                    systemImage: "arrow.uturn.left",
                                    accessibilityLabel: "Use source folder",
                                    compact: true,
                                    action: {
                                        settingsStore.resetDefaultOutputDirectory()
                                    }
                                )
                                .disabled(settingsStore.defaultOutputDirectoryURL == nil)
                                .help("Use source folder (save next to input)")
                            }

                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .revealDefaultOutputFolder,
                                isEnabled: settingsStore.defaultOutputDirectoryURL != nil,
                                onKeyDown: buttonKeyHandler {
                                    revealDefaultOutputFolder()
                                }
                            ) {
                                SidebarPillButton(
                                    systemImage: "folder",
                                    accessibilityLabel: "Reveal output folder in Finder",
                                    compact: true,
                                    action: {
                                        revealDefaultOutputFolder()
                                    }
                                )
                                .disabled(settingsStore.defaultOutputDirectoryURL == nil)
                                .help(
                                    settingsStore.defaultOutputDirectoryURL == nil
                                        ? "Choose a default folder first."
                                        : "Reveal output folder in Finder"
                                )
                            }
                        }
                    }
                }
                .onDrop(
                    of: folderDropTypeIdentifiers,
                    isTargeted: $isDefaultOutputFolderDropTargeted,
                    perform: handleDefaultOutputFolderDrop
                )
                .help("Choose or drop a folder for new exports. Leave it empty to save beside each source file.")

                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .chooseOutputFolderForSelection,
                    isEnabled: !viewModel.selectedJobIDs.isEmpty,
                    onKeyDown: buttonKeyHandler {
                        queueStore.chooseOutputDirectory(for: viewModel.selectedJobIDs)
                    }
                ) {
                    Button {
                        queueStore.chooseOutputDirectory(for: viewModel.selectedJobIDs)
                    } label: {
                        outputActionButtonLabel(
                            title: "Choose folder for selection",
                            subtitle: viewModel.selectedJobIDs.isEmpty
                                ? "Select queue items first."
                                : "Click or drop a folder for the selected item" + (viewModel.selectedJobIDs.count == 1 ? "." : "s."),
                            systemImage: "folder",
                            isDropTargeted: isSelectionOutputFolderDropTargeted,
                            isEnabled: !viewModel.selectedJobIDs.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedJobIDs.isEmpty)
                    .onDrop(
                        of: selectionFolderDropTypeIdentifiers,
                        isTargeted: $isSelectionOutputFolderDropTargeted,
                        perform: handleSelectionOutputFolderDrop
                    )
                }
                .help("Select one or more items in the queue to set an output folder for them.")
            }
        )
    }

    private var pinnedSidebarActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            FocusableContainer(
                router: sidebarFocusRouter,
                target: .startConversion,
                isEnabled: !sidebarStartDisabled,
                onKeyDown: buttonKeyHandler {
                    queueStore.startOrResume(selectedJobIDs: viewModel.selectedJobIDs)
                }
            ) {
                Button {
                    queueStore.startOrResume(selectedJobIDs: viewModel.selectedJobIDs)
                } label: {
                    primarySidebarActionLabel(
                        queueStore.startButtonTitle(selectedJobIDs: viewModel.selectedJobIDs),
                        systemImage: queueStore.startButtonTitle(selectedJobIDs: viewModel.selectedJobIDs) == "Resume"
                            ? "arrow.clockwise"
                            : "play.fill"
                    )
                }
                .disabled(sidebarStartDisabled)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sidebarReadableText(startActionSummary, font: .caption, color: startActionSummaryColor)

            HStack(spacing: 8) {
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .moreSettingsTogglePill,
                    onKeyDown: toggleSectionKeyHandler($isMoreSettingsExpanded)
                ) {
                    Button {
                        isMoreSettingsExpanded.toggle()
                    } label: {
                        sectionTogglePill(
                            title: isMoreSettingsExpanded ? "Less Settings" : "More Settings",
                            isExpanded: isMoreSettingsExpanded
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let moreSettingsStatusLabel {
                    statusPill(title: moreSettingsStatusLabel, color: .orange)
                }

                HelpPopoverButton(topic: .moreSettings)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private var moreSettingsContentSection: AnyView {
        AnyView(
            Section("More Settings") {
                VStack(alignment: .leading, spacing: 14) {
                    formatAndQualitySettings
                    videoSettings
                    audioSettings
                    subtitleSettings
                    outputBehaviorSettings
                    renameToolsSection
                    advancedToolsSection
                }
            }
        )
    }

    private var formatAndQualitySettings: some View {
        GroupBox("Format & Quality") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .container)
                    HStack(spacing: 6) {
                        Text("Container")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .container)
                    }
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
                .help("Choose the output file type. MP4 is most compatible, MOV suits editing, and MKV is most flexible.")

                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .videoCodec)
                    HStack(spacing: 6) {
                        Text("Video codec")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .videoCodec)
                    }
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
                    .help("Choose the video encoder. Availability depends on the selected container and your FFmpeg build.")

                    if settingsStore.encoderCapabilities.missingModernVideoEncoders {
                        HStack(spacing: 8) {
                            sidebarReadableText(
                                "AV1/VP9 encoders not available in your FFmpeg build.",
                                font: .caption2,
                                color: .orange
                            )
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .videoCodecHelp,
                                onKeyDown: buttonKeyHandler {
                                    isCodecHelpPopoverPresented = true
                                }
                            ) {
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
                                        sidebarReadableText(
                                            "If already installed, reinstall/update FFmpeg and verify encoders:",
                                            font: .caption,
                                            color: .secondary
                                        )
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
                }

                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .quality)
                    HStack(spacing: 6) {
                        Text("Quality")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .quality)
                    }
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
                .help("Smaller saves space, Balanced is the default, and Better keeps more detail.")

                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .encoderOptions)
                    HStack(spacing: 6) {
                        Text("Encoder options")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .encoderOptions)
                    }
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .encoderOptions,
                        isEnabled: viewModel.draftOptions.videoCodec != .proRes,
                        onKeyDown: pillKeyHandler(
                            options: EncoderChoice.allCases,
                            selection: encoderChoiceBinding,
                            isEnabled: { viewModel.draftOptions.videoCodec != .proRes }
                        )
                    ) {
                        WrappingPills(
                            options: EncoderChoice.allCases,
                            selection: encoderChoiceBinding,
                            title: { $0.displayName },
                            isDisabled: { _ in viewModel.draftOptions.videoCodec == .proRes }
                        )
                    }

                    if viewModel.draftOptions.encoderOption == nil {
                        Text("Auto currently uses \(viewModel.draftOptions.effectiveEncoderOption.displayName).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.draftOptions.videoCodec == .proRes {
                        Text("ProRes ignores encoder speed presets.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Trade speed for efficiency. Slower encodes usually make smaller files at the same quality.")

                HStack(alignment: .center, spacing: 8) {
                    Text("Use Apple VideoToolbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .videoToolboxDefault,
                        onKeyDown: toggleKeyHandler(settingsBinding(\.autoUseVideoToolbox))
                    ) {
                        BinaryPillToggle(isOn: settingsBinding(\.autoUseVideoToolbox))
                    }
                }
                .help("Use Apple's hardware encoder by default for H.264 and HEVC when it fits the chosen preset.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var videoSettings: some View {
        GroupBox("Video") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .resolution)
                    HStack(spacing: 6) {
                        Text("Resolution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .resolution)
                    }
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
                .help("Keep the current resolution or scale to a common output size.")

                if resolutionChoiceBinding.wrappedValue == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Custom size")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .resolutionCustomSize)
                        }

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
                    }
                    .onAppear { applyCustomResolutionIfValid() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .fps)
                    HStack(spacing: 6) {
                        Text("FPS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .fps)
                    }
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
                .help("Keep the current frame rate or convert to a common playback rate.")

                if fpsChoiceBinding.wrappedValue == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Custom FPS")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .fpsCustom)
                        }

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
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Tone map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .hdrEnable,
                                onKeyDown: toggleKeyHandler(optionsBinding(\.enableHDRToSDR))
                            ) {
                                BinaryPillToggle(
                                    isOn: optionsBinding(\.enableHDRToSDR),
                                    isDisabled: !toneMappingToggleEnabled
                                )
                            }
                            HelpPopoverButton(topic: .hdrToSDR)
                            if !toneMappingControlsAvailable {
                                Button {
                                    isToneMapSupportHelpPresented = true
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                                .help("Why HDR tone mapping is unavailable")
                                .popover(isPresented: $isToneMapSupportHelpPresented, arrowEdge: .trailing) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("HDR tone mapping unavailable")
                                            .font(.headline)
                                        sidebarReadableText(
                                            toneMappingUnavailableMessage,
                                            font: .callout,
                                            color: .secondary
                                        )
                                    }
                                    .padding(14)
                                    .frame(width: 320, alignment: .leading)
                                }
                            }
                        }
                        if viewModel.draftOptions.enableHDRToSDR {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tone mapping engine")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                FocusableContainer(
                                    router: sidebarFocusRouter,
                                    target: .hdrToneMappingEngine,
                                    onKeyDown: toneMappingEngineKeyHandler
                                ) {
                                    WrappingPills(
                                        options: ToneMappingBackend.allCases,
                                        selection: toneMappingEngineBinding,
                                        title: { $0.displayName },
                                        isDisabled: isToneMappingEngineDisabled,
                                        helpText: toneMappingEngineHelpText
                                    )
                                }

                                if let toneMappingEngineWarning {
                                    sidebarReadableText(toneMappingEngineWarning, font: .caption2, color: .orange)
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            Text("Tone map method")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .toneMapMethod)
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
                            .disabled(
                                !viewModel.draftOptions.enableHDRToSDR ||
                                viewModel.draftOptions.isAudioOnly ||
                                !toneMappingControlsAvailable ||
                                toneMappingUsesApplePipeline
                            )
                            .help("Choose how HDR highlights are compressed into SDR.")
                        }

                        if let toneMappingNote {
                            sidebarReadableText(toneMappingNote, font: .caption2, color: .secondary)
                        }

                        if !toneMappingControlsAvailable {
                            sidebarReadableText(
                                toneMappingUnavailableMessage,
                                font: .caption2,
                                color: .orange
                            )
                        }
                    }
                } label: {
                    Text("HDR → SDR")
                }
                .help("Convert HDR sources to SDR when you need wider playback compatibility.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var audioSettings: some View {
        GroupBox("Audio") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .audioCodec)
                    HStack(spacing: 6) {
                        Text("Audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .audio)
                    }
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
                .help("Keep the source audio or re-encode it to AAC or MP3.")

                if viewModel.draftOptions.audioCodec == .copy {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Audio bitrate / channels")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .audioLocked)
                        }
                        Text("Locked (Copy audio)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        headerAnchor(for: .audioBitrate)
                        HStack(spacing: 6) {
                            Text("Audio bitrate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .audioBitrate)
                        }
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .audioBitrate,
                            onKeyDown: pillKeyHandler(
                                options: AudioBitrateChoice.allCases,
                                selection: audioBitrateChoiceBinding
                            )
                        ) {
                            WrappingPills(
                                options: AudioBitrateChoice.allCases,
                                selection: audioBitrateChoiceBinding,
                                title: { $0.displayName }
                            )
                        }
                    }
                    .help("Set a fixed audio bitrate, or leave it on Auto when re-encoding audio.")

                    VStack(alignment: .leading, spacing: 6) {
                        headerAnchor(for: .audioChannels)
                        HStack(spacing: 6) {
                            Text("Audio channels")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HelpPopoverButton(topic: .audioChannels)
                        }
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .audioChannels,
                            onKeyDown: pillKeyHandler(
                                options: AudioChannelChoice.allCases,
                                selection: audioChannelBinding
                            )
                        ) {
                            WrappingPills(
                                options: AudioChannelChoice.allCases,
                                selection: audioChannelBinding,
                                title: { $0.displayName }
                            )
                        }
                    }
                    .help("Keep the original channel layout or force mono, stereo, 5.1, or 7.1 output.")
                }

                if viewModel.draftOptions.audioCodec == .mp3,
                   audioChannelBinding.wrappedValue == .surround71 {
                    sidebarReadableText(
                        "MP3 does not reliably support 7.1. Output will be encoded as Stereo.",
                        font: .caption2,
                        color: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .externalAudioAdd)
                    HStack(spacing: 6) {
                        Text("External audio tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .externalAudio)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Format")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .audioCodec,
                            onKeyDown: pillKeyHandler(
                                options: AudioCodec.externalTrackChoices,
                                selection: optionsBinding(\.audioCodec)
                            )
                        ) {
                            WrappingPills(
                                options: AudioCodec.externalTrackChoices,
                                selection: optionsBinding(\.audioCodec),
                                title: { $0.displayName }
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .externalAudioAdd,
                            onKeyDown: buttonKeyHandler {
                                chooseExternalAudioTracks()
                            }
                        ) {
                            SidebarPillButton(
                                title: viewModel.draftOptions.externalAudioAttachments.isEmpty ? "Add Audio Tracks" : "Add More Audio",
                                systemImage: "waveform.badge.plus",
                                action: {
                                    chooseExternalAudioTracks()
                                }
                            )
                        }

                        if !viewModel.draftOptions.externalAudioAttachments.isEmpty {
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .externalAudioClear,
                                onKeyDown: buttonKeyHandler {
                                    clearExternalAudioTracks()
                                }
                            ) {
                                Button {
                                    clearExternalAudioTracks()
                                } label: {
                                    pillActionButtonLabel("Clear All", systemImage: "trash", prominence: .subtle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sidebarReadableText(
                        "These tracks replace the source audio. Their order here becomes the output order.",
                        font: .caption2,
                        color: .secondary
                    )

                    if !viewModel.draftOptions.externalAudioAttachments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(viewModel.draftOptions.externalAudioAttachments.enumerated()), id: \.element.id) { index, attachment in
                                attachmentRow(
                                    index: index,
                                    title: attachment.fileURL.lastPathComponent,
                                    subtitle: "Track \(index + 1)",
                                    removeTarget: .externalAudioRemove(attachment.id),
                                    removeAction: { removeExternalAudioTrack(attachment.id) }
                                )
                            }
                        }
                    }

                    if let error = externalAudioValidationMessage {
                        sidebarReadableText(error, font: .caption2, color: .red)
                    }
                }
                .help("Add one or more external audio tracks. ForgeFF uses them in this order and replaces the source audio.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitleSettings: some View {
        GroupBox("Subtitles") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    headerAnchor(for: .subtitles)
                    HStack(spacing: 6) {
                        Text("Subtitles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .subtitles)
                    }
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .subtitles,
                        onKeyDown: pillKeyHandler(options: SubtitleHandling.allCases, selection: subtitleModeBinding)
                    ) {
                        WrappingPills(
                            options: SubtitleHandling.allCases,
                            selection: subtitleModeBinding,
                            title: { $0.displayName }
                        )
                    }
                }
                .help("Keep embedded subtitles, remove them, or add one or more external subtitle files.")

                if subtitleMode == .addExternal {
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .subtitleAdd,
                        onKeyDown: buttonKeyHandler {
                            addExternalSubtitleTracks()
                        }
                    ) {
                        Button {
                            addExternalSubtitleTracks()
                        } label: {
                            pillActionButtonLabel(
                                viewModel.draftOptions.subtitleAttachments.isEmpty ? "Add Subtitle Files" : "Add More Subtitles",
                                systemImage: "captions.bubble"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .help("Pick one or more subtitle files to mux into the output.")

                    if !viewModel.draftOptions.subtitleAttachments.isEmpty {
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .subtitleClear,
                            onKeyDown: buttonKeyHandler {
                                applySubtitleMode(.keep)
                            }
                        ) {
                            Button {
                                applySubtitleMode(.keep)
                            } label: {
                                pillActionButtonLabel("Clear Subtitles", systemImage: "trash", prominence: .subtle)
                            }
                            .buttonStyle(.plain)
                        }
                        .help("Remove all external subtitle files and return to the default subtitle handling.")

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(viewModel.draftOptions.subtitleAttachments.enumerated()), id: \.element.id) { index, subtitle in
                                subtitleAttachmentRow(index: index, attachment: subtitle)
                            }
                        }
                    }

                    if let warning = subtitleCompatibilityMessage {
                        sidebarReadableText(warning, font: .caption2, color: .orange)
                    }

                    if let error = subtitleValidationMessage {
                        sidebarReadableText(error, font: .caption2, color: .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outputBehaviorSettings: some View {
        GroupBox("Output & Cleanup") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Overwrite existing files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .allowOverwrite,
                        onKeyDown: toggleKeyHandler(settingsBinding(\.allowOverwrite))
                    ) {
                        BinaryPillToggle(isOn: settingsBinding(\.allowOverwrite))
                    }
                    HelpPopoverButton(topic: .overwrite)
                }
                .help("Overwrite existing output files instead of creating numbered copies.")

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Remove metadata")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .cleanupMetadata,
                                onKeyDown: toggleKeyHandler(optionsBinding(\.removeMetadata))
                            ) {
                                BinaryPillToggle(isOn: optionsBinding(\.removeMetadata))
                            }
                        }

                        HStack(alignment: .center, spacing: 8) {
                            Text("Remove chapters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            FocusableContainer(
                                router: sidebarFocusRouter,
                                target: .cleanupChapters,
                                onKeyDown: toggleKeyHandler(optionsBinding(\.removeChapters))
                            ) {
                                BinaryPillToggle(isOn: optionsBinding(\.removeChapters))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Cleanup")
                        HelpPopoverButton(topic: .cleanup)
                    }
                }
                .help("Strip metadata and chapters from the output file when you want a cleaner export.")

                HStack(alignment: .center, spacing: 8) {
                    Text("Web optimization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .webOptimization,
                        isEnabled: viewModel.draftOptions.isWebOptimizationAvailable,
                        onKeyDown: toggleKeyHandler(optionsBinding(\.webOptimization))
                    ) {
                        BinaryPillToggle(
                            isOn: optionsBinding(\.webOptimization),
                            isDisabled: !viewModel.draftOptions.isWebOptimizationAvailable
                        )
                    }
                    HelpPopoverButton(topic: .webOptimization)
                }
                .help(webOptimizationHelpText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var renameToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .renameTogglePill,
                    onKeyDown: toggleSectionKeyHandler($isRenameExpanded)
                ) {
                    Button {
                        isRenameExpanded.toggle()
                    } label: {
                        sectionTogglePill(title: "Rename", isExpanded: isRenameExpanded)
                    }
                    .buttonStyle(.plain)
                }

                HelpPopoverButton(topic: .rename)
            }

            if isRenameExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Rename fields")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpPopoverButton(topic: .renameFields)
                    }
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
                        HStack(alignment: .center, spacing: 8) {
                            Text("Sanitize filenames")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            BinaryPillToggle(isOn: $viewModel.renameConfiguration.sanitizeFilename)
                        }
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
                        SidebarPillButton(
                            title: "Apply Rename",
                            systemImage: "textformat.abc",
                            action: {
                                viewModel.applyRenamePreview()
                            }
                        )
                    }
                }
            }
        }
        .help("Apply the same prefix, suffix, replace, and sanitize rules across the queue.")
    }

    private var advancedToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: .advancedTogglePill,
                    onKeyDown: toggleSectionKeyHandler(advancedExpandedBinding)
                ) {
                    Button {
                        viewModel.isAdvancedExpanded.toggle()
                    } label: {
                        sectionTogglePill(title: "Advanced", isExpanded: viewModel.isAdvancedExpanded)
                    }
                    .buttonStyle(.plain)
                }

                HelpPopoverButton(topic: .advanced)

                if viewModel.isAdvancedModified {
                    statusPill(title: "Modified", color: .orange)
                }
            }

            if viewModel.isAdvancedExpanded {
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

                if !viewModel.draftOptions.subtitleAttachments.isEmpty {
                    Text("Edit subtitle languages in the Subtitles section above.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Use custom FFmpeg command")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .advancedCustomCommandToggle,
                            onKeyDown: toggleKeyHandler(customCommandEnabledBinding)
                        ) {
                            BinaryPillToggle(isOn: customCommandEnabledBinding)
                        }
                        HelpPopoverButton(topic: .customFFmpegCommand)
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .advancedCustomCommandInsertExample,
                            onKeyDown: buttonKeyHandler(insertCustomCommandExample)
                        ) {
                            Button(action: insertCustomCommandExample) {
                                pillActionButtonLabel("Insert Example", systemImage: "doc.badge.plus", prominence: .subtle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .help("Override ForgeFF's generated ffmpeg command for the selected queue items.")

                    Text(viewModel.draftOptions.isCustomCommandEnabled ? "Custom FFmpeg command template" : "Stored custom command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FocusableContainer(
                        router: sidebarFocusRouter,
                        target: .advancedCustomCommandTemplate,
                        isEnabled: viewModel.draftOptions.isCustomCommandEnabled,
                        onFocusGained: { focusedField = .customFFmpegArgs },
                        onKeyDown: { _ in false }
                    ) {
                        TextEditor(text: customCommandTemplateBinding)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 108)
                            .focused($focusedField, equals: .customFFmpegArgs)
                            .disabled(!viewModel.draftOptions.isCustomCommandEnabled)
                            .opacity(viewModel.draftOptions.isCustomCommandEnabled ? 1 : 0.7)
                    }
                    .help("Use {input} and {output} placeholders. ForgeFF substitutes the real file paths safely.")
                    sidebarReadableText(
                        viewModel.draftOptions.isCustomCommandEnabled
                            ? "Required placeholders: {input} and {output}."
                            : "Stored text stays here, but it is inactive until you turn this override on.",
                        font: .caption2,
                        color: .secondary
                    )
                    sidebarReadableText(
                        "Example: ffmpeg -hide_banner -i \"{input}\" -c:v libx264 -preset medium -crf 21 \"{output}\"",
                        font: .caption2,
                        color: .secondary
                    )
                    .textSelection(.enabled)

                    HStack(spacing: 10) {
                        FocusableContainer(
                            router: sidebarFocusRouter,
                            target: .advancedCustomCommandReset,
                            onKeyDown: buttonKeyHandler {
                                viewModel.updateOptions {
                                    $0.isCustomCommandOverrideEnabled = false
                                    $0.customCommandTemplate = ""
                                }
                            }
                        ) {
                            Button {
                                viewModel.updateOptions {
                                    $0.isCustomCommandOverrideEnabled = false
                                    $0.customCommandTemplate = ""
                                }
                            } label: {
                                pillActionButtonLabel("Reset", systemImage: "arrow.counterclockwise", prominence: .subtle)
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.draftOptions.isCustomCommandEnabled && viewModel.draftOptions.effectiveCustomCommandTemplate.isEmpty)
                        }
                    }

                    if let error = customCommandValidation.errorMessage {
                        sidebarReadableText(error, font: .caption2, color: .red)
                    }
                }
            }
        }
    }

    private var presetLibraryPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                presetLibrarySection("Built-in") {
                    ForEach(ConversionPreset.builtIns) { preset in
                        presetLibraryButtonRow(preset.name) {
                            viewModel.selectPreset(preset)
                            isPresetLibraryPresented = false
                        }
                    }
                }

                presetLibrarySection("Custom") {
                    presetLibraryButtonRow(ConversionPreset.custom.name) {
                        viewModel.selectCustomPreset()
                        isPresetLibraryPresented = false
                    }
                }

                if !viewModel.userPresets.isEmpty {
                    presetLibrarySection("My Presets") {
                        ForEach(viewModel.userPresets) { preset in
                            presetLibraryButtonRow(preset.name) {
                                viewModel.selectUserPreset(preset)
                                isPresetLibraryPresented = false
                            }
                        }
                    }
                }

                Divider()

                presetLibraryButtonRow("Save Current as Preset…") {
                    presetNameInput = draftSuggestedPresetName
                    isSavePresetPresented = true
                    isPresetLibraryPresented = false
                }

                presetLibraryButtonRow("Import Presets…") {
                    importUserPresets()
                    isPresetLibraryPresented = false
                }

                presetLibraryButtonRow("Export Presets…") {
                    exportUserPresets()
                    isPresetLibraryPresented = false
                }

                if !viewModel.userPresets.isEmpty {
                    presetLibrarySection("Delete My Preset") {
                        ForEach(viewModel.userPresets) { preset in
                            presetLibraryButtonRow(preset.name, role: .destructive) {
                                presetPendingDeletion = preset
                                isPresetLibraryPresented = false
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 280)
        .frame(maxHeight: 380)
    }

    private var primaryPresetCards: [SidebarPrimaryPresetCard] {
        let cards = [
            SidebarPrimaryPresetCard(
                title: "Telegram",
                subtitle: "Reliable MP4 playback, source resolution and FPS.",
                presetName: ConversionPreset.telegramPresetName,
                icon: "paperplane.fill"
            ),
            SidebarPrimaryPresetCard(
                title: "Fast MP4 (H.264)",
                subtitle: "Fast, widely compatible export.",
                presetName: "MP4 — H.264 (Fast)",
                icon: "bolt.fill"
            ),
            SidebarPrimaryPresetCard(
                title: "Efficient HEVC",
                subtitle: "Telegram-style settings with smaller HEVC video.",
                presetName: ConversionPreset.efficientHEVCPresetName,
                icon: "sparkles"
            ),
            SidebarPrimaryPresetCard(
                title: "VP9",
                subtitle: "Efficient web and archive compression in MKV.",
                presetName: "MKV — VP9 (Balanced)",
                icon: "shippingbox.fill"
            ),
            SidebarPrimaryPresetCard(
                title: "AV1",
                subtitle: "Modern compression with the smallest output.",
                presetName: "MKV — AV1 (Balanced)",
                icon: "archivebox.fill"
            ),
            SidebarPrimaryPresetCard(
                title: "Editing ProRes",
                subtitle: "Large edit-ready files for finishing.",
                presetName: "MOV — ProRes 422 (Editing)",
                icon: "film.stack"
            )
        ]

        return cards
    }

    private var shouldShowCurrentPresetStatus: Bool {
        viewModel.isUsingCustomPreset ||
        viewModel.isPresetCustomized ||
        !primaryPresetCards.map(\.presetName).contains(viewModel.selectedPresetID)
    }

    private func isPrimaryPresetUnavailable(_ card: SidebarPrimaryPresetCard) -> Bool {
        guard let codec = ConversionPreset.builtIn(named: card.presetName)?.videoCodec else {
            return false
        }
        return isVideoCodecUnavailable(codec)
    }

    private func primaryPresetHelpText(_ card: SidebarPrimaryPresetCard) -> String {
        guard isPrimaryPresetUnavailable(card) else { return card.subtitle }
        return "\(card.title) is not available in the detected FFmpeg build."
    }

    private var currentPresetStatusCard: some View {
        presetCard(
            title: currentPresetStatusTitle,
            subtitle: currentPresetStatusSubtitle,
            icon: currentPresetStatusIcon,
            accentColor: currentPresetStatusAccentColor,
            isSelected: true,
            badgeTitle: currentPresetStatusBadge
        )
    }

    private var currentPresetStatusTitle: String {
        if viewModel.isUsingCustomPreset {
            return "Custom settings"
        }
        return activePresetDisplayName
    }

    private var currentPresetStatusSubtitle: String {
        if let modifiedBasePreset = viewModel.modifiedBasePreset {
            return "Based on \(modifiedBasePreset.name) with manual overrides in More Settings."
        }
        if viewModel.isUsingCustomPreset {
            return "Manual settings outside the quick preset cards. Save them if you want to reuse this setup."
        }
        if isActiveUserPreset {
            return "Saved preset from your library."
        }
        return viewModel.activePreset.summary
    }

    private var currentPresetStatusBadge: String? {
        if viewModel.isUsingCustomPreset {
            return "Custom"
        }
        return "Selected"
    }

    private var currentPresetStatusIcon: String {
        if viewModel.isUsingCustomPreset {
            return "slider.horizontal.3"
        }
        if isActiveUserPreset {
            return "bookmark.fill"
        }
        return presetIcon(for: viewModel.activePreset)
    }

    private var currentPresetStatusAccentColor: Color {
        return .accentColor
    }

    @ViewBuilder
    private func presetLibrarySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func presetLibraryButtonRow(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if role == .destructive {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var startActionSummary: String {
        if !settingsStore.hasRequiredBinaries {
            return "FFmpeg and FFprobe must be configured before you can start."
        }
        if viewModel.hasInvalidCustomInputs {
            return "Fix the custom resolution or FPS values in More Settings."
        }
        if customCommandValidation.errorMessage != nil {
            return "Fix the custom FFmpeg command in Advanced before starting."
        }
        if externalAudioValidationMessage != nil {
            return "Choose readable external audio tracks or clear the override."
        }
        if subtitleValidationMessage != nil {
            return "Choose readable subtitle files or clear the override."
        }
        if !queueStore.canStartOrResume(selectedJobIDs: viewModel.selectedJobIDs) {
            return viewModel.selectedJobIDs.isEmpty ? "Add files to begin converting." : "The selected items are not ready to start."
        }

        let count = viewModel.selectedJobIDs.count
        if count == 0 {
            return "Runs on all queued items."
        }
        if count == 1 {
            return "Runs on the selected item."
        }
        return "Runs on \(count) selected items."
    }

    private var startActionSummaryColor: Color {
        if sidebarStartDisabled && queueStore.canStartOrResume(selectedJobIDs: viewModel.selectedJobIDs) {
            return .orange
        }
        if !settingsStore.hasRequiredBinaries {
            return .orange
        }
        return .secondary
    }

    private var moreSettingsStatusLabel: String? {
        if viewModel.isUsingCustomPreset {
            return "Custom"
        }
        if viewModel.isPresetCustomized || viewModel.isAdvancedModified {
            return "Modified"
        }
        return nil
    }

    private var isActiveUserPreset: Bool {
        viewModel.userPresets.contains { $0.name == viewModel.activePreset.name }
    }

    private func presetCard(for card: SidebarPrimaryPresetCard) -> some View {
        let isSelected = viewModel.selectedPresetID == card.presetName
        let isModifiedBasePreset = viewModel.modifiedBasePreset?.name == card.presetName && !isSelected
        let isUnavailable = isPrimaryPresetUnavailable(card)
        let accentColor: Color = isUnavailable ? .secondary : (isModifiedBasePreset ? .orange : .accentColor)
        let badgeTitle: String? = {
            if isUnavailable {
                return "Unavailable"
            }
            if isSelected {
                return "Selected"
            }
            if isModifiedBasePreset {
                return "Modified"
            }
            return nil
        }()

        return presetCard(
            title: card.title,
            subtitle: card.subtitle,
            icon: card.icon,
            accentColor: accentColor,
            isSelected: isSelected,
            badgeTitle: badgeTitle
        )
    }

    @ViewBuilder
    private func presetCard(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        isSelected: Bool,
        badgeTitle: String?
    ) -> some View {
        let borderColor = isSelected ? accentColor : Color(nsColor: .separatorColor)
        let fillColor = isSelected ? accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24)
                .background((isSelected ? borderColor : Color(nsColor: .separatorColor)).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if let badgeTitle {
                        statusPill(title: badgeTitle, color: accentColor)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func presetIcon(for preset: ConversionPreset) -> String {
        guard preset.kind == .video else {
            return "waveform"
        }

        if preset.name == ConversionPreset.telegramPresetName {
            return "paperplane.fill"
        }

        switch preset.videoCodec {
        case .h264:
            return "bolt.fill"
        case .hevc:
            return "sparkles"
        case .proRes:
            return "film.stack"
        case .vp9, .av1:
            return "paperplane.fill"
        case nil:
            return "slider.horizontal.3"
        }
    }

    private var outputSummaryView: some View {
        Group {
            if let outputFolder = settingsStore.defaultOutputDirectoryURL {
                VStack(alignment: .leading, spacing: 3) {
                    Text(outputFolder.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(outputFolder.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                sidebarReadableText("Exports save next to each source file.", font: .caption, color: .secondary)
            }
        }
    }

    private var folderDropTypeIdentifiers: [String] {
        [UTType.fileURL.identifier]
    }

    private var selectionFolderDropTypeIdentifiers: [String] {
        viewModel.selectedJobIDs.isEmpty ? [] : folderDropTypeIdentifiers
    }

    private func outputActionButtonLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        isDropTargeted: Bool,
        isEnabled: Bool = true
    ) -> some View {
        outputActionCardContainer(isDropTargeted: isDropTargeted, isEnabled: isEnabled) {
            outputActionCardContent(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage
            )
        }
    }

    private func outputActionCardContent(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .separatorColor).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputActionCardContainer<Content: View>(
        isDropTargeted: Bool,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let borderColor = isDropTargeted
            ? Color.accentColor
            : (isEnabled ? Color(nsColor: .separatorColor) : Color(nsColor: .separatorColor).opacity(0.6))
        let backgroundColor = isDropTargeted
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor)

        return content()
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: isDropTargeted ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isEnabled ? 1 : 0.58)
    }

    private func sidebarReadableText(
        _ content: String,
        font: Font = .caption2,
        color: Color = .secondary
    ) -> some View {
        // Sidebar helper and warning copy should wrap within the available column instead of truncating.
        Text(content)
            .font(font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private func pillActionButtonLabel(
        _ title: String,
        systemImage: String? = nil,
        prominence: PillButtonProminence = .secondary
    ) -> some View {
        let palette = prominence.palette

        return HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .foregroundStyle(palette.foreground)
        .background(palette.background)
        .overlay(
            Capsule()
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func primarySidebarActionLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .foregroundStyle(Color.white)
        .background(Color.accentColor)
        .clipShape(Capsule())
        .opacity(sidebarStartDisabled ? 0.55 : 1)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                    addExternalSubtitleTracks()
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

    private var encoderChoiceBinding: Binding<EncoderChoice> {
        Binding(
            get: { EncoderChoice(option: viewModel.draftOptions.encoderOption) },
            set: { newValue in
                viewModel.updateOptions {
                    $0.encoderOption = newValue.option
                }
            }
        )
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

    private var customCommandEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.draftOptions.isCustomCommandEnabled },
            set: { newValue in
                viewModel.updateOptions { $0.isCustomCommandOverrideEnabled = newValue }
            }
        )
    }

    private var customCommandTemplateBinding: Binding<String> {
        Binding(
            get: { viewModel.draftOptions.effectiveCustomCommandTemplate },
            set: { newValue in
                viewModel.updateOptions { $0.customCommandTemplate = newValue }
            }
        )
    }

    private var activePresetDisplayName: String {
        viewModel.activePreset.name
    }

    private var toneMappingUsesApplePipeline: Bool {
        settingsStore.preferredToneMappingBackend == .appleAVConvert
    }

    private var selectedDynamicRangeState: SidebarDynamicRangeState {
        let relevantJobs = viewModel.selectedJobs.filter { !$0.options.isAudioOnly }
        guard !relevantJobs.isEmpty else { return .unknown }
        let analyzedJobs = relevantJobs.filter { $0.metadata?.videoStream != nil }
        guard !analyzedJobs.isEmpty else { return .unknown }
        let hdrCount = analyzedJobs.filter { $0.metadata?.isHDR == true }.count
        if hdrCount == 0 {
            return .allSDR
        }
        if hdrCount == analyzedJobs.count {
            return .hdrPresent
        }
        return .mixed
    }

    private var toneMappingControlsAvailable: Bool {
        if settingsStore.avconvertCapabilities.isAvailable {
            return true
        }
        return !settingsStore.filterCapabilities.hasScanned || settingsStore.filterCapabilities.supportsToneMapping
    }

    private var toneMappingToggleEnabled: Bool {
        !viewModel.draftOptions.isAudioOnly &&
        ((toneMappingControlsAvailable && selectedDynamicRangeState != .allSDR) || viewModel.draftOptions.enableHDRToSDR)
    }

    private var toneMappingUnavailableMessage: String {
        "HDR tone mapping requires Apple's avconvert on this Mac, or an FFmpeg build with libplacebo or zscale."
    }

    private var toneMappingEngineBinding: Binding<ToneMappingBackend> {
        Binding(
            get: { settingsStore.toneMappingBackendPreference },
            set: { newValue in
                settingsStore.selectToneMappingBackend(newValue)
            }
        )
    }

    private var toneMappingEngineWarning: String? {
        guard viewModel.draftOptions.enableHDRToSDR else { return nil }
        guard settingsStore.filterCapabilities.hasScanned else { return nil }
        guard !settingsStore.filterCapabilities.supportsToneMapping else { return nil }
        guard settingsStore.avconvertCapabilities.isAvailable else { return nil }
        return "FFmpeg tone mapping requires libplacebo or zscale in your ffmpeg build. Apple VideoToolbox will be used instead."
    }

    private func isToneMappingEngineDisabled(_ backend: ToneMappingBackend) -> Bool {
        switch backend {
        case .appleAVConvert:
            return !settingsStore.avconvertCapabilities.isAvailable
        case .ffmpegFilters:
            return settingsStore.filterCapabilities.hasScanned && !settingsStore.filterCapabilities.supportsToneMapping
        }
    }

    private func toneMappingEngineHelpText(_ backend: ToneMappingBackend) -> String? {
        switch backend {
        case .appleAVConvert:
            return settingsStore.avconvertCapabilities.isAvailable
                ? nil
                : "Apple VideoToolbox tone mapping is unavailable on this Mac."
        case .ffmpegFilters:
            guard settingsStore.filterCapabilities.hasScanned else { return nil }
            return settingsStore.filterCapabilities.supportsToneMapping
                ? nil
                : "FFmpeg tone mapping requires libplacebo or zscale in your ffmpeg build."
        }
    }

    private var toneMappingNote: String? {
        if selectedDynamicRangeState == .allSDR {
            return "Source is SDR. HDR → SDR only applies to HDR sources."
        }

        guard viewModel.draftOptions.enableHDRToSDR else { return nil }

        if toneMappingUsesApplePipeline {
            return "Handled by Apple VideoToolbox tone mapping."
        }

        if settingsStore.preferredToneMappingBackend == .ffmpegFilters {
            if !settingsStore.avconvertCapabilities.isAvailable,
               settingsStore.filterCapabilities.hasScanned,
               settingsStore.filterCapabilities.supportsToneMapping {
                return "Apple VideoToolbox is unavailable on this Mac, so ForgeFF will use FFmpeg tone mapping instead."
            }

            if selectedDynamicRangeState == .mixed {
                return "SDR sources keep their original range. Only HDR sources will be tone mapped."
            }

            return "FFmpeg tone mapping uses the selected method below."
        }

        if selectedDynamicRangeState == .mixed {
            return "SDR sources keep their original range. Only HDR sources will be tone mapped."
        }

        return nil
    }

    private var sidebarStartDisabled: Bool {
        !settingsStore.hasRequiredBinaries ||
        !queueStore.canStartOrResume(selectedJobIDs: viewModel.selectedJobIDs) ||
        viewModel.hasInvalidCustomInputs ||
        customCommandValidation.errorMessage != nil ||
        externalAudioValidationMessage != nil ||
        subtitleValidationMessage != nil
    }

    private var customCommandValidation: FFmpegCommandBuilder.CustomCommandTemplateValidation {
        FFmpegCommandBuilder.validateCustomCommandTemplate(
            viewModel.draftOptions.effectiveCustomCommandTemplate,
            enabled: viewModel.draftOptions.isCustomCommandEnabled
        )
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

    private func handleDefaultOutputFolderDrop(providers: [NSItemProvider]) -> Bool {
        handleFolderDrop(providers) { url in
            settingsStore.setDefaultOutputDirectory(url)
            queueStore.applyDefaultOutputDirectoryToUnsetJobs()
        }
    }

    private func handleSelectionOutputFolderDrop(providers: [NSItemProvider]) -> Bool {
        let selection = viewModel.selectedJobIDs
        guard !selection.isEmpty else { return false }

        return handleFolderDrop(providers) { url in
            queueStore.setOutputDirectory(url, for: selection)
        }
    }

    private func handleFolderDrop(
        _ providers: [NSItemProvider],
        action: @escaping (URL) -> Void
    ) -> Bool {
        let supportedProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !supportedProviders.isEmpty else { return false }

        for provider in supportedProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = droppedURL(from: item), isDirectory(url) else { return }
                DispatchQueue.main.async {
                    action(url)
                }
            }
        }

        return true
    }

    private func droppedURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let nsURL = item as? NSURL {
            return nsURL as URL
        }
        if let string = item as? String,
           let url = URL(string: string),
           url.isFileURL {
            return url
        }
        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func revealDefaultOutputFolder() {
        guard settingsStore.revealDefaultOutputDirectory() else {
            queueStore.alertMessage = "Choose a default output folder first."
            return
        }
    }

    private var advancedExpandedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isAdvancedExpanded },
            set: { viewModel.isAdvancedExpanded = $0 }
        )
    }

    private func insertCustomCommandExample() {
        let currentTemplate = viewModel.draftOptions.effectiveCustomCommandTemplate
            .trimmingCharacters(in: .whitespacesAndNewlines)

        viewModel.updateOptions {
            $0.isCustomCommandOverrideEnabled = true
            if currentTemplate.isEmpty {
                $0.customCommandTemplate = customCommandExampleTemplate
            }
        }
    }

    private var focusOrder: [SidebarFocusTarget] {
        var order: [SidebarFocusTarget] = primaryPresetCards.map {
            SidebarFocusTarget.presetCard($0.presetName)
        }
        order.append(contentsOf: [
            .morePresets,
            .chooseDefaultOutputFolder,
            .resetDefaultOutputFolder,
            .revealDefaultOutputFolder,
            .chooseOutputFolderForSelection,
            .startConversion,
            .moreSettingsTogglePill
        ])

        if isMoreSettingsExpanded,
           let moreIndex = order.firstIndex(of: .moreSettingsTogglePill) {
            let moreTargets: [SidebarFocusTarget] = [
                .container,
                .videoCodec,
                .videoCodecHelp,
                .quality,
                .encoderOptions,
                .videoToolboxDefault,
                .resolution,
                .fps,
                .hdrEnable,
                .hdrToneMappingEngine,
                .hdrToneMap,
                .audioCodec,
                .audioBitrate,
                .audioChannels,
                .externalAudioAdd,
                .subtitles,
                .subtitleAdd,
                .allowOverwrite,
                .cleanupMetadata,
                .cleanupChapters,
                .webOptimization,
                .renameTogglePill,
                .advancedTogglePill
            ]
            order.insert(contentsOf: moreTargets, at: moreIndex + 1)

            if resolutionChoiceBinding.wrappedValue == .custom,
               let resolutionIndex = order.firstIndex(of: .resolution) {
                order.insert(contentsOf: [.resolutionCustomWidth, .resolutionCustomHeight], at: resolutionIndex + 1)
            }

            if fpsChoiceBinding.wrappedValue == .custom,
               let fpsIndex = order.firstIndex(of: .fps) {
                order.insert(.fpsCustomValue, at: fpsIndex + 1)
            }

            if !viewModel.draftOptions.externalAudioAttachments.isEmpty,
               let externalAudioIndex = order.firstIndex(of: .externalAudioAdd) {
                let audioTargets = viewModel.draftOptions.externalAudioAttachments.map { SidebarFocusTarget.externalAudioRemove($0.id) }
                order.insert(contentsOf: [.externalAudioClear] + audioTargets, at: externalAudioIndex + 1)
            }

            if subtitleMode == .addExternal,
               let subtitleIndex = order.firstIndex(of: .subtitleAdd) {
                var subtitleTargets = [SidebarFocusTarget]()
                if !viewModel.draftOptions.subtitleAttachments.isEmpty {
                    subtitleTargets.append(.subtitleClear)
                    for attachment in viewModel.draftOptions.subtitleAttachments {
                        subtitleTargets.append(.subtitleLanguage(attachment.id))
                        subtitleTargets.append(.subtitleRemove(attachment.id))
                    }
                }
                order.insert(contentsOf: subtitleTargets, at: subtitleIndex + 1)
            }

            if isRenameExpanded,
               let renameIndex = order.firstIndex(of: .renameTogglePill) {
                let renameTargets: [SidebarFocusTarget] = [
                    .renamePrefix,
                    .renameSuffix,
                    .renameReplace,
                    .renameWith,
                    .renameSanitize,
                    .renameApply
                ]
                order.insert(contentsOf: renameTargets, at: renameIndex + 1)
            }

            if viewModel.isAdvancedExpanded {
                let advancedTargets: [SidebarFocusTarget] = [
                    .advancedFFmpegChange,
                    .advancedFFmpegReset,
                    .advancedFFprobeChange,
                    .advancedFFprobeReset,
                    .advancedVideoBitrate,
                    .advancedCustomCommandToggle,
                    .advancedCustomCommandInsertExample,
                    .advancedCustomCommandTemplate,
                    .advancedCustomCommandReset
                ]
                if let headerIndex = order.firstIndex(of: .advancedTogglePill) {
                    order.insert(contentsOf: advancedTargets, at: headerIndex + 1)
                }
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
             .advancedCustomCommandToggle,
             .advancedCustomCommandInsertExample,
             .advancedCustomCommandTemplate,
             .advancedCustomCommandReset:
            return true
        default:
            return false
        }
    }

    private func isRenameControlTarget(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case .renamePrefix, .renameSuffix, .renameReplace, .renameWith, .renameSanitize, .renameApply:
            return true
        default:
            return false
        }
    }

    private func isFocusTargetEnabled(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case let .presetCard(name):
            return primaryPresetCards.contains { $0.presetName == name }
        case .morePresets:
            return true
        case .resetDefaultOutputFolder:
            return settingsStore.defaultOutputDirectoryURL != nil
        case .revealDefaultOutputFolder:
            return settingsStore.defaultOutputDirectoryURL != nil
        case .chooseOutputFolderForSelection:
            return !viewModel.selectedJobIDs.isEmpty
        case .startConversion:
            return !sidebarStartDisabled
        case .moreSettingsTogglePill:
            return true
        case .container,
             .videoCodec,
             .quality,
             .resolution,
             .fps,
             .audioCodec,
             .subtitles,
             .videoToolboxDefault,
             .cleanupMetadata,
             .cleanupChapters,
             .externalAudioAdd,
             .advancedTogglePill,
             .renameTogglePill,
             .allowOverwrite:
            return isMoreSettingsExpanded
        case .hdrEnable:
            return isMoreSettingsExpanded && toneMappingToggleEnabled
        case .hdrToneMappingEngine:
            return isMoreSettingsExpanded &&
            viewModel.draftOptions.enableHDRToSDR &&
            toneMappingControlsAvailable
        case .subtitleAdd:
            return isMoreSettingsExpanded && subtitleMode == .addExternal
        case .subtitleClear:
            return isMoreSettingsExpanded && subtitleMode == .addExternal && !viewModel.draftOptions.subtitleAttachments.isEmpty
        case .encoderOptions:
            return isMoreSettingsExpanded && viewModel.draftOptions.videoCodec != .proRes
        case .videoCodecHelp:
            return isMoreSettingsExpanded && settingsStore.encoderCapabilities.missingModernVideoEncoders
        case .webOptimization:
            return isMoreSettingsExpanded && viewModel.draftOptions.isWebOptimizationAvailable
        case .externalAudioClear:
            return isMoreSettingsExpanded && !viewModel.draftOptions.externalAudioAttachments.isEmpty
        case let .externalAudioRemove(id):
            return isMoreSettingsExpanded && viewModel.draftOptions.externalAudioAttachments.contains { $0.id == id }
        case let .subtitleLanguage(id):
            return isMoreSettingsExpanded && subtitleMode == .addExternal && viewModel.draftOptions.subtitleAttachments.contains { $0.id == id }
        case let .subtitleRemove(id):
            return isMoreSettingsExpanded && subtitleMode == .addExternal && viewModel.draftOptions.subtitleAttachments.contains { $0.id == id }
        case .audioBitrate, .audioChannels:
            return isMoreSettingsExpanded && viewModel.draftOptions.audioCodec != .copy
        case .hdrToneMap:
            return isMoreSettingsExpanded &&
            viewModel.draftOptions.enableHDRToSDR &&
            toneMappingControlsAvailable &&
            !toneMappingUsesApplePipeline
        case .resolutionCustomWidth, .resolutionCustomHeight:
            return isMoreSettingsExpanded && resolutionChoiceBinding.wrappedValue == .custom
        case .fpsCustomValue:
            return isMoreSettingsExpanded && fpsChoiceBinding.wrappedValue == .custom
        case .renamePrefix,
             .renameSuffix,
             .renameReplace,
             .renameWith,
             .renameSanitize,
             .renameApply:
            return isMoreSettingsExpanded && isRenameExpanded
        case .advancedFFmpegChange,
             .advancedFFmpegReset,
             .advancedFFprobeChange,
             .advancedFFprobeReset,
             .advancedVideoBitrate,
             .advancedCustomCommandToggle,
             .advancedCustomCommandInsertExample,
             .advancedCustomCommandReset:
            return isMoreSettingsExpanded && viewModel.isAdvancedExpanded
        case .advancedCustomCommandTemplate:
            return isMoreSettingsExpanded && viewModel.isAdvancedExpanded && viewModel.draftOptions.isCustomCommandEnabled
        default:
            return true
        }
    }

    private func isMoreSettingsChildTarget(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case .container,
             .videoCodec,
             .videoCodecHelp,
             .quality,
             .encoderOptions,
             .resolution,
             .resolutionCustomWidth,
             .resolutionCustomHeight,
             .fps,
             .fpsCustomValue,
             .audioCodec,
             .subtitles,
             .videoToolboxDefault,
             .audioBitrate,
             .audioChannels,
             .allowOverwrite,
             .cleanupMetadata,
             .cleanupChapters,
             .webOptimization,
             .externalAudioAdd,
             .externalAudioClear,
             .hdrEnable,
             .hdrToneMappingEngine,
             .hdrToneMap,
             .subtitleAdd,
             .subtitleClear,
             .renameTogglePill,
             .advancedTogglePill,
             .advancedFFmpegChange,
             .advancedFFmpegReset,
             .advancedFFprobeChange,
             .advancedFFprobeReset,
             .advancedVideoBitrate,
             .advancedCustomCommandToggle,
             .advancedCustomCommandInsertExample,
             .advancedCustomCommandTemplate,
             .advancedCustomCommandReset,
             .renamePrefix,
             .renameSuffix,
             .renameReplace,
             .renameWith,
             .renameSanitize,
             .renameApply:
            return true
        case .externalAudioRemove(_),
             .subtitleLanguage(_),
             .subtitleRemove(_):
            return true
        default:
            return false
        }
    }

    private func toggleSectionKeyHandler(_ binding: Binding<Bool>) -> (NSEvent) -> Bool {
        { event in
            switch event.keyCode {
            case 36, 76, 49: // return/enter/space
                binding.wrappedValue.toggle()
                return true
            case 124: // right arrow
                if !binding.wrappedValue {
                    binding.wrappedValue = true
                }
                return true
            case 123: // left arrow
                if binding.wrappedValue {
                    binding.wrappedValue = false
                }
                return true
            default:
                return false
            }
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

    private var externalAudioValidationMessage: String? {
        let hasUnreadableTrack = viewModel.draftOptions.externalAudioAttachments.contains {
            !FileManager.default.isReadableFile(atPath: $0.fileURL.path)
        }
        return hasUnreadableTrack ? "One or more external audio tracks are missing or unreadable." : nil
    }

    private var subtitleValidationMessage: String? {
        let hasUnreadableSubtitle = viewModel.draftOptions.subtitleAttachments.contains {
            !FileManager.default.isReadableFile(atPath: $0.fileURL.path)
        }
        return hasUnreadableSubtitle ? "One or more subtitle files are missing or unreadable." : nil
    }

    private var subtitleCompatibilityMessage: String? {
        guard subtitleMode == .addExternal,
              viewModel.draftOptions.container != .mkv else {
            return nil
        }

        let needsMKV = viewModel.draftOptions.subtitleAttachments.contains {
            $0.fileURL.pathExtension.lowercased() != "srt"
        }
        return needsMKV ? "Use MKV for the broadest subtitle compatibility with these files." : nil
    }

    private func sectionTogglePill(title: String, isExpanded: Bool) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isExpanded ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                Capsule()
                    .stroke(isExpanded ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var webOptimizationHelpText: String {
        if viewModel.draftOptions.isWebOptimizationAvailable {
            return "Move MP4 or MOV streaming metadata to the start of the file so playback begins sooner online."
        }
        return "Available only for MP4 and MOV outputs. MKV does not use fast-start metadata."
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

    private func presetCardKeyHandler(_ card: SidebarPrimaryPresetCard) -> (NSEvent) -> Bool {
        { event in
            switch event.keyCode {
            case 123, 126:
                if let previous = adjacentPresetCardTarget(for: card.presetName, step: -1) {
                    sidebarFocusRouter.focus(previous, source: .keyboardShiftTab)
                }
                return true
            case 124, 125:
                if let next = adjacentPresetCardTarget(for: card.presetName, step: 1) {
                    sidebarFocusRouter.focus(next, source: .keyboardTab)
                } else {
                    sidebarFocusRouter.focus(.morePresets, source: .keyboardTab)
                }
                return true
            case 36, 76, 49:
                guard !isPrimaryPresetUnavailable(card) else { return true }
                viewModel.selectPreset(named: card.presetName)
                return true
            default:
                return false
            }
        }
    }

    private func adjacentPresetCardTarget(for presetName: String, step: Int) -> SidebarFocusTarget? {
        guard let index = primaryPresetCards.firstIndex(where: { $0.presetName == presetName }) else {
            return nil
        }

        let nextIndex = index + step
        guard primaryPresetCards.indices.contains(nextIndex) else {
            return nil
        }

        return .presetCard(primaryPresetCards[nextIndex].presetName)
    }

    private func isPresetHeaderTarget(_ target: SidebarFocusTarget) -> Bool {
        switch target {
        case .presetCard(_), .morePresets:
            return true
        default:
            return false
        }
    }

    private func toneMapKeyHandler(_ event: NSEvent) -> Bool {
        guard toneMappingControlsAvailable,
              viewModel.draftOptions.enableHDRToSDR,
              !toneMappingUsesApplePipeline else { return false }
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

    private func toneMappingEngineKeyHandler(_ event: NSEvent) -> Bool {
        guard viewModel.draftOptions.enableHDRToSDR, toneMappingControlsAvailable else { return false }
        let backends = ToneMappingBackend.allCases.filter { !isToneMappingEngineDisabled($0) }
        guard let index = backends.firstIndex(of: toneMappingEngineBinding.wrappedValue) else { return false }
        switch event.keyCode {
        case 123, 126:
            toneMappingEngineBinding.wrappedValue = backends[max(0, index - 1)]
            return true
        case 124, 125:
            toneMappingEngineBinding.wrappedValue = backends[min(backends.count - 1, index + 1)]
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
    private func attachmentRow(
        index: Int,
        title: String,
        subtitle: String,
        removeTarget: SidebarFocusTarget,
        removeAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            FocusableContainer(
                router: sidebarFocusRouter,
                target: removeTarget,
                onKeyDown: buttonKeyHandler(removeAction)
            ) {
                Button(action: removeAction) {
                    pillActionButtonLabel("Remove", systemImage: "xmark", prominence: .subtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func subtitleAttachmentRow(index: Int, attachment: SubtitleAttachment) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileURL.lastPathComponent)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Track \(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            FocusableContainer(
                router: sidebarFocusRouter,
                target: .subtitleLanguage(attachment.id),
                onFocusGained: { focusedField = .subtitleLanguage(attachment.id) },
                onKeyDown: { _ in false }
            ) {
                TextField("eng", text: subtitleLanguageBinding(for: attachment.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 68)
                    .focused($focusedField, equals: .subtitleLanguage(attachment.id))
            }

            FocusableContainer(
                router: sidebarFocusRouter,
                target: .subtitleRemove(attachment.id),
                onKeyDown: buttonKeyHandler {
                    removeSubtitleTrack(attachment.id)
                }
            ) {
                Button {
                    removeSubtitleTrack(attachment.id)
                } label: {
                    pillActionButtonLabel("Remove", systemImage: "xmark", prominence: .subtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chooseExternalAudioTracks() {
        guard let urls = queueStore.chooseExternalAudioURLs(), !urls.isEmpty else { return }
        let attachments = urls.map { ExternalAudioAttachment(fileURL: $0) }
        viewModel.updateOptions { options in
            if !AudioCodec.externalTrackChoices.contains(options.audioCodec) {
                options.audioCodec = .aac
            }
            options.externalAudioAttachments = mergeExternalAudioAttachments(
                existing: options.externalAudioAttachments,
                additions: attachments
            )
        }
    }

    private func clearExternalAudioTracks() {
        viewModel.updateOptions { $0.externalAudioAttachments = [] }
    }

    private func removeExternalAudioTrack(_ attachmentID: UUID) {
        viewModel.updateOptions {
            $0.externalAudioAttachments.removeAll { $0.id == attachmentID }
        }
    }

    private func exportUserPresets() {
        guard !viewModel.userPresets.isEmpty else {
            queueStore.alertMessage = "There are no saved user presets to export."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "forgeff-presets-v2.json"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.exportUserPresets(to: url)
        } catch {
            queueStore.alertMessage = "Could not export presets: \(error.localizedDescription)"
        }
    }

    private func importUserPresets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.importUserPresets(from: url)
        } catch {
            queueStore.alertMessage = "Could not import presets: \(error.localizedDescription)"
        }
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
                    Button(action: onChange) {
                        pillActionButtonLabel("Change", systemImage: "slider.horizontal.3", prominence: .subtle)
                    }
                    .buttonStyle(.plain)
                }
                FocusableContainer(
                    router: sidebarFocusRouter,
                    target: resetTarget,
                    onKeyDown: buttonKeyHandler(onReset)
                ) {
                    Button(action: onReset) {
                        pillActionButtonLabel("Reset to Auto", systemImage: "arrow.uturn.backward", prominence: .subtle)
                    }
                    .buttonStyle(.plain)
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

    private func applySubtitleMode(_ mode: SubtitleHandling, attachments: [SubtitleAttachment] = []) {
        viewModel.updateOptions {
            $0.subtitleMode = mode
            switch mode {
            case .keep:
                $0.removeEmbeddedSubtitles = false
                if attachments.isEmpty {
                    $0.subtitleAttachments = []
                }
            case .remove:
                $0.removeEmbeddedSubtitles = true
                $0.subtitleAttachments = []
            case .addExternal:
                $0.removeEmbeddedSubtitles = false
                if !attachments.isEmpty {
                    $0.subtitleAttachments = attachments
                }
            }
        }
    }

    private func addExternalSubtitleTracks() {
        guard let urls = queueStore.chooseSubtitleAttachmentURLs(), !urls.isEmpty else { return }
        let attachments = urls.map { SubtitleAttachment(fileURL: $0, languageCode: "eng") }
        viewModel.updateOptions { options in
            options.subtitleMode = .addExternal
            options.removeEmbeddedSubtitles = false
            options.subtitleAttachments = mergeSubtitleAttachments(
                existing: options.subtitleAttachments,
                additions: attachments
            )
        }
    }

    private func removeSubtitleTrack(_ attachmentID: UUID) {
        viewModel.updateOptions {
            $0.subtitleAttachments.removeAll { $0.id == attachmentID }
            if $0.subtitleAttachments.isEmpty, $0.subtitleMode == .addExternal {
                $0.subtitleMode = .keep
            }
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

    private func subtitleLanguageBinding(for attachmentID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.draftOptions.subtitleAttachments.first(where: { $0.id == attachmentID })?.languageCode ?? "eng"
            },
            set: { newValue in
                viewModel.updateOptions { options in
                    guard let index = options.subtitleAttachments.firstIndex(where: { $0.id == attachmentID }) else { return }
                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    options.subtitleAttachments[index].languageCode = normalized.isEmpty ? "eng" : normalized
                }
            }
        )
    }

    private func mergeSubtitleAttachments(
        existing: [SubtitleAttachment],
        additions: [SubtitleAttachment]
    ) -> [SubtitleAttachment] {
        var merged = existing
        var seenPaths = Set(existing.map { $0.fileURL.standardizedFileURL.path })
        for attachment in additions {
            let path = attachment.fileURL.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            merged.append(attachment)
            seenPaths.insert(path)
        }
        return merged
    }

    private func mergeExternalAudioAttachments(
        existing: [ExternalAudioAttachment],
        additions: [ExternalAudioAttachment]
    ) -> [ExternalAudioAttachment] {
        var merged = existing
        var seenPaths = Set(existing.map { $0.fileURL.standardizedFileURL.path })
        for attachment in additions {
            let path = attachment.fileURL.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            merged.append(attachment)
            seenPaths.insert(path)
        }
        return merged
    }

}

private struct SidebarPrimaryPresetCard: Identifiable {
    let title: String
    let subtitle: String
    let presetName: String
    let icon: String

    var id: String { presetName }
}

private enum SidebarDynamicRangeState {
    case unknown
    case allSDR
    case mixed
    case hdrPresent
}

private enum PillButtonProminence: Equatable {
    case primary
    case secondary
    case subtle

    var palette: (foreground: Color, background: Color, border: Color) {
        switch self {
        case .primary:
            return (.white, .accentColor, .accentColor)
        case .secondary:
            return (.primary, Color(nsColor: .controlBackgroundColor), Color(nsColor: .separatorColor))
        case .subtle:
            return (.secondary, Color.secondary.opacity(0.12), Color.secondary.opacity(0.24))
        }
    }
}

private struct SidebarPillButton: View {
    var title: String? = nil
    var systemImage: String? = nil
    var accessibilityLabel: String? = nil
    var prominence: PillButtonProminence = .secondary
    var compact: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(
            SidebarPillButtonStyle(
                prominence: prominence,
                compact: compact,
                isHovering: isHovering
            )
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(Text(accessibilityLabel ?? title ?? "Button"))
    }
}

private struct SidebarPillButtonStyle: ButtonStyle {
    let prominence: PillButtonProminence
    let compact: Bool
    let isHovering: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = prominence.palette
        let interactionOverlayOpacity = isEnabled
            ? (configuration.isPressed ? 0.12 : (isHovering ? 0.06 : 0))
            : 0
        let borderColor = configuration.isPressed
            ? Color.accentColor.opacity(0.85)
            : palette.border
        let foregroundColor: Color = {
            if !isEnabled {
                return Color(nsColor: .secondaryLabelColor)
            }
            if prominence == .primary {
                return .white
            }
            return Color(nsColor: .labelColor)
        }()

        return configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, compact ? 8 : 12)
            .frame(minWidth: compact ? 30 : nil)
            .frame(height: 30)
            .foregroundStyle(foregroundColor)
            .background {
                Capsule()
                    .fill(palette.background)
                    .overlay(
                        Capsule()
                            .fill(Color(nsColor: .labelColor).opacity(interactionOverlayOpacity))
                    )
            }
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BinaryPillToggle: View {
    @Binding var isOn: Bool
    var offTitle: String = "Off"
    var onTitle: String = "On"
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            toggleButton(title: offTitle, selected: !isOn) {
                isOn = false
            }
            toggleButton(title: onTitle, selected: isOn) {
                isOn = true
            }
        }
        .opacity(isDisabled ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }

    private func toggleButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .background(selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Capsule()
                        .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private enum FocusField: Hashable {
    case customWidth
    case customHeight
    case customFPS
    case videoBitrate
    case subtitleLanguage(UUID)
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

private enum EncoderChoice: CaseIterable, Hashable {
    case auto
    case veryFast
    case fast
    case medium
    case slow

    static let allCases: [EncoderChoice] = [.auto, .veryFast, .fast, .medium, .slow]

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .veryFast: return "Very Fast"
        case .fast: return "Fast"
        case .medium: return "Medium"
        case .slow: return "Slow"
        }
    }

    var option: EncoderOption? {
        switch self {
        case .auto: return nil
        case .veryFast: return .veryFast
        case .fast: return .fast
        case .medium: return .medium
        case .slow: return .slow
        }
    }

    init(option: EncoderOption?) {
        switch option {
        case nil: self = .auto
        case .veryFast?: self = .veryFast
        case .fast?: self = .fast
        case .medium?: self = .medium
        case .slow?: self = .slow
        }
    }
}
