import XCTest
@testable import ForgeFF

@MainActor
final class JobQueueStoreTests: XCTestCase {
    private func makeConfiguredSettingsStore() -> SettingsStore {
        SettingsStore(
            pathDetector: FFmpegPathDetector(
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                commandLookup: { _ in "/usr/bin/true" },
                pathExists: { FileManager.default.fileExists(atPath: $0) }
            )
        )
    }

    func testRemovingRunningJobWithNoRemainingItemsResetsToIdle() throws {
        let settings = SettingsStore(
            pathDetector: FFmpegPathDetector(
                isExecutable: { _ in false },
                commandLookup: { _ in nil },
                pathExists: { _ in false }
            )
        )
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-test-running-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var runningJob = VideoJob(sourceURL: tempURL)
        runningJob.status = .running
        store._debugSetJobs([runningJob])
        store._debugSetQueueState(.running)

        store.remove(jobIDs: [runningJob.id])

        XCTAssertEqual(store.queueState, .idle)
        XCTAssertEqual(store.startButtonTitle, "Start")
        XCTAssertFalse(store.canStartOrResume)
    }

    func testClearAfterCancelResetsToIdleAndStartWorksAfterReAdd() throws {
        let settings = SettingsStore(
            pathDetector: FFmpegPathDetector(
                isExecutable: { _ in false },
                commandLookup: { _ in nil },
                pathExists: { _ in false }
            )
        )
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-test-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        store.addFiles(urls: [tempURL])
        XCTAssertEqual(store.jobs.count, 1)

        var runningJob = VideoJob(sourceURL: tempURL)
        runningJob.status = .running
        store._debugSetJobs([runningJob])
        store._debugSetExecutionState(.running, scopeJobIDs: [runningJob.id], activeJobID: runningJob.id)

        store.cancelCurrentJob()
        XCTAssertEqual(store.queueState, .cancelling)

        store.clearAllItems()
        XCTAssertEqual(store.queueState, .idle)
        XCTAssertTrue(store.jobs.isEmpty)

        store.addFiles(urls: [tempURL])
        XCTAssertEqual(store.jobs.count, 1)
        var readyJob = store.jobs[0]
        readyJob.status = .ready
        store._debugSetJobs([readyJob])
        XCTAssertTrue(store.canStartOrResume)
        XCTAssertEqual(store.startButtonTitle, "Start")
    }

    func testFinderOpenAddsSelectedFileBesideItsSource() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)
        let sourceFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("forgeff-open-with-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let sourceURL = sourceFolder.appendingPathComponent("camera.mp4")
        try Data(repeating: 1, count: 128).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceFolder) }

        let jobIDs = store.addFiles(urls: [sourceURL], outputBesideSource: true)

        XCTAssertEqual(jobIDs.count, 1)
        XCTAssertEqual(store.jobs.first?.sourceURL, sourceURL)
        XCTAssertEqual(store.jobs.first?.outputDirectory, sourceFolder)
        XCTAssertEqual(store.selectedJobID, jobIDs.first)
    }

    func testPausedScopeRemovalResetsStateToIdleAndStartLabel() throws {
        let settings = SettingsStore(
            pathDetector: FFmpegPathDetector(
                isExecutable: { _ in false },
                commandLookup: { _ in nil },
                pathExists: { _ in false }
            )
        )
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-test-paused-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var pausedJob = VideoJob(sourceURL: tempURL)
        pausedJob.status = .paused
        store._debugSetJobs([pausedJob])
        store._debugSetQueueState(.paused)

        store.remove(jobIDs: [pausedJob.id])

        XCTAssertEqual(store.queueState, .idle)
        XCTAssertEqual(store.startButtonTitle, "Start")
    }

    func testStartButtonTitleUsesSelectionScopedResumeEligibility() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let pausedURL = baseURL.appendingPathComponent("forgeff-test-title-paused-\(UUID().uuidString).mkv")
        let readyURL = baseURL.appendingPathComponent("forgeff-test-title-ready-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: pausedURL)
        try Data(repeating: 1, count: 1024).write(to: readyURL)
        defer {
            try? FileManager.default.removeItem(at: pausedURL)
            try? FileManager.default.removeItem(at: readyURL)
        }

        var pausedJob = VideoJob(sourceURL: pausedURL)
        pausedJob.status = .paused
        var readyJob = VideoJob(sourceURL: readyURL)
        readyJob.status = .ready

        store._debugSetJobs([pausedJob, readyJob])
        store._debugSetExecutionState(.paused, scopeJobIDs: Set([pausedJob.id, readyJob.id]), pausedJobID: pausedJob.id)

        XCTAssertEqual(store.startButtonTitle(selectedJobIDs: []), "Resume")
        XCTAssertEqual(store.startButtonTitle(selectedJobIDs: [readyJob.id]), "Start")
        XCTAssertTrue(store.canStartOrResume(selectedJobIDs: [readyJob.id]))
    }

    func testCancellingWithRemainingReadyAfterRemovalResetsToIdleAndCanStart() throws {
        let settings = SettingsStore(
            pathDetector: FFmpegPathDetector(
                isExecutable: { _ in false },
                commandLookup: { _ in nil },
                pathExists: { _ in false }
            )
        )
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let cancelledURL = baseURL.appendingPathComponent("forgeff-test-cancelled-\(UUID().uuidString).mkv")
        let readyURL = baseURL.appendingPathComponent("forgeff-test-ready-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: cancelledURL)
        try Data(repeating: 1, count: 1024).write(to: readyURL)
        defer {
            try? FileManager.default.removeItem(at: cancelledURL)
            try? FileManager.default.removeItem(at: readyURL)
        }

        var cancelledJob = VideoJob(sourceURL: cancelledURL)
        cancelledJob.status = .cancelled
        var readyJob = VideoJob(sourceURL: readyURL)
        readyJob.status = .ready

        store._debugSetJobs([cancelledJob, readyJob])
        store._debugSetQueueState(.cancelling)

        store.remove(jobIDs: [cancelledJob.id])

        XCTAssertEqual(store.queueState, .idle)
        XCTAssertEqual(store.startButtonTitle, "Start")
        XCTAssertTrue(store.canStartOrResume)
    }

    func testStartOrResumeTreatsPausedSelectionAsRunnable() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-test-paused-runnable-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var pausedJob = VideoJob(sourceURL: tempURL)
        pausedJob.status = .paused
        store._debugSetJobs([pausedJob])
        store._debugSetQueueState(.paused)

        store.startOrResume(selectedJobIDs: [pausedJob.id])

        XCTAssertEqual(store.queueState, .running)
        XCTAssertNil(store.alertMessage)
    }

    func testStartOrResumeUsesSelectionScopeForRunnablePredicate() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let pausedURL = baseURL.appendingPathComponent("forgeff-test-scope-paused-\(UUID().uuidString).mkv")
        let doneURL = baseURL.appendingPathComponent("forgeff-test-scope-done-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: pausedURL)
        try Data(repeating: 1, count: 1024).write(to: doneURL)
        defer {
            try? FileManager.default.removeItem(at: pausedURL)
            try? FileManager.default.removeItem(at: doneURL)
        }

        var pausedJob = VideoJob(sourceURL: pausedURL)
        pausedJob.status = .paused
        var doneJob = VideoJob(sourceURL: doneURL)
        doneJob.status = .completed
        store._debugSetJobs([pausedJob, doneJob])
        store._debugSetQueueState(.paused)

        store.startOrResume(selectedJobIDs: [doneJob.id])
        XCTAssertEqual(store.alertMessage, "No runnable items in the current selection.")

        store.startOrResume(selectedJobIDs: [pausedJob.id])
        XCTAssertEqual(store.queueState, .running)
    }

    func testStartOrResumeSelectionDoesNotReusePausedJobOutsideScope() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let pausedURL = baseURL.appendingPathComponent("forgeff-test-selection-paused-\(UUID().uuidString).mkv")
        let readyURL = baseURL.appendingPathComponent("forgeff-test-selection-ready-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: pausedURL)
        try Data(repeating: 1, count: 1024).write(to: readyURL)
        defer {
            try? FileManager.default.removeItem(at: pausedURL)
            try? FileManager.default.removeItem(at: readyURL)
        }

        var pausedJob = VideoJob(sourceURL: pausedURL)
        pausedJob.status = .paused
        var readyJob = VideoJob(sourceURL: readyURL)
        readyJob.status = .ready

        store._debugSetJobs([pausedJob, readyJob])
        store._debugSetExecutionState(.paused, scopeJobIDs: Set([pausedJob.id, readyJob.id]), pausedJobID: pausedJob.id)

        store.startOrResume(selectedJobIDs: [readyJob.id])

        let executionState = store._debugExecutionState()
        XCTAssertEqual(store.queueState, .running)
        XCTAssertEqual(executionState.scopeJobIDs, Set([readyJob.id]))
        XCTAssertEqual(executionState.pausedJobID, pausedJob.id)
        XCTAssertNil(store.alertMessage)
        XCTAssertEqual(store.jobs.first(where: { $0.id == pausedJob.id })?.status, .paused)
    }

    func testCancellingPausedSelectionClearsPausedStateToIdle() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let pausedURL = baseURL.appendingPathComponent("forgeff-test-cancel-paused-\(UUID().uuidString).mkv")
        let readyURL = baseURL.appendingPathComponent("forgeff-test-cancel-ready-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: pausedURL)
        try Data(repeating: 1, count: 1024).write(to: readyURL)
        defer {
            try? FileManager.default.removeItem(at: pausedURL)
            try? FileManager.default.removeItem(at: readyURL)
        }

        var pausedJob = VideoJob(sourceURL: pausedURL)
        pausedJob.status = .paused
        var readyJob = VideoJob(sourceURL: readyURL)
        readyJob.status = .ready

        store._debugSetJobs([pausedJob, readyJob])
        store._debugSetExecutionState(.paused, scopeJobIDs: Set([pausedJob.id, readyJob.id]), pausedJobID: pausedJob.id)

        store.cancelCurrentJob(selectedJobIDs: [pausedJob.id])

        let executionState = store._debugExecutionState()
        XCTAssertEqual(store.queueState, .idle)
        XCTAssertNil(executionState.pausedJobID)
        XCTAssertEqual(store.jobs.first(where: { $0.id == pausedJob.id })?.status, .cancelled)
        XCTAssertEqual(store.startButtonTitle(selectedJobIDs: []), "Start")
        XCTAssertTrue(store.canStartOrResume)
    }

    func testDisplayStatusMarksPlannedJobsAsInQueueAndActiveJobAsRunning() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let firstURL = baseURL.appendingPathComponent("forgeff-test-in-queue-1-\(UUID().uuidString).mkv")
        let secondURL = baseURL.appendingPathComponent("forgeff-test-in-queue-2-\(UUID().uuidString).mkv")
        let thirdURL = baseURL.appendingPathComponent("forgeff-test-in-queue-3-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: firstURL)
        try Data(repeating: 1, count: 1024).write(to: secondURL)
        try Data(repeating: 1, count: 1024).write(to: thirdURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
            try? FileManager.default.removeItem(at: thirdURL)
        }

        var firstJob = VideoJob(sourceURL: firstURL)
        firstJob.status = .ready
        var secondJob = VideoJob(sourceURL: secondURL)
        secondJob.status = .ready
        var thirdJob = VideoJob(sourceURL: thirdURL)
        thirdJob.status = .ready

        store._debugSetJobs([firstJob, secondJob, thirdJob])
        store._debugSetExecutionState(
            .running,
            scopeJobIDs: Set([firstJob.id, secondJob.id, thirdJob.id]),
            activeJobID: firstJob.id
        )

        XCTAssertEqual(store.displayStatus(for: firstJob.id), .running)
        XCTAssertEqual(store.displayStatus(for: secondJob.id), .inQueue)
        XCTAssertEqual(store.displayStatus(for: thirdJob.id), .inQueue)
        XCTAssertEqual(store.footerSummary.processing, 1)
        XCTAssertEqual(store.footerSummary.queued, 2)
    }

    func testNewReadyJobJoinsFullQueueScopeWhileRunning() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let runningURL = baseURL.appendingPathComponent("forgeff-test-running-full-\(UUID().uuidString).mkv")
        let newURL = baseURL.appendingPathComponent("forgeff-test-new-full-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: runningURL)
        try Data(repeating: 1, count: 1024).write(to: newURL)
        defer {
            try? FileManager.default.removeItem(at: runningURL)
            try? FileManager.default.removeItem(at: newURL)
        }

        var runningJob = VideoJob(sourceURL: runningURL)
        runningJob.status = .running
        var newJob = VideoJob(sourceURL: newURL)
        newJob.status = .ready

        store._debugSetJobs([runningJob, newJob])
        store._debugSetExecutionState(
            .running,
            scopeMode: .fullQueue,
            scopeJobIDs: [runningJob.id],
            activeJobID: runningJob.id
        )

        store._debugAdmitNewJobIntoActiveScope(jobID: newJob.id)

        let executionState = store._debugExecutionState()
        XCTAssertTrue(executionState.scopeJobIDs.contains(newJob.id))
        XCTAssertEqual(store.displayStatus(for: newJob.id), .inQueue)
    }

    func testNewReadyJobJoinsSelectionScopeWhileRunning() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let runningURL = baseURL.appendingPathComponent("forgeff-test-running-selection-\(UUID().uuidString).mkv")
        let newURL = baseURL.appendingPathComponent("forgeff-test-new-selection-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: runningURL)
        try Data(repeating: 1, count: 1024).write(to: newURL)
        defer {
            try? FileManager.default.removeItem(at: runningURL)
            try? FileManager.default.removeItem(at: newURL)
        }

        var runningJob = VideoJob(sourceURL: runningURL)
        runningJob.status = .running
        var newJob = VideoJob(sourceURL: newURL)
        newJob.status = .ready

        store._debugSetJobs([runningJob, newJob])
        store._debugSetExecutionState(
            .running,
            scopeMode: .selection,
            scopeJobIDs: [runningJob.id],
            activeJobID: runningJob.id
        )

        store._debugAdmitNewJobIntoActiveScope(jobID: newJob.id)

        let executionState = store._debugExecutionState()
        XCTAssertTrue(executionState.scopeJobIDs.contains(newJob.id))
        XCTAssertEqual(store.displayStatus(for: newJob.id), .inQueue)
    }

    func testAnalyzingJobJoinsActiveQueueBeforeMetadataIsReady() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        var runningJob = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/forgeff-running.mov"))
        runningJob.status = .running
        var analyzingJob = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/forgeff-analyzing.mov"))
        analyzingJob.status = .analyzing

        store._debugSetJobs([runningJob, analyzingJob])
        store._debugSetExecutionState(
            .running,
            scopeMode: .selection,
            scopeJobIDs: [runningJob.id],
            activeJobID: runningJob.id
        )

        store._debugAdmitNewJobIntoActiveScope(jobID: analyzingJob.id)

        XCTAssertTrue(store._debugExecutionState().scopeJobIDs.contains(analyzingJob.id))
        XCTAssertEqual(store.displayStatus(for: analyzingJob.id), .analyzing)
    }

    func testDisplayStatusPromotesNextJobToRunningAfterCompletion() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let firstURL = baseURL.appendingPathComponent("forgeff-test-next-running-1-\(UUID().uuidString).mkv")
        let secondURL = baseURL.appendingPathComponent("forgeff-test-next-running-2-\(UUID().uuidString).mkv")
        let thirdURL = baseURL.appendingPathComponent("forgeff-test-next-running-3-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: firstURL)
        try Data(repeating: 1, count: 1024).write(to: secondURL)
        try Data(repeating: 1, count: 1024).write(to: thirdURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
            try? FileManager.default.removeItem(at: thirdURL)
        }

        var firstJob = VideoJob(sourceURL: firstURL)
        firstJob.status = .completed
        var secondJob = VideoJob(sourceURL: secondURL)
        secondJob.status = .ready
        var thirdJob = VideoJob(sourceURL: thirdURL)
        thirdJob.status = .ready

        store._debugSetJobs([firstJob, secondJob, thirdJob])
        store._debugSetExecutionState(
            .running,
            scopeJobIDs: Set([firstJob.id, secondJob.id, thirdJob.id]),
            activeJobID: secondJob.id
        )

        XCTAssertEqual(store.displayStatus(for: firstJob.id), .completed)
        XCTAssertEqual(store.displayStatus(for: secondJob.id), .running)
        XCTAssertEqual(store.displayStatus(for: thirdJob.id), .inQueue)
    }

    func testCancellingCurrentRunRevertsPendingScopeJobsToReady() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let baseURL = FileManager.default.temporaryDirectory
        let runningURL = baseURL.appendingPathComponent("forgeff-test-cancel-scope-running-\(UUID().uuidString).mkv")
        let readyURL = baseURL.appendingPathComponent("forgeff-test-cancel-scope-ready-\(UUID().uuidString).mkv")
        let readyTwoURL = baseURL.appendingPathComponent("forgeff-test-cancel-scope-ready-two-\(UUID().uuidString).mkv")
        try Data(repeating: 1, count: 1024).write(to: runningURL)
        try Data(repeating: 1, count: 1024).write(to: readyURL)
        try Data(repeating: 1, count: 1024).write(to: readyTwoURL)
        defer {
            try? FileManager.default.removeItem(at: runningURL)
            try? FileManager.default.removeItem(at: readyURL)
            try? FileManager.default.removeItem(at: readyTwoURL)
        }

        var runningJob = VideoJob(sourceURL: runningURL)
        runningJob.status = .running
        var readyJob = VideoJob(sourceURL: readyURL)
        readyJob.status = .ready
        var secondReadyJob = VideoJob(sourceURL: readyTwoURL)
        secondReadyJob.status = .ready

        store._debugSetJobs([runningJob, readyJob, secondReadyJob])
        store._debugSetExecutionState(
            .running,
            scopeJobIDs: Set([runningJob.id, readyJob.id, secondReadyJob.id]),
            activeJobID: runningJob.id
        )

        store.cancelCurrentJob()

        let executionState = store._debugExecutionState()
        XCTAssertEqual(store.queueState, .cancelling)
        XCTAssertEqual(executionState.scopeJobIDs, Set([runningJob.id]))
        XCTAssertEqual(store.jobs.first(where: { $0.id == runningJob.id })?.status, .cancelled)
        XCTAssertEqual(store.jobs.first(where: { $0.id == readyJob.id })?.status, .ready)
        XCTAssertEqual(store.jobs.first(where: { $0.id == secondReadyJob.id })?.status, .ready)
        XCTAssertEqual(store.displayStatus(for: readyJob.id), .ready)
        XCTAssertEqual(store.displayStatus(for: secondReadyJob.id), .ready)
    }

    func testQueueElapsedTrackerRunningPausedRunning() {
        var tracker = QueueElapsedTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        let t5 = Date(timeIntervalSince1970: 5)
        let t8 = Date(timeIntervalSince1970: 8)
        let t12 = Date(timeIntervalSince1970: 12)

        tracker.startOrResume(at: t0)
        XCTAssertEqual(tracker.elapsed(at: t5), 5, accuracy: 0.001)

        tracker.pause(at: t5)
        XCTAssertEqual(tracker.elapsed(at: t8), 5, accuracy: 0.001)

        tracker.startOrResume(at: t8)
        XCTAssertEqual(tracker.elapsed(at: t12), 9, accuracy: 0.001)
    }

    func testAppendingExternalAudioTracksKeepsOrderAndDeduplicatesByPath() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-audio-order-\(UUID().uuidString).mp4")
        try Data(repeating: 1, count: 1024).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        store.addFiles(urls: [sourceURL])
        let jobID = try XCTUnwrap(store.jobs.first?.id)

        let first = URL(fileURLWithPath: "/tmp/voiceover-en.m4a")
        let second = URL(fileURLWithPath: "/tmp/voiceover-es.m4a")
        store.appendExternalAudioAttachments(
            [
                ExternalAudioAttachment(fileURL: first),
                ExternalAudioAttachment(fileURL: second),
                ExternalAudioAttachment(fileURL: first)
            ],
            for: [jobID]
        )

        let attachments = try XCTUnwrap(store.jobs.first?.options.externalAudioAttachments)
        XCTAssertEqual(attachments.map(\.fileURL.path), [first.path, second.path])
    }

    func testAppendingSubtitleTracksKeepsOrderAndDeduplicatesByPath() throws {
        let settings = makeConfiguredSettingsStore()
        let history = HistoryStore()
        let store = JobQueueStore(settingsStore: settings, historyStore: history)

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("forgeff-subtitle-order-\(UUID().uuidString).mp4")
        try Data(repeating: 1, count: 1024).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        store.addFiles(urls: [sourceURL])
        let jobID = try XCTUnwrap(store.jobs.first?.id)

        let first = URL(fileURLWithPath: "/tmp/subtitles-en.srt")
        let second = URL(fileURLWithPath: "/tmp/subtitles-es.srt")
        store.appendSubtitleAttachments(
            [
                SubtitleAttachment(fileURL: first, languageCode: "eng"),
                SubtitleAttachment(fileURL: second, languageCode: "spa"),
                SubtitleAttachment(fileURL: first, languageCode: "eng")
            ],
            for: [jobID]
        )

        let attachments = try XCTUnwrap(store.jobs.first?.options.subtitleAttachments)
        XCTAssertEqual(attachments.map(\.fileURL.path), [first.path, second.path])
        XCTAssertEqual(attachments.map(\.languageCode), ["eng", "spa"])
    }

    func testFailureDiagnosticReportGeneratesSafeFilenameAndCompleteContents() {
        var job = VideoJob(sourceURL: URL(fileURLWithPath: "/tmp/Camera clip #1.MP4"))
        job.status = .failed
        job.errorMessage = "Encoder failed."
        job.errorDetails = "Detailed FFmpeg output"
        job.commandLine = "/opt/homebrew/bin/ffmpeg -i input.mp4 output.mp4"
        job.ffmpegVersion = "ffmpeg version 8.1.2"
        job.result = JobResultSummary(
            outputURL: nil,
            outputFileSize: nil,
            elapsedSeconds: 12.5,
            averageSpeed: 0.8,
            encodedFrameCount: 250,
            averageFramesPerSecond: 20
        )

        let report = FailureDiagnosticReport(
            job: job,
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "2.6.3",
            appBuild: "263"
        )

        XCTAssertEqual(report.suggestedFilename, "ForgeFF-Camera-clip-1-failed-19700101-000000.txt")
        XCTAssertTrue(report.contents.contains("Application: ForgeFF 2.6.3 (263)"))
        XCTAssertTrue(report.contents.contains("Status: Failed"))
        XCTAssertTrue(report.contents.contains("Encoder failed."))
        XCTAssertTrue(report.contents.contains("Detailed FFmpeg output"))
        XCTAssertTrue(report.contents.contains("Average processing FPS: 20.00"))
        XCTAssertTrue(report.contents.contains(job.commandLine ?? ""))
    }

}
