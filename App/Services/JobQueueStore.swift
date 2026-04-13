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

struct QueueExecutionState: Equatable {
    var runnerState: QueueRunState = .idle
    var scopeJobIDs = Set<UUID>()
    var activeJobID: UUID?
    var pausedJobID: UUID?
}

enum QueueJobDisplayStatus: Equatable {
    case queued
    case analyzing
    case ready
    case inQueue
    case running
    case paused
    case completed
    case failed
    case cancelled

    init(jobStatus: JobStatus) {
        switch jobStatus {
        case .queued: self = .queued
        case .analyzing: self = .analyzing
        case .ready: self = .ready
        case .running: self = .running
        case .paused: self = .paused
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .analyzing: return "Analyzing"
        case .ready: return "Ready"
        case .inQueue: return "In queue"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

@MainActor
final class JobQueueStore: ObservableObject {
    @Published private(set) var jobs: [VideoJob] = []
    @Published private(set) var queueState: QueueRunState = .idle
    @Published private(set) var queueElapsedSeconds: TimeInterval = 0
    @Published var selectedJobID: UUID?
    @Published var alertMessage: String?

    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let runner = FFmpegRunner()
    private let sourceBookmarkStore = SecurityScopedBookmarkStore()
    private let outputBookmarkStore = SecurityScopedBookmarkStore()
    private var queueTask: Task<Void, Never>?
    private var activeProcessingSessionID: UUID?
    private var executionState = QueueExecutionState()
    private var activeProgressJobIDs = Set<UUID>()
    private var elapsedTracker = QueueElapsedTracker()
    private var elapsedTimer: Timer?

    init(settingsStore: SettingsStore, historyStore: HistoryStore) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
    }

    var selectedJob: VideoJob? {
        guard let selectedJobID else { return nil }
        return jobs.first(where: { $0.id == selectedJobID })
    }

    var footerSummary: QueueFooterSummary {
        let displayStatuses = jobs.map { displayStatus(for: $0) }
        return QueueFooterSummary(
            queued: displayStatuses.filter { $0 == .ready || $0 == .queued || $0 == .analyzing || $0 == .inQueue }.count,
            processing: displayStatuses.filter { $0 == .running || $0 == .paused }.count,
            done: displayStatuses.filter { $0 == .completed }.count,
            failed: displayStatuses.filter { $0 == .failed }.count,
            totalInputSizeBytes: jobs.reduce(into: Int64(0)) { partialResult, job in
                partialResult += max(0, job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes ?? 0)
            }
        )
    }

    var isRunning: Bool {
        executionState.runnerState == .running
    }

    var isQueuePaused: Bool {
        executionState.runnerState == .paused
    }

    var canPause: Bool {
        executionState.runnerState == .running &&
        executionState.activeJobID != nil &&
        executionState.activeJobID.flatMap(jobStatus(for:)) == .running
    }

    var hasRunnableItems: Bool {
        !resolvedRunnableScopeJobIDs(selectedJobIDs: []).isEmpty
    }

    var canStartOrResume: Bool {
        canStartOrResume(selectedJobIDs: [])
    }

    var startButtonTitle: String {
        startButtonTitle(selectedJobIDs: [])
    }

    var hasClearableQueueItems: Bool {
        jobs.contains(where: { $0.status == .ready || $0.status == .queued || $0.status == .analyzing || $0.status == .paused })
    }

    var hasCompletedResults: Bool {
        jobs.contains(where: { $0.status == .completed || $0.status == .failed || $0.status == .cancelled })
    }

    var queueElapsedDisplay: String {
        let elapsed = Int(queueElapsedSeconds.rounded(.down))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var dockProgressFraction: Double? {
        guard executionState.runnerState == .running || executionState.runnerState == .paused || executionState.runnerState == .cancelling else {
            return nil
        }

        let trackedJobs = jobs.filter { activeProgressJobIDs.contains($0.id) }
        guard !trackedJobs.isEmpty else { return nil }

        let finishedCount = trackedJobs.filter(\.status.isTerminal).count
        let currentProgress = trackedJobs.first(where: { $0.status == .running || $0.status == .paused })?.progress ?? 0
        let fraction = (Double(finishedCount) + currentProgress) / Double(trackedJobs.count)
        return min(max(fraction, 0), 1)
    }

    func canStartOrResume(selectedJobIDs: Set<UUID> = []) -> Bool {
        guard executionState.runnerState != .running, executionState.runnerState != .cancelling else {
            return false
        }
        return !resolvedRunnableScopeJobIDs(selectedJobIDs: selectedJobIDs).isEmpty
    }

    func startButtonTitle(selectedJobIDs: Set<UUID> = []) -> String {
        let scopeJobIDs = resolvedRunnableScopeJobIDs(selectedJobIDs: selectedJobIDs)
        guard !scopeJobIDs.isEmpty else { return "Start" }
        return prioritizedPausedJobID(in: scopeJobIDs) != nil ? "Resume" : "Start"
    }

    func canCancel(selectedJobIDs: Set<UUID>) -> Bool {
        if selectedJobIDs.isEmpty {
            return executionState.runnerState != .idle &&
            (!executionState.scopeJobIDs.isEmpty || executionState.activeJobID != nil || executionState.pausedJobID != nil)
        }
        return jobs.contains {
            selectedJobIDs.contains($0.id) &&
            ($0.status == .ready || $0.status == .queued || $0.status == .analyzing || $0.status == .paused || $0.status == .running)
        }
    }

    func displayStatus(for jobID: UUID) -> QueueJobDisplayStatus? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        return displayStatus(for: job)
    }

    func displayStatus(for job: VideoJob) -> QueueJobDisplayStatus {
        let isActiveScope = executionState.scopeJobIDs.contains(job.id)
        if executionState.runnerState == .running,
           executionState.activeJobID == job.id,
           isActiveScope,
           (job.status == .ready || job.status == .running || job.status == .paused) {
            return .running
        }

        if (executionState.runnerState == .running || executionState.runnerState == .paused),
           job.status == .ready,
           isActiveScope {
            return .inQueue
        }

        return QueueJobDisplayStatus(jobStatus: job.status)
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
        let removingActiveJob = executionState.activeJobID.map(jobIDs.contains) ?? false
        let removingPausedJob = executionState.pausedJobID.map(jobIDs.contains) ?? false

        if removingActiveJob || (removingPausedJob && executionState.runnerState == .paused) {
            invalidateProcessingSession()
            runner.cancel(force: removingPausedJob && executionState.runnerState == .paused)
            setRunnerState(.idle)
            pauseElapsedTracking()
        }

        sourceBookmarkStore.remove(jobIDs: jobIDs)
        outputBookmarkStore.remove(jobIDs: jobIDs)
        executionState.scopeJobIDs.subtract(jobIDs)
        if removingActiveJob {
            executionState.activeJobID = nil
        }
        if removingPausedJob {
            executionState.pausedJobID = nil
        }
        activeProgressJobIDs.subtract(jobIDs)
        jobs.removeAll { jobIDs.contains($0.id) }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
        reconcileExecutionStateAfterMutation()
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
        outputBookmarkStore.remove(jobIDs: removedIDs)
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
        outputBookmarkStore.remove(jobIDs: removedIDs)
        jobs.removeAll { job in
            job.status == .completed || job.status == .failed || job.status == .cancelled
        }
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = jobs.first?.id
        }
        reconcileExecutionStateAfterMutation()
    }

    func clearAllItems() {
        resetQueueRuntimeState()
        let allJobIDs = Set(jobs.map(\.id))
        sourceBookmarkStore.remove(jobIDs: allJobIDs)
        outputBookmarkStore.remove(jobIDs: allJobIDs)
        jobs.removeAll()
        selectedJobID = nil
    }

    func toggleStartPause(selectedJobIDs: Set<UUID>) {
        if executionState.runnerState == .running {
            pauseCurrentJob()
            return
        }
        startOrResume(selectedJobIDs: selectedJobIDs)
    }

    func startOrResume(selectedJobIDs: Set<UUID> = []) {
        guard executionState.runnerState != .running, executionState.runnerState != .cancelling else { return }

        let scopeJobIDs = resolvedRunnableScopeJobIDs(selectedJobIDs: selectedJobIDs)
        guard !scopeJobIDs.isEmpty else {
            alertMessage = noRunnableItemsMessage(for: selectedJobIDs)
            return
        }

        guard settingsStore.hasRequiredBinaries else {
            alertMessage = "FFmpeg and FFprobe must both be configured before starting the queue."
            settingsStore.shouldShowFFmpegSetup = true
            return
        }
        if let unavailableCodec = firstUnavailableCodec(in: scopeJobIDs) {
            alertMessage = "\(unavailableCodec.displayName) is not available in your FFmpeg build. Choose another codec or install missing encoders."
            return
        }
        if let customCommandError = firstInvalidCustomCommandError(in: scopeJobIDs) {
            alertMessage = customCommandError
            return
        }
        if let externalAudioError = firstInvalidExternalAudioError(in: scopeJobIDs) {
            alertMessage = externalAudioError
            return
        }
        if let subtitleError = firstInvalidSubtitleAttachmentError(in: scopeJobIDs) {
            alertMessage = subtitleError
            return
        }

        if executionState.runnerState == .paused,
           let pausedJobID = executionState.pausedJobID,
           scopeJobIDs.contains(pausedJobID),
           jobStatus(for: pausedJobID) == .paused {
            resumePausedJob(pausedJobID, in: scopeJobIDs)
            return
        }

        if executionState.runnerState == .paused {
            abandonPausedExecutionForNewScope()
        }

        beginProcessing(scopeJobIDs: scopeJobIDs)
    }

    func startQueue(selectedJobIDs: Set<UUID> = []) {
        startOrResume(selectedJobIDs: selectedJobIDs)
    }

    func pauseCurrentJob() {
        guard let activeJobID = executionState.activeJobID,
              let index = jobs.firstIndex(where: { $0.id == activeJobID && $0.status == .running }) else { return }

        if let previousPausedJobID = executionState.pausedJobID, previousPausedJobID != activeJobID {
            resetPausedJobForFreshRun(jobID: previousPausedJobID)
        }

        jobs[index].status = .paused
        runner.pause()
        executionState.pausedJobID = activeJobID
        executionState.activeJobID = nil
        setRunnerState(.paused)
        pauseElapsedTracking()
    }

    private func resumePausedJob(_ jobID: UUID, in scopeJobIDs: Set<UUID>) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID && $0.status == .paused }) else { return }

        executionState.scopeJobIDs = scopeJobIDs
        executionState.activeJobID = jobID
        executionState.pausedJobID = nil
        activeProgressJobIDs = scopeJobIDs
        jobs[index].status = .running
        runner.resume()
        setRunnerState(.running)
        elapsedTracker.startOrResume(at: Date())
        queueElapsedSeconds = elapsedTracker.elapsed(at: Date())
        startElapsedTimer()
    }

    func cancelCurrentJob(selectedJobIDs: Set<UUID> = []) {
        if selectedJobIDs.isEmpty {
            cancelAllRunningQueue()
            return
        }
        cancelSelectedJobs(selectedJobIDs)
    }

    private func cancelAllRunningQueue() {
        guard executionState.runnerState != .idle else { return }

        let forceCancel = executionState.runnerState == .paused
        let currentJobID = executionState.activeJobID ?? executionState.pausedJobID
        let pendingJobIDs = executionState.scopeJobIDs.subtracting(currentJobID.map { [$0] } ?? [])

        for index in jobs.indices where pendingJobIDs.contains(jobs[index].id) {
            resetPendingScopeJob(at: index)
        }

        executionState.scopeJobIDs.subtract(pendingJobIDs)
        activeProgressJobIDs.subtract(pendingJobIDs)

        guard let currentJobID else {
            invalidateProcessingSession()
            setRunnerState(.idle)
            pauseElapsedTracking()
            return
        }

        executionState.scopeJobIDs = [currentJobID]
        activeProgressJobIDs = [currentJobID]
        setRunnerState(.cancelling)
        queueTask?.cancel()

        if let currentIndex = jobs.firstIndex(where: { $0.id == currentJobID }) {
            switch jobs[currentIndex].status {
            case .ready, .queued, .analyzing, .paused, .running:
                markCancelled(at: currentIndex)
            default:
                break
            }
        }

        runner.cancel(force: forceCancel)
    }

    private func cancelSelectedJobs(_ jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty else { return }

        for index in jobs.indices where jobIDs.contains(jobs[index].id) {
            switch jobs[index].status {
            case .ready, .queued, .analyzing, .paused:
                markCancelled(at: index)
                executionState.scopeJobIDs.remove(jobs[index].id)
                if executionState.pausedJobID == jobs[index].id {
                    executionState.pausedJobID = nil
                }
            case .running:
                markCancelled(at: index)
                executionState.scopeJobIDs.remove(jobs[index].id)
                runner.cancel()
            default:
                break
            }
        }

        if executionState.runnerState == .paused, executionState.pausedJobID == nil {
            invalidateProcessingSession()
            runner.cancel(force: true)
            setRunnerState(.idle)
            pauseElapsedTracking()
        }

        reconcileExecutionStateAfterMutation()
    }

    func cancel(jobID: UUID) {
        if executionState.activeJobID == jobID, jobs.first(where: { $0.id == jobID && $0.status == .running }) != nil {
            runner.cancel()
            return
        }

        if executionState.pausedJobID == jobID, executionState.runnerState == .paused {
            if let index = jobs.firstIndex(where: { $0.id == jobID }) {
                markCancelled(at: index)
            }
            executionState.scopeJobIDs.remove(jobID)
            executionState.pausedJobID = nil
            invalidateProcessingSession()
            runner.cancel(force: true)
            setRunnerState(.idle)
            pauseElapsedTracking()
            return
        }

        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        markCancelled(at: index)
        executionState.scopeJobIDs.remove(jobID)
        if executionState.pausedJobID == jobID {
            executionState.pausedJobID = nil
        }
        reconcileExecutionStateAfterMutation()
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil
        jobs[index].ffmpegVersion = nil
        jobs[index].result = nil
        jobs[index].executionSnapshot = nil
        jobs[index].completedAt = nil
    }

    func retryFailedJobs() {
        let failedJobIDs = jobs
            .filter { $0.status == .failed || $0.status == .cancelled }
            .map(\.id)

        for jobID in failedJobIDs {
            retry(jobID: jobID)
        }
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
        applyDefaultOutputDirectoryToUnsetJobs()
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
            setOutputDirectory(url, for: jobIDs)
        }
    }

    func setOutputDirectory(_ url: URL, for jobIDs: Set<UUID>) {
        guard !jobIDs.isEmpty, isDirectory(url) else { return }

        for index in jobs.indices
        where jobIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].outputDirectory = url
            outputBookmarkStore.store(url: url, for: jobs[index].id)
        }
    }

    func applyDefaultOutputDirectoryToUnsetJobs() {
        guard let defaultURL = settingsStore.defaultOutputDirectoryURL else { return }
        let jobIDs = Set(jobs.lazy.filter { $0.outputDirectory == nil }.map(\.id))
        setOutputDirectory(defaultURL, for: jobIDs)
    }

    func revealOutput(for jobID: UUID) {
        guard let outputURL = jobs.first(where: { $0.id == jobID })?.result?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func openOutputFolder(for jobID: UUID) {
        guard let outputURL = jobs.first(where: { $0.id == jobID })?.result?.outputURL else { return }
        let folderURL = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folderURL.path) else { return }
        NSWorkspace.shared.open(folderURL)
    }

    func openSource(for jobID: UUID) {
        guard let sourceURL = jobs.first(where: { $0.id == jobID })?.sourceURL else { return }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            alertMessage = "Source file not found."
            return
        }
        NSWorkspace.shared.open(sourceURL)
    }

    func revealSelectedOutput() {
        guard let selectedJobID else { return }
        revealOutput(for: selectedJobID)
    }

    func openCompletedOutput(for jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              job.status == .completed,
              let outputURL = job.result?.outputURL else { return }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            alertMessage = "Output file not found."
            return
        }

        NSWorkspace.shared.open(outputURL)
    }

    func applyOptions(_ options: ConversionOptions, to jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
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
        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            if let value = preview[jobs[index].id] {
                jobs[index].outputFilename = value
            }
        }
    }

    func replaceSubtitleAttachments(_ attachments: [SubtitleAttachment], for jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.subtitleAttachments = attachments
        }
    }

    func appendSubtitleAttachments(_ attachments: [SubtitleAttachment], for jobIDs: Set<UUID>?) {
        guard !attachments.isEmpty else { return }
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.subtitleAttachments = mergedUniqueSubtitleAttachments(
                existing: jobs[index].options.subtitleAttachments,
                newAttachments: attachments
            )
        }
    }

    func updateSubtitleAttachmentLanguage(_ attachmentID: UUID, languageCode: String, for jobIDs: Set<UUID>?) {
        let normalizedLanguageCode = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            guard let attachmentIndex = jobs[index].options.subtitleAttachments.firstIndex(where: { $0.id == attachmentID }) else { continue }
            jobs[index].options.subtitleAttachments[attachmentIndex].languageCode = normalizedLanguageCode.isEmpty ? "eng" : normalizedLanguageCode
        }
    }

    func removeSubtitleAttachment(_ attachmentID: UUID, for jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.subtitleAttachments.removeAll { $0.id == attachmentID }
        }
    }

    func chooseSubtitleAttachmentURLs() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["srt", "ass", "vtt"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Add Subtitles"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

    func appendExternalAudioAttachments(_ attachments: [ExternalAudioAttachment], for jobIDs: Set<UUID>?) {
        guard !attachments.isEmpty else { return }
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.externalAudioAttachments = mergedUniqueExternalAudioAttachments(
                existing: jobs[index].options.externalAudioAttachments,
                newAttachments: attachments
            )
        }
    }

    func removeExternalAudioAttachment(_ attachmentID: UUID, for jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.externalAudioAttachments.removeAll { $0.id == attachmentID }
        }
    }

    func clearExternalAudioAttachments(for jobIDs: Set<UUID>?) {
        let targetIDs: Set<UUID> = {
            if let jobIDs, !jobIDs.isEmpty {
                return jobIDs
            }
            return Set(jobs.map(\.id))
        }()

        for index in jobs.indices
        where targetIDs.contains(jobs[index].id) && !isConfigurationLocked(for: jobs[index]) {
            jobs[index].options.externalAudioAttachments = []
        }
    }

    func chooseExternalAudioURLs() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.supportedExternalAudioContentTypes
        panel.prompt = "Add Audio Tracks"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
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

    private func processPendingJobs(sessionID: UUID) async {
        while isActiveSession(sessionID) {
            guard let nextIndex = nextRunnableJobIndex(in: executionState.scopeJobIDs) else {
                break
            }

            await runJob(at: nextIndex, sessionID: sessionID)

            if Task.isCancelled || !isActiveSession(sessionID) || executionState.runnerState == .idle {
                break
            }
        }

        finishProcessing(sessionID: sessionID)
    }

    private func runJob(at index: Int, sessionID: UUID) async {
        guard isActiveSession(sessionID), jobs.indices.contains(index) else { return }

        let jobID = jobs[index].id
        executionState.activeJobID = jobID
        if executionState.pausedJobID == jobID {
            executionState.pausedJobID = nil
        }

        jobs[index].status = .running
        jobs[index].startedAt = Date()
        jobs[index].completedAt = nil
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil
        jobs[index].ffmpegVersion = nil
        jobs[index].executionSnapshot = JobExecutionSnapshot(
            options: jobs[index].options,
            outputDirectory: jobs[index].outputDirectory,
            outputFilename: jobs[index].outputFilename
        )
        setRunnerState(.running)

        do {
            let appSettings = settingsStore.settings
            let ffmpegURL = settingsStore.ffmpegURL
            let capabilities = settingsStore.encoderCapabilities
            let sourceURL = jobs[index].sourceURL
            let result = try await withAccessibleSourceURL(for: jobID, fallbackURL: sourceURL) { accessibleSourceURL in
                var runnableJob = jobs[index]
                if let executionSnapshot = jobs[index].executionSnapshot {
                    runnableJob.options = executionSnapshot.options
                    runnableJob.outputDirectory = executionSnapshot.outputDirectory
                    runnableJob.outputFilename = executionSnapshot.outputFilename
                }
                runnableJob.sourceURL = accessibleSourceURL
                return try await withAccessibleOutputDirectory(for: runnableJob) { accessibleOutputDirectory in
                    runnableJob.outputDirectory = accessibleOutputDirectory
                    return try await withAccessibleAncillaryURLs(for: runnableJob) {
                        if let ffmpegURL {
                            if let invocation = try? FFmpegCommandBuilder.buildInvocation(
                                for: runnableJob,
                                ffmpegURL: ffmpegURL,
                                settings: appSettings,
                                capabilities: capabilities
                            ) {
                                jobs[index].commandLine = invocation.commandLine
                            } else {
                                jobs[index].commandLine = nil
                            }
                        }

                        return try await runner.run(
                            job: runnableJob,
                            ffmpegURL: ffmpegURL,
                            settings: appSettings,
                            capabilities: capabilities
                        ) { [weak self] progress in
                            self?.applyProgress(progress, to: jobID, sessionID: sessionID)
                        }
                    }
                }
            }

            guard isActiveSession(sessionID),
                  let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            var completedResult = result
            if completedResult.outputFileSize == nil,
               let outputURL = completedResult.outputURL {
                completedResult.outputFileSize = readFileSize(at: outputURL)
            }
            jobs[refreshedIndex].status = .completed
            jobs[refreshedIndex].progress = 1
            jobs[refreshedIndex].estimatedRemainingSeconds = 0
            jobs[refreshedIndex].result = completedResult
            jobs[refreshedIndex].ffmpegVersion = runner.lastResolvedVersion
            jobs[refreshedIndex].completedAt = Date()
            historyStore.append(job: jobs[refreshedIndex])
        } catch {
            guard isActiveSession(sessionID),
                  let refreshedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
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
            jobs[refreshedIndex].ffmpegVersion = runner.lastResolvedVersion
            jobs[refreshedIndex].completedAt = Date()
            historyStore.append(job: jobs[refreshedIndex])
        }

        executionState.activeJobID = nil
        if executionState.runnerState == .paused && executionState.pausedJobID == nil {
            setRunnerState(.idle)
            pauseElapsedTracking()
        }
    }

    private func applyProgress(_ progress: FFmpegProgress, to jobID: UUID, sessionID: UUID) {
        guard isActiveSession(sessionID),
              let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
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
        if let estimate = OutputSizeEstimator.estimate(for: job) {
            job.estimatedOutputSizeBytes = estimate.outputBytes
            job.estimatedOutputDeltaPercent = estimate.deltaPercent
        } else {
            job.estimatedOutputSizeBytes = nil
            job.estimatedOutputDeltaPercent = nil
        }
    }

    private func firstUnavailableCodec(in scopeJobIDs: Set<UUID>) -> VideoCodec? {
        let capabilities = settingsStore.encoderCapabilities
        for job in jobs where scopeJobIDs.contains(job.id) {
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

    private func firstInvalidCustomCommandError(in scopeJobIDs: Set<UUID>) -> String? {
        for job in jobs where scopeJobIDs.contains(job.id) {
            let validation = FFmpegCommandBuilder.validateCustomCommandTemplate(
                job.options.effectiveCustomCommandTemplate,
                enabled: job.options.isCustomCommandEnabled
            )
            if let error = validation.errorMessage {
                return error
            }
        }
        return nil
    }

    private func firstInvalidExternalAudioError(in scopeJobIDs: Set<UUID>) -> String? {
        for job in jobs where scopeJobIDs.contains(job.id) {
            for attachment in job.options.externalAudioAttachments {
                let url = attachment.fileURL
                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    return "An external audio track is missing or unreadable."
                }
            }
        }
        return nil
    }

    private func firstInvalidSubtitleAttachmentError(in scopeJobIDs: Set<UUID>) -> String? {
        for job in jobs where scopeJobIDs.contains(job.id) {
            for attachment in job.options.subtitleAttachments {
                let url = attachment.fileURL
                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    return "A subtitle file is missing or unreadable."
                }
            }
        }
        return nil
    }

    private func mergedUniqueSubtitleAttachments(
        existing: [SubtitleAttachment],
        newAttachments: [SubtitleAttachment]
    ) -> [SubtitleAttachment] {
        var merged = existing
        var seenPaths = Set(existing.map { $0.fileURL.standardizedFileURL.path })
        for attachment in newAttachments where !seenPaths.contains(attachment.fileURL.standardizedFileURL.path) {
            merged.append(attachment)
            seenPaths.insert(attachment.fileURL.standardizedFileURL.path)
        }
        return merged
    }

    private func mergedUniqueExternalAudioAttachments(
        existing: [ExternalAudioAttachment],
        newAttachments: [ExternalAudioAttachment]
    ) -> [ExternalAudioAttachment] {
        var merged = existing
        var seenPaths = Set(existing.map { $0.fileURL.standardizedFileURL.path })
        for attachment in newAttachments where !seenPaths.contains(attachment.fileURL.standardizedFileURL.path) {
            merged.append(attachment)
            seenPaths.insert(attachment.fileURL.standardizedFileURL.path)
        }
        return merged
    }

    private func withAccessibleAncillaryURLs<T>(
        for job: VideoJob,
        operation: () async throws -> T
    ) async throws -> T {
        let urls = job.options.subtitleAttachments.map(\.fileURL) + job.options.externalAudioAttachments.map(\.fileURL)
        var activeScopedURLs = [URL]()
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                activeScopedURLs.append(url)
            }
        }
        defer {
            for url in activeScopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
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
        let forceCancel = executionState.runnerState == .paused
        invalidateProcessingSession()
        runner.cancel(force: forceCancel)
        executionState = QueueExecutionState()
        activeProgressJobIDs.removeAll()
        queueState = .idle
        elapsedTracker.reset()
        queueElapsedSeconds = 0
        stopElapsedTimer()
    }

    private func reconcileExecutionStateAfterMutation() {
        let existingJobIDs = Set(jobs.map(\.id))

        executionState.scopeJobIDs.formIntersection(existingJobIDs)
        activeProgressJobIDs.formIntersection(existingJobIDs)

        if let activeJobID = executionState.activeJobID,
           jobStatus(for: activeJobID) != .running {
            executionState.activeJobID = nil
        }

        if let pausedJobID = executionState.pausedJobID,
           jobStatus(for: pausedJobID) != .paused {
            executionState.pausedJobID = nil
        }

        let hasRunningJobs = jobs.contains(where: { $0.status == .running })
        let hasPausedJobs = jobs.contains(where: { $0.status == .paused })

        switch executionState.runnerState {
        case .running:
            if executionState.activeJobID == nil && !hasRunningJobs {
                setRunnerState(.idle)
                executionState.scopeJobIDs.removeAll()
                activeProgressJobIDs.removeAll()
                pauseElapsedTracking()
            }
        case .paused:
            if executionState.pausedJobID == nil && !hasPausedJobs {
                invalidateProcessingSession()
                setRunnerState(.idle)
                executionState.scopeJobIDs.removeAll()
                activeProgressJobIDs.removeAll()
                pauseElapsedTracking()
            }
        case .cancelling:
            if !hasRunningJobs && !hasPausedJobs {
                setRunnerState(.idle)
                executionState.scopeJobIDs.removeAll()
                activeProgressJobIDs.removeAll()
                pauseElapsedTracking()
            }
        case .idle:
            executionState.scopeJobIDs = executionState.scopeJobIDs.intersection(existingJobIDs)
        }
    }

    private func isRunnableStatus(_ status: JobStatus) -> Bool {
        status == .ready || status == .paused
    }

    private func isConfigurationLocked(for job: VideoJob) -> Bool {
        job.status == .running || job.status == .paused
    }

    private func resolvedRunnableScopeJobIDs(selectedJobIDs: Set<UUID>) -> Set<UUID> {
        let scopeSelection = selectedJobIDs.isEmpty ? Set(jobs.map(\.id)) : selectedJobIDs
        return Set(jobs.compactMap { job in
            guard scopeSelection.contains(job.id), isRunnableStatus(job.status) else { return nil }
            return job.id
        })
    }

    private func prioritizedPausedJobID(in scopeJobIDs: Set<UUID>) -> UUID? {
        guard let pausedJobID = executionState.pausedJobID,
              scopeJobIDs.contains(pausedJobID),
              let status = jobStatus(for: pausedJobID),
              isRunnableStatus(status) else {
            return nil
        }
        return pausedJobID
    }

    private func nextRunnableJobIndex(in scopeJobIDs: Set<UUID>) -> Int? {
        if let prioritizedJobID = prioritizedPausedJobID(in: scopeJobIDs),
           let prioritizedIndex = jobs.firstIndex(where: { $0.id == prioritizedJobID && scopeJobIDs.contains($0.id) && isRunnableStatus($0.status) }) {
            return prioritizedIndex
        }

        return jobs.firstIndex(where: { scopeJobIDs.contains($0.id) && isRunnableStatus($0.status) })
    }

    private func beginProcessing(scopeJobIDs: Set<UUID>) {
        let sessionID = UUID()

        prepareJobsForFreshRun(scopeJobIDs: scopeJobIDs)
        executionState.scopeJobIDs = scopeJobIDs
        executionState.activeJobID = nextRunnableJobIndex(in: scopeJobIDs).map { jobs[$0].id }
        activeProgressJobIDs = scopeJobIDs
        activeProcessingSessionID = sessionID
        setRunnerState(.running)
        elapsedTracker.reset()
        elapsedTracker.startOrResume(at: Date())
        queueElapsedSeconds = elapsedTracker.elapsed(at: Date())
        startElapsedTimer()
        queueTask = Task { [weak self] in
            await self?.processPendingJobs(sessionID: sessionID)
        }
    }

    private func abandonPausedExecutionForNewScope() {
        guard executionState.runnerState == .paused else { return }
        invalidateProcessingSession()
        runner.cancel(force: true)
        executionState.scopeJobIDs.removeAll()
        executionState.activeJobID = nil
        activeProgressJobIDs.removeAll()
        setRunnerState(.idle)
        pauseElapsedTracking()
    }

    private func prepareJobsForFreshRun(scopeJobIDs: Set<UUID>) {
        for jobID in scopeJobIDs {
            resetPausedJobForFreshRun(jobID: jobID)
        }
    }

    private func resetPendingScopeJob(at index: Int) {
        if jobs[index].status == .paused {
            cleanupPartialOutput(for: jobs[index])
        }
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].estimatedRemainingSeconds = nil
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil
        jobs[index].ffmpegVersion = nil
        jobs[index].result = nil
        jobs[index].executionSnapshot = nil
        jobs[index].startedAt = nil
        jobs[index].completedAt = nil
    }

    private func resetPausedJobForFreshRun(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID && $0.status == .paused }) else { return }

        cleanupPartialOutput(for: jobs[index])
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].estimatedRemainingSeconds = nil
        jobs[index].errorMessage = nil
        jobs[index].errorDetails = nil
        jobs[index].commandLine = nil
        jobs[index].ffmpegVersion = nil
        jobs[index].result = nil
        jobs[index].executionSnapshot = nil
        jobs[index].startedAt = nil
        jobs[index].completedAt = nil
    }

    private func cleanupPartialOutput(for job: VideoJob) {
        let performCleanup = { [self] in
            let outputURL = FFmpegCommandBuilder.outputURL(for: job, settings: self.settingsStore.settings)
            guard FileManager.default.fileExists(atPath: outputURL.path) else { return }
            try? FileManager.default.removeItem(at: outputURL)
        }

        if let accessibleOutputDirectory = accessibleOutputDirectoryURL(for: job) {
            let didStart = accessibleOutputDirectory.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    accessibleOutputDirectory.stopAccessingSecurityScopedResource()
                }
            }
            performCleanup()
            return
        }

        performCleanup()
    }

    private func markCancelled(at index: Int) {
        jobs[index].status = .cancelled
        jobs[index].errorMessage = "Cancelled by user."
        jobs[index].errorDetails = "Conversion cancelled by user."
    }

    private func finishProcessing(sessionID: UUID) {
        guard isActiveSession(sessionID) else { return }
        activeProcessingSessionID = nil
        queueTask = nil
        executionState.activeJobID = nil
        executionState.scopeJobIDs.removeAll()
        activeProgressJobIDs.removeAll()
        if executionState.runnerState != .paused {
            setRunnerState(.idle)
            pauseElapsedTracking()
        }
    }

    private func invalidateProcessingSession() {
        activeProcessingSessionID = nil
        queueTask?.cancel()
        queueTask = nil
    }

    private func isActiveSession(_ sessionID: UUID) -> Bool {
        activeProcessingSessionID == sessionID
    }

    private func setRunnerState(_ state: QueueRunState) {
        executionState.runnerState = state
        queueState = state
    }

    private func pauseElapsedTracking() {
        elapsedTracker.pause(at: Date())
        queueElapsedSeconds = elapsedTracker.elapsed(at: Date())
        stopElapsedTimer()
    }

    private func noRunnableItemsMessage(for selectedJobIDs: Set<UUID>) -> String {
        selectedJobIDs.isEmpty ? "No runnable items in the queue." : "No runnable items in the current selection."
    }

    private func jobStatus(for jobID: UUID) -> JobStatus? {
        jobs.first(where: { $0.id == jobID })?.status
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

    private func withAccessibleOutputDirectory<T>(
        for job: VideoJob,
        operation: (URL?) async throws -> T
    ) async throws -> T {
        guard let accessibleURL = accessibleOutputDirectoryURL(for: job) else {
            return try await operation(job.outputDirectory)
        }

        let didStart = accessibleURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation(accessibleURL)
    }

    private func accessibleOutputDirectoryURL(for job: VideoJob) -> URL? {
        if job.outputDirectory != nil {
            return outputBookmarkStore.resolvedURL(for: job.id) ?? job.outputDirectory
        }
        return settingsStore.defaultOutputDirectoryURL
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func startElapsedTimer() {
        guard elapsedTimer == nil else { return }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.queueElapsedSeconds = self.elapsedTracker.elapsed(at: Date())
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
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

    static var supportedExternalAudioContentTypes: [UTType] {
        let extensions = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "aif", "aiff"]
        return [.audio] + extensions.compactMap { UTType(filenameExtension: $0) }
    }
}

extension JobQueueStore {
    func _debugSetJobs(_ jobs: [VideoJob]) {
        self.jobs = jobs
    }

    func _debugSetQueueState(_ state: QueueRunState) {
        self.executionState.runnerState = state
        self.queueState = state
    }

    func _debugSetExecutionState(
        _ state: QueueRunState,
        scopeJobIDs: Set<UUID> = [],
        activeJobID: UUID? = nil,
        pausedJobID: UUID? = nil
    ) {
        executionState = QueueExecutionState(
            runnerState: state,
            scopeJobIDs: scopeJobIDs,
            activeJobID: activeJobID,
            pausedJobID: pausedJobID
        )
        queueState = state
    }

    func _debugExecutionState() -> QueueExecutionState {
        executionState
    }
}

struct QueueElapsedTracker {
    private(set) var accumulatedSeconds: TimeInterval = 0
    private(set) var runningSince: Date?

    mutating func startOrResume(at date: Date) {
        guard runningSince == nil else { return }
        runningSince = date
    }

    mutating func pause(at date: Date) {
        guard let runningSince else { return }
        accumulatedSeconds += max(0, date.timeIntervalSince(runningSince))
        self.runningSince = nil
    }

    mutating func reset() {
        accumulatedSeconds = 0
        runningSince = nil
    }

    func elapsed(at date: Date) -> TimeInterval {
        if let runningSince {
            return accumulatedSeconds + max(0, date.timeIntervalSince(runningSince))
        }
        return accumulatedSeconds
    }
}

struct OutputSizeEstimate: Equatable {
    let outputBytes: Int64
    let deltaPercent: Double?
}

enum OutputSizeEstimator {
    static func estimate(for job: VideoJob) -> OutputSizeEstimate? {
        guard let duration = job.metadata?.durationSeconds, duration > 0 else { return nil }

        let videoBitrate = estimatedVideoBitrate(for: job)
        let audioBitrate = estimatedAudioBitrate(for: job)
        let totalBitrate = max(0, videoBitrate + audioBitrate)
        guard totalBitrate > 0 else { return nil }

        let bytes = Int64((Double(totalBitrate) * duration) / 8.0)
        let clampedBytes = max(Int64(0), bytes)

        let sourceSize = job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes
        let deltaPercent: Double? = {
            guard let sourceSize, sourceSize > 0 else { return nil }
            return (Double(clampedBytes - sourceSize) / Double(sourceSize)) * 100.0
        }()

        return OutputSizeEstimate(outputBytes: clampedBytes, deltaPercent: deltaPercent)
    }

    static func estimateFromTotalBitrate(durationSeconds: Double, totalBitrateBitsPerSecond: Int) -> Int64? {
        guard durationSeconds > 0, totalBitrateBitsPerSecond > 0 else { return nil }
        return Int64((Double(totalBitrateBitsPerSecond) * durationSeconds) / 8.0)
    }

    private static func estimatedVideoBitrate(for job: VideoJob) -> Int {
        guard !job.options.isAudioOnly else { return 0 }

        if let custom = job.options.videoBitrateKbps, custom > 0 {
            return custom * 1_000
        }

        guard let sourceVideo = job.metadata?.videoStream else { return 0 }
        let sourceWidth = max(1, sourceVideo.width ?? 1920)
        let sourceHeight = max(1, sourceVideo.height ?? 1080)
        let targetDimensions = job.options.resolutionOverride.dimensions ?? (sourceWidth, sourceHeight)
        let targetWidth = max(1, targetDimensions.0)
        let targetHeight = max(1, targetDimensions.1)

        let sourceFPS = max(1.0, sourceVideo.frameRateValue ?? 30.0)
        let targetFPS: Double = {
            if let fps = job.options.frameRateOption.numericValue { return fps }
            if job.options.frameRateOption == .custom, let fps = job.options.customFrameRate, fps > 0 { return fps }
            return sourceFPS
        }()

        let heuristicBPPF = bitsPerPixelPerFrame(
            codec: job.options.videoCodec,
            quality: job.options.qualityProfile,
            encoderOption: job.options.effectiveEncoderOption
        )
        let sourceBPPF = derivedSourceBitsPerPixelPerFrame(
            stream: sourceVideo,
            fallbackTotalBitrate: job.metadata?.format.bitRate.flatMap(Int.init),
            sourceAudioBitrate: job.metadata?.audioStreams.first?.bitRate.flatMap(Int.init)
        )
        let blendedBPPF = blendedBitsPerPixelPerFrame(
            heuristic: heuristicBPPF,
            source: sourceBPPF,
            codec: job.options.videoCodec
        )
        let hdrMultiplier = job.metadata?.isHDR == true ? 1.08 : 1.0
        let baseBitrate = Double(targetWidth * targetHeight) * targetFPS * blendedBPPF * hdrMultiplier
        return Int(max(0, baseBitrate))
    }

    private static func estimatedAudioBitrate(for job: VideoJob) -> Int {
        let sourceAudioBitrate = job.metadata?.audioStreams.first?.bitRate.flatMap(Int.init)
        switch job.options.audioCodec {
        case .copy:
            if let sourceBitrate = sourceAudioBitrate, sourceBitrate > 0 {
                return sourceBitrate
            }
            return 192_000
        case .aac:
            return (job.options.effectiveAudioBitrateKbps ?? sourceAudioBitrate.map { max(96, $0 / 1_000) } ?? 192) * 1_000
        case .mp3:
            return (job.options.effectiveAudioBitrateKbps ?? sourceAudioBitrate.map { max(96, $0 / 1_000) } ?? 192) * 1_000
        case .pcm:
            return 1_536_000
        }
    }

    private static func bitsPerPixelPerFrame(
        codec: VideoCodec,
        quality: QualityProfile,
        encoderOption: EncoderOption
    ) -> Double {
        let base: Double
        switch codec {
        case .h264:
            switch quality {
            case .smaller: base = 0.075
            case .balanced: base = 0.095
            case .better: base = 0.115
            }
        case .hevc, .vp9:
            switch quality {
            case .smaller: base = 0.055
            case .balanced: base = 0.070
            case .better: base = 0.085
            }
        case .av1:
            switch quality {
            case .smaller: base = 0.045
            case .balanced: base = 0.060
            case .better: base = 0.075
            }
        case .proRes:
            base = 0.95
        }
        return base * encoderSpeedMultiplier(encoderOption)
    }

    private static func encoderSpeedMultiplier(_ encoderOption: EncoderOption) -> Double {
        switch encoderOption {
        case .veryFast: return 1.18
        case .fast: return 1.08
        case .medium: return 1.0
        case .slow: return 0.9
        }
    }

    private static func derivedSourceBitsPerPixelPerFrame(
        stream: MediaMetadata.StreamInfo,
        fallbackTotalBitrate: Int?,
        sourceAudioBitrate: Int?
    ) -> Double? {
        let width = max(1, stream.width ?? 0)
        let height = max(1, stream.height ?? 0)
        let frameRate = max(1.0, stream.frameRateValue ?? 0)
        guard width > 0, height > 0, frameRate > 0 else { return nil }

        let rawBitrate: Int? = {
            if let videoBitrate = stream.bitRate.flatMap(Int.init), videoBitrate > 0 {
                return videoBitrate
            }
            if let fallbackTotalBitrate, fallbackTotalBitrate > 0 {
                let audio = max(sourceAudioBitrate ?? 0, 0)
                return max(fallbackTotalBitrate - audio, 0)
            }
            return nil
        }()

        guard let bitrate = rawBitrate, bitrate > 0 else { return nil }
        return Double(bitrate) / (Double(width * height) * frameRate)
    }

    private static func blendedBitsPerPixelPerFrame(
        heuristic: Double,
        source: Double?,
        codec: VideoCodec
    ) -> Double {
        guard let source else { return heuristic }

        let lowerBound = heuristic * 0.55
        let upperBound = codec == .proRes ? heuristic * 1.3 : heuristic * 1.8
        let clampedSource = min(max(source, lowerBound), upperBound)
        return (heuristic * 0.65) + (clampedSource * 0.35)
    }
}
