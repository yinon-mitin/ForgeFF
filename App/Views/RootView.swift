import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var queueStore: JobQueueStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var commandHandler: AppCommandHandler

    @ObservedObject var viewModel: QueueViewModel

    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var isClearConfirmationPresented = false

    var body: some View {
        NavigationSplitView {
            PresetOptionsPanelView(viewModel: viewModel)
                .frame(minWidth: 300, idealWidth: 320)
        } detail: {
            VStack(spacing: 0) {
                QueueListView(
                    viewModel: viewModel,
                    isDropTargeted: $isDropTargeted,
                    onAddFiles: { isFileImporterPresented = true },
                    onAddFolder: chooseFolder
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            toolbarContent
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                queueStore.addFiles(urls: urls)
                viewModel.refreshDraftOptions()
            }
        }
        .confirmationDialog("Clear Queue", isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button("Clear only queued items") {
                queueStore.clearQueuedItems()
                viewModel.refreshDraftOptions()
            }
            Button("Clear everything (queued + completed + failed)") {
                queueStore.clearAllItems()
                viewModel.selectedJobIDs.removeAll()
                viewModel.refreshDraftOptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to remove from the queue.")
        }
        .sheet(isPresented: $settingsStore.shouldShowFFmpegSetup) {
            FFmpegSetupView()
                .environmentObject(settingsStore)
                .frame(minWidth: 520, minHeight: 360)
                .interactiveDismissDisabled(!settingsStore.hasRequiredBinaries)
        }
        .alert("ForgeFF", isPresented: Binding(
            get: { queueStore.alertMessage != nil },
            set: { if !$0 { queueStore.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(queueStore.alertMessage ?? "")
        }
        .onAppear {
            settingsStore.refreshBinaryDetection()
            wireCommandHandlers()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu("Add…") {
                Button("Add Files…") {
                    isFileImporterPresented = true
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Add Folder…") {
                    chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            Button("Output Folder") {
                queueStore.chooseOutputDirectory()
            }

            Button(queueStore.isQueuePaused ? "Resume" : "Start") {
                queueStore.startQueue()
            }
            .disabled(!settingsStore.hasRequiredBinaries || viewModel.hasInvalidCustomInputs)

            Button("Pause") {
                queueStore.pauseCurrentJob()
            }
            .disabled(!queueStore.isRunning)

            Button("Cancel") {
                queueStore.cancelCurrentJob()
            }
            .disabled(!queueStore.isRunning && !queueStore.isQueuePaused)

            Button("Clear") {
                isClearConfirmationPresented = true
            }
            .disabled(!queueStore.hasClearableQueueItems && !queueStore.hasCompletedResults)
        }

        ToolbarItem(placement: .automatic) {
            if !settingsStore.hasRequiredBinaries {
                Button {
                    settingsStore.shouldShowFFmpegSetup = true
                } label: {
                    Label("FFmpeg Missing", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                }
                .help("FFmpeg/FFprobe not configured")
            }
        }
    }

    private var footer: some View {
        let summary = queueStore.footerSummary
        return HStack(spacing: 14) {
            Text("In queue: \(summary.queued)")
            Text("Processing: \(summary.processing)")
            Text("Done: \(summary.done)")
            Text("Failed: \(summary.failed)")
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func wireCommandHandlers() {
        commandHandler.onAddFiles = { isFileImporterPresented = true }
        commandHandler.onAddFolder = { chooseFolder() }
        commandHandler.onStartOrResume = { queueStore.startQueue() }
        commandHandler.onCancelQueue = { queueStore.cancelCurrentJob() }
        commandHandler.onRemoveSelected = { viewModel.removeSelectedJobs() }
        commandHandler.onClearQueue = { isClearConfirmationPresented = true }
        commandHandler.onClearCompleted = { queueStore.clearCompletedResults() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            queueStore.addFolder(url: url)
            viewModel.refreshDraftOptions()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                DispatchQueue.main.async {
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    if isDirectory.boolValue {
                        queueStore.addFolder(url: url)
                    } else {
                        queueStore.addFiles(urls: [url])
                    }
                    viewModel.refreshDraftOptions()
                }
            }
        }
        return true
    }

}

private struct FFmpegSetupView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FFmpeg not found")
                .font(.title2.weight(.semibold))

            Text("ForgeFF needs both ffmpeg and ffprobe configured before any conversion can run. You can install FFmpeg with Homebrew or choose existing binaries manually.")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    settingsStore.copyHomebrewInstallCommand()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install with Homebrew")
                            .font(.headline)
                        Text("Copies: brew install ffmpeg")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    settingsStore.chooseMissingBinary()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose Binary…")
                            .font(.headline)
                        Text("Pick missing ffmpeg/ffprobe path")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .buttonStyle(.bordered)
            }

            GroupBox("Detected hints") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hints, id: \.self) { hint in
                        Text("• \(hint)")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Retry Detection") {
                    settingsStore.refreshBinaryDetection()
                }
            }
        }
        .padding(24)
    }

    private var hints: [String] {
        var lines: [String] = []
        if settingsStore.ffmpegURL == nil {
            lines.append("ffmpeg binary is missing.")
        }
        if settingsStore.ffprobeURL == nil {
            lines.append("ffprobe binary is missing.")
        }
        lines.append(contentsOf: settingsStore.ffmpegHints)
        return lines.isEmpty ? ["No known FFmpeg installation was discovered."] : lines
    }
}

struct RootView: View {
    @ObservedObject var viewModel: QueueViewModel

    var body: some View {
        MainWindowView(viewModel: viewModel)
    }
}
