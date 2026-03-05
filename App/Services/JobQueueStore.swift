import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct QueueFooterSummary {
    let queued: Int
    let processing: Int
    let done: Int
    let failed: Int
}

@MainActor
final class JobQueueStore: ObservableObject {
    @Published private(set) var jobs: [VideoJob] = []
    @Published private(set) var isRunning = false
    @Published var selectedJobID: UUID?
    @Published var alertMessage: String?

    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let runner = FFmpegRunner()
    private var queueTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, historyStore: HistoryStore) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
    }

    var selectedJob: VideoJob? {
        guard let selectedJobID else { return nil }
        return jobs.first(where: { $0.id == selectedJobID })
    }

    var footerSummary: QueueFooterSummary {
        QueueFooterSummary(
            queued: jobs.filter { $0.status == .ready || $0.status == .queued || $0.status == .analyzing }.count,
            processing: jobs.filter { $0.status == .running || $0.status == .paused }.count,
            done: jobs.filter { $0.status == .completed }.count,
            failed: jobs.filter { $0.status == .failed }.count
        )
    }

    var isQueuePaused: Bool {
        jobs.contains(where: { $0.status == .paused })
    }

    var hasClearableQueueItems: Bool {
        jobs.contains(where: { $0.status == .ready || $0.status == .queued || $0.status == .analyzing || $0.status == .paused })
    }

    var hasCompletedResults: Bool {
        jobs.contains(where: { $0.status == .completed || $0.status == .failed || $0.status == .cancelled })
    }

    func addFiles(urls: [URL]) {
        let options = settingsStore.restoreLastUsedOptions()

        for url in urls where Self.isImportable(url: url) {
            var job = VideoJob(sourceURL: url, options: options)
            job.status = .analyzing
            refreshDerivedNaming(for: &job)
            jobs.append(job)
            selectedJobID = job.id
            Task {
                await analyzeMetadata(for: job.id)
            }
        }
    }

    func addFolder(url: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        addFiles(urls: contents)
    }

    func remove(jobIDs: Set<UUID>) {
        jobs.removeAll { jobIDs.contains($0.id) }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
    }

    func removeSelectedJob() {
        guard let selectedJobID else { return }
        remove(jobIDs: [selectedJobID])
    }

    func clearQueuedItems() {
        jobs.removeAll { job in
            switch job.status {
            case .queued, .analyzing, .ready, .paused:
                return true
            default:
                return false
            }
        }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
    }

    func clearCompletedResults() {
        jobs.removeAll { job in
            job.status == .completed || job.status == .failed || job.status == .cancelled
        }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
    }

    func clearAllItems() {
        jobs.removeAll()
        selectedJobID = nil
    }

    func startQueue() {
        if isQueuePaused {
            resumeCurrentJob()
            return
        }

        guard !isRunning else { return }
        guard settingsStore.hasRequiredBinaries else {
            alertMessage = "FFmpeg and FFprobe must both be configured before starting the queue."
            settingsStore.shouldShowFFmpegSetup = true
            return
        }

        isRunning = true
        queueTask = Task { [weak self] in
            await self?.processPendingJobs()
        }
    }

    func pauseCurrentJob() {
        guard let index = jobs.firstIndex(where: { $0.status == .running }) else { return }
        jobs[index].status = .paused
        runner.pause()
    }

    func resumeCurrentJob() {
        guard let index = jobs.firstIndex(where: { $0.status == .paused }) else { return }
        jobs[index].status = .running
        runner.resume()
        isRunning = true
    }

    func cancelCurrentJob() {
        runner.cancel()
    }

    func cancel(jobID: UUID) {
        if jobs.first(where: { $0.id == jobID && $0.status == .running }) != nil {
            runner.cancel()
            return
        }

        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .cancelled
        jobs[index].errorMessage = "Cancelled by user."
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].errorMessage = nil
        jobs[index].result = nil
        jobs[index].completedAt = nil
    }

    func move(from source: IndexSet, to destination: Int) {
        let items = source.map { jobs[$0] }
        var updatedJobs = jobs
        for index in source.sorted(by: >) {
            updatedJobs.remove(at: index)
        }
        let adjustment = source.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - adjustment, 0), updatedJobs.count)
        updatedJobs.insert(contentsOf: items, at: insertionIndex)
        jobs = updatedJobs
    }

    func chooseOutputDirectory() {
        settingsStore.chooseDefaultOutputDirectory()
        for index in jobs.indices where jobs[index].outputDirectory == nil {
            jobs[index].outputDirectory = settingsStore.defaultOutputDirectoryURL
        }
    }

    func chooseOutputDirectoryForSelectedJob() {
        guard let selectedJobID, let index = jobs.firstIndex(where: { $0.id == selectedJobID }) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            jobs[index].outputDirectory = url
        }
    }

    func revealOutput(for jobID: UUID) {
        guard let outputURL = jobs.first(where: { $0.id == jobID })?.result?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func revealSelectedOutput() {
        guard let selectedJobID else { return }
        revealOutput(for: selectedJobID)
    }

    func applyOptions(_ options: ConversionOptions, to jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices where targetIDs.contains(jobs[index].id) {
            jobs[index].options = options
            refreshDerivedNaming(for: &jobs[index])
        }

        settingsStore.saveLastUsed(options: options)
    }

    func applyPreset(_ preset: ConversionPreset, to jobIDs: Set<UUID>?) -> ConversionOptions {
        var options = optionsForSelection(jobIDs)
        options.apply(preset: preset)
        applyOptions(options, to: jobIDs)
        return options
    }

    func applyBatchRename(configuration: BatchRenameConfiguration) {
        let targetIDs = Set(jobs.map(\.id))
        let preview = FilenameRenamer.preview(for: jobs, configuration: configuration)
        for index in jobs.indices where targetIDs.contains(jobs[index].id) {
            if let value = preview[jobs[index].id] {
                jobs[index].outputFilename = value
            }
        }
    }

    func updateSubtitleAttachment(_ attachment: SubtitleAttachment?, for jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices where targetIDs.contains(jobs[index].id) {
            jobs[index].options.subtitleAttachments = attachment.map { [$0] } ?? []
        }
    }

    func chooseSubtitleAttachment(for jobIDs: Set<UUID>?) {
        guard let url = chooseSubtitleAttachmentURL() else { return }

        let attachment = SubtitleAttachment(
            fileURL: url,
            languageCode: "eng"
        )
        updateSubtitleAttachment(attachment, for: jobIDs)
    }

    func chooseSubtitleAttachmentURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["srt", "ass", "vtt"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Add Subtitle"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    func optionsForSelection(_ jobIDs: Set<UUID>?) -> ConversionOptions {
        if let jobIDs, jobIDs.count == 1,
           let id = jobIDs.first,
           let job = jobs.first(where: { $0.id == id }) {
            return job.options
        }

        if let selectedJob {
            return selectedJob.options
        }

        return settingsStore.restoreLastUsedOptions()
    }

    private func analyzeMetadata(for jobID: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .analyzing

        do {
            let ffprobeURL = settingsStore.ffprobeURL
            let metadata = try await FFprobeService.analyze(url: jobs[index].sourceURL, ffprobeURL: ffprobeURL)
            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            jobs[refreshedIndex].metadata = metadata
            jobs[refreshedIndex].status = .ready
            refreshDerivedNaming(for: &jobs[refreshedIndex])
        } catch {
            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            jobs[refreshedIndex].status = .ready
            jobs[refreshedIndex].errorMessage = error.localizedDescription
        }
    }

    private func processPendingJobs() async {
        while true {
            if let nextIndex = jobs.firstIndex(where: { $0.status == .ready }) {
                await runJob(at: nextIndex)
            } else if jobs.contains(where: { $0.status == .analyzing || $0.status == .paused || $0.status == .running }) {
                try? await Task.sleep(nanoseconds: 200_000_000)
            } else {
                break
            }

            if Task.isCancelled { break }
        }

        isRunning = false
        queueTask = nil
    }

    private func runJob(at index: Int) async {
        guard jobs.indices.contains(index) else { return }

        let jobID = jobs[index].id
        jobs[index].status = .running
        jobs[index].startedAt = Date()
        jobs[index].completedAt = nil
        jobs[index].errorMessage = nil

        do {
            let appSettings = settingsStore.settings
            let ffmpegURL = settingsStore.ffmpegURL
            let capabilities = settingsStore.encoderCapabilities
            let result = try await runner.run(job: jobs[index], ffmpegURL: ffmpegURL, settings: appSettings, capabilities: capabilities) { [weak self] progress in
                Task { @MainActor in
                    self?.applyProgress(progress, to: jobID)
                }
            }

            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            jobs[refreshedIndex].status = .completed
            jobs[refreshedIndex].progress = 1
            jobs[refreshedIndex].estimatedRemainingSeconds = 0
            jobs[refreshedIndex].result = result
            jobs[refreshedIndex].completedAt = Date()
            historyStore.append(job: jobs[refreshedIndex])
        } catch {
            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            if case FFmpegRunnerError.cancelled = error {
                jobs[refreshedIndex].status = .cancelled
            } else {
                jobs[refreshedIndex].status = .failed
            }
            jobs[refreshedIndex].errorMessage = error.localizedDescription
            jobs[refreshedIndex].completedAt = Date()
            historyStore.append(job: jobs[refreshedIndex])
        }
    }

    private func applyProgress(_ progress: FFmpegProgress, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = progress.ratio
        jobs[index].estimatedRemainingSeconds = progress.etaSeconds
        if jobs[index].result == nil {
            jobs[index].result = JobResultSummary(
                outputURL: nil,
                outputFileSize: nil,
                elapsedSeconds: nil,
                averageSpeed: progress.speed
            )
        } else {
            jobs[index].result?.averageSpeed = progress.speed
        }
    }

    private func refreshDerivedNaming(for job: inout VideoJob) {
        job.outputFilename = OutputTemplateRenderer.render(template: job.options.outputTemplate, job: job)
    }

    private static func isImportable(url: URL) -> Bool {
        let supportedExtensions = Set([
            "mp4", "mov", "mkv", "m4v", "avi", "webm", "mpg", "mpeg", "mts", "m2ts"
        ])
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
