import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct QueueFooterSummary {
    let queued: Int
    let processing: Int
    let done: Int
    let failed: Int
    let totalInputSizeBytes: Int64
}

enum QueueRunState: String, Equatable {
    case idle
    case running
    case paused
    case cancelling
}

private enum RunScope: Equatable {
    case all
    case selected(Set<UUID>)

    func contains(_ jobID: UUID) -> Bool {
        switch self {
        case .all:
            return true
        case let .selected(ids):
            return ids.contains(jobID)
        }
    }
}

@MainActor
final class JobQueueStore: ObservableObject {
    @Published private(set) var jobs: [VideoJob] = []
    @Published private(set) var queueState: QueueRunState = .idle
    @Published var selectedJobID: UUID?
    @Published var alertMessage: String?

    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let runner = FFmpegRunner()
    private let sourceBookmarkStore = SecurityScopedBookmarkStore()
    private var queueTask: Task<Void, Never>?
    private var activeRunScope: RunScope?

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
            failed: jobs.filter { $0.status == .failed }.count,
            totalInputSizeBytes: jobs.reduce(into: Int64(0)) { partialResult, job in
                partialResult += max(0, job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes ?? 0)
            }
        )
    }

    var isRunning: Bool {
        queueState == .running || queueState == .paused || queueState == .cancelling
    }

    var isQueuePaused: Bool {
        queueState == .paused
    }

    var hasRunnableItems: Bool {
        jobs.contains(where: { isRunnableStatus($0.status) })
    }

    var canStartOrResume: Bool {
        switch queueState {
        case .running, .cancelling:
            return false
        case .idle, .paused:
            if queueState == .paused, hasActivePausedRun {
                return hasRunnableJobs(in: activeRunScope ?? .all)
            }
            return hasRunnableItems
        }
    }

    var startButtonTitle: String {
        guard hasRunnableItems else { return "Start" }
        return hasActivePausedRun ? "Resume" : "Start"
    }

    var hasClearableQueueItems: Bool {
        jobs.contains(where: { $0.status == .ready || $0.status == .queued || $0.status == .analyzing || $0.status == .paused })
    }

    var hasCompletedResults: Bool {
        jobs.contains(where: { $0.status == .completed || $0.status == .failed || $0.status == .cancelled })
    }

    func canCancel(selectedJobIDs: Set<UUID>) -> Bool {
        if selectedJobIDs.isEmpty {
            return isRunning || isQueuePaused
        }
        return jobs.contains {
            selectedJobIDs.contains($0.id) &&
            ($0.status == .ready || $0.status == .queued || $0.status == .analyzing || $0.status == .paused || $0.status == .running)
        }
    }

    func addFiles(urls: [URL]) {
        let options = settingsStore.restoreLastUsedOptions()

        for url in urls where !url.hasDirectoryPath {
            var job = VideoJob(sourceURL: url, options: options)
            job.status = .analyzing
            job.inputFileSizeBytes = readFileSize(at: url)
            refreshDerivedNaming(for: &job)
            jobs.append(job)
            sourceBookmarkStore.store(url: url, for: job.id)
            selectedJobID = job.id
            Task {
                await analyzeMetadata(for: job.id)
            }
        }
    }

    func addFolder(url: URL) {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        addFiles(urls: contents)
    }

    func remove(jobIDs: Set<UUID>) {
        let removingRunningJob = jobs.contains(where: { jobIDs.contains($0.id) && $0.status == .running })
        let removingPausedJob = jobs.contains(where: { jobIDs.contains($0.id) && $0.status == .paused })

        if removingRunningJob {
            runner.cancel()
        }

        sourceBookmarkStore.remove(jobIDs: jobIDs)
        jobs.removeAll { jobIDs.contains($0.id) }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
        if removingRunningJob || removingPausedJob {
            queueTask?.cancel()
            queueTask = nil
        }
        reconcileQueueStateAfterMutation()
    }

    func removeSelectedJob() {
        guard let selectedJobID else { return }
        remove(jobIDs: [selectedJobID])
    }

    func clearQueuedItems() {
        resetQueueRuntimeState()
        let removedIDs = Set(jobs.compactMap { job -> UUID? in
            switch job.status {
            case .queued, .analyzing, .ready, .paused:
                return job.id
            default:
                return nil
            }
        })
        sourceBookmarkStore.remove(jobIDs: removedIDs)
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
        let removedIDs = Set(jobs.compactMap { job -> UUID? in
            job.status == .completed || job.status == .failed || job.status == .cancelled ? job.id : nil
        })
        sourceBookmarkStore.remove(jobIDs: removedIDs)
        jobs.removeAll { job in
            job.status == .completed || job.status == .failed || job.status == .cancelled
        }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
        reconcileQueueStateAfterMutation()
    }

    func clearAllItems() {
        resetQueueRuntimeState()
        sourceBookmarkStore.remove(jobIDs: Set(jobs.map(\.id)))
        jobs.removeAll()
        selectedJobID = nil
    }

    func toggleStartPause(selectedJobIDs: Set<UUID>) {
        if queueState == .running {
            pauseCurrentJob()
            return
        }
        startOrResume(selectedJobIDs: selectedJobIDs)
    }

    func startOrResume(selectedJobIDs: Set<UUID> = []) {
        let resolvedScope: RunScope = selectedJobIDs.isEmpty ? .all : .selected(selectedJobIDs)

        if queueState == .paused {
            if hasPausedJobs(in: resolvedScope) {
                activeRunScope = resolvedScope
                resumeCurrentJob(in: resolvedScope)
                return
            }
            queueState = .idle
            queueTask?.cancel()
            queueTask = nil
            activeRunScope = nil
        }

        guard queueState == .idle else { return }
        guard settingsStore.hasRequiredBinaries else {
            alertMessage = "FFmpeg and FFprobe must both be configured before starting the queue."
            settingsStore.shouldShowFFmpegSetup = true
            return
        }
        if let unavailableCodec = firstUnavailableCodecInQueue() {
            alertMessage = "\(unavailableCodec.displayName) is not available in your FFmpeg build. Choose another codec or install missing encoders."
            return
        }

        guard hasRunnableJobs(in: resolvedScope) else {
            alertMessage = "No runnable items in the current selection."
            return
        }

        activeRunScope = resolvedScope
        queueState = .running
        queueTask = Task { [weak self] in
            await self?.processPendingJobs()
        }
    }

    func startQueue(selectedJobIDs: Set<UUID> = []) {
        startOrResume(selectedJobIDs: selectedJobIDs)
    }

    func pauseCurrentJob() {
        guard let index = jobs.firstIndex(where: { $0.status == .running }) else { return }
        jobs[index].status = .paused
        runner.pause()
        queueState = .paused
    }

    private func resumeCurrentJob(in scope: RunScope? = nil) {
        let targetScope = scope ?? (activeRunScope ?? .all)
        guard let index = jobs.firstIndex(where: { $0.status == .paused && targetScope.contains($0.id) }) else { return }
        jobs[index].status = .running
        runner.resume()
        queueState = .running
    }

    func cancelCurrentJob(selectedJobIDs: Set<UUID> = []) {
        if selectedJobIDs.isEmpty {
            cancelAllRunningQueue()
            return
        }
        cancelSelectedJobs(selectedJobIDs)
    }

    private func cancelAllRunningQueue() {
        queueState = .cancelling
        queueTask?.cancel()
        runner.cancel()
        activeRunScope = nil
    }

    private func cancelSelectedJobs(_ jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty else { return }

        for index in jobs.indices where jobIDs.contains(jobs[index].id) {
            switch jobs[index].status {
            case .ready, .queued, .analyzing, .paused:
                jobs[index].status = .cancelled
                jobs[index].errorMessage = "Cancelled by user."
                jobs[index].errorDetails = "Conversion cancelled by user."
            case .running:
                runner.cancel()
            default:
                break
            }
        }
    }

    func cancel(jobID: UUID) {
        if jobs.first(where: { $0.id == jobID && $0.status == .running }) != nil {
            runner.cancel()
            return
        }

        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .cancelled
        jobs[index].errorMessage = "Cancelled by user."
        jobs[index].errorDetails = "Conversion cancelled by user."
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil
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
        guard let selectedJobID else { return }
        chooseOutputDirectory(for: [selectedJobID])
    }

    func chooseOutputDirectory(for jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            for index in jobs.indices where jobIDs.contains(jobs[index].id) {
                jobs[index].outputDirectory = url
            }
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
            let sourceURL = jobs[index].sourceURL
            let metadata = try await withAccessibleSourceURL(for: jobID, fallbackURL: sourceURL) { accessibleURL in
                try await FFprobeService.analyze(url: accessibleURL, ffprobeURL: ffprobeURL)
            }
            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            jobs[refreshedIndex].metadata = metadata
            jobs[refreshedIndex].status = .ready
            refreshDerivedNaming(for: &jobs[refreshedIndex])
        } catch {
            guard let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            jobs[refreshedIndex].status = .failed
            jobs[refreshedIndex].errorMessage = "Could not read media metadata. File may be unsupported or inaccessible."
            jobs[refreshedIndex].errorDetails = error.localizedDescription
        }
    }

    private func processPendingJobs() async {
        while true {
            if let nextIndex = jobs.firstIndex(where: { isRunnableStatus($0.status) && isInActiveRunScope($0.id) }) {
                await runJob(at: nextIndex)
            } else if jobs.contains(where: { ($0.status == .analyzing || $0.status == .paused || $0.status == .running) && isInActiveRunScope($0.id) }) {
                try? await Task.sleep(nanoseconds: 200_000_000)
            } else {
                break
            }

            if Task.isCancelled { break }
        }

        queueState = .idle
        queueTask = nil
        activeRunScope = nil
    }

    private func runJob(at index: Int) async {
        guard jobs.indices.contains(index) else { return }

        let jobID = jobs[index].id
        jobs[index].status = .running
        jobs[index].startedAt = Date()
        jobs[index].completedAt = nil
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil

        do {
            let appSettings = settingsStore.settings
            let ffmpegURL = settingsStore.ffmpegURL
            let capabilities = settingsStore.encoderCapabilities
            let sourceURL = jobs[index].sourceURL
            let result = try await withAccessibleSourceURL(for: jobID, fallbackURL: sourceURL) { accessibleSourceURL in
                var runnableJob = jobs[index]
                runnableJob.sourceURL = accessibleSourceURL
                if let ffmpegURL {
                    let commandArgs = FFmpegCommandBuilder.buildArguments(for: runnableJob, settings: appSettings, capabilities: capabilities)
                    jobs[index].commandLine = FFmpegCommandBuilder.commandLine(executableURL: ffmpegURL, arguments: commandArgs)
                }

                return try await runner.run(job: runnableJob, ffmpegURL: ffmpegURL, settings: appSettings, capabilities: capabilities) { [weak self] progress in
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
            if let runnerError = error as? FFmpegRunnerError {
                jobs[refreshedIndex].errorMessage = runnerError.errorDescription
                jobs[refreshedIndex].errorDetails = runnerError.details
                jobs[refreshedIndex].commandLine = runnerError.commandLine
            } else {
                jobs[refreshedIndex].errorMessage = error.localizedDescription
                jobs[refreshedIndex].errorDetails = error.localizedDescription
                jobs[refreshedIndex].commandLine = nil
            }
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

    private func hasRunnableJobs(in scope: RunScope) -> Bool {
        jobs.contains(where: { isRunnableStatus($0.status) && scope.contains($0.id) })
    }

    private func hasPausedJobs(in scope: RunScope) -> Bool {
        jobs.contains(where: { $0.status == .paused && scope.contains($0.id) })
    }

    private func isInActiveRunScope(_ jobID: UUID) -> Bool {
        (activeRunScope ?? .all).contains(jobID)
    }

    private func firstUnavailableCodecInQueue() -> VideoCodec? {
        let capabilities = settingsStore.encoderCapabilities
        for job in jobs where job.status == .ready || job.status == .queued {
            switch job.options.videoCodec {
            case .vp9 where !capabilities.supportsVP9:
                return .vp9
            case .av1 where !capabilities.supportsAV1:
                return .av1
            default:
                continue
            }
        }
        return nil
    }

    private func withAccessibleSourceURL<T>(
        for jobID: UUID,
        fallbackURL: URL,
        operation: (URL) async throws -> T
    ) async throws -> T {
        let resolvedURL = sourceBookmarkStore.resolvedURL(for: jobID) ?? fallbackURL
        let didStartAccess = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation(resolvedURL)
    }

    private func resetQueueRuntimeState() {
        queueTask?.cancel()
        queueTask = nil
        runner.cancel()
        activeRunScope = nil
        queueState = .idle
    }

    private func reconcileQueueStateAfterMutation() {
        if let scope = activeRunScope, !hasRunnableJobs(in: scope) {
            activeRunScope = nil
        }

        if jobs.contains(where: { $0.status == .running && isInActiveRunScope($0.id) }) {
            queueState = .running
            return
        }
        if jobs.contains(where: { $0.status == .paused && isInActiveRunScope($0.id) }) {
            queueState = .paused
            return
        }

        if queueState == .paused || queueState == .cancelling {
            queueTask?.cancel()
            queueTask = nil
            queueState = .idle
        }

        if !hasRunnableItems {
            queueTask?.cancel()
            queueTask = nil
            activeRunScope = nil
            queueState = .idle
            return
        }
    }

    private var hasActivePausedRun: Bool {
        guard queueState == .paused else { return false }
        return jobs.contains(where: { $0.status == .paused && isInActiveRunScope($0.id) })
    }

    private func isRunnableStatus(_ status: JobStatus) -> Bool {
        status == .ready || status == .paused
    }

    private func readFileSize(at url: URL) -> Int64? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    static var supportedImportContentTypes: [UTType] {
        let extensions = [
            "mkv", "mp4", "mov", "m4v", "webm", "avi", "wmv", "flv",
            "ts", "m2ts", "mts", "mpg", "mpeg",
            "mp3", "m4a", "aac", "flac", "wav", "ogg"
        ]
        let specificTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        return [.movie, .video, .audio] + specificTypes
    }
}

extension JobQueueStore {
    func _debugSetJobs(_ jobs: [VideoJob]) {
        self.jobs = jobs
    }

    func _debugSetQueueState(_ state: QueueRunState) {
        self.queueState = state
    }
}
