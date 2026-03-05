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
        store._debugSetQueueState(.running)

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
}
