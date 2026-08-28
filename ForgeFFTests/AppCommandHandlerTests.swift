import XCTest
@testable import ForgeFF

@MainActor
final class AppCommandHandlerTests: XCTestCase {
    func testOpenFilesHandlerPublishesAllSelectedURLs() {
        let delegate = ForgeFFAppDelegate()
        let urls = [URL(fileURLWithPath: "/tmp/first.mp4"), URL(fileURLWithPath: "/tmp/second.mov")]
        let expectation = expectation(description: "open files notification")
        let token = NotificationCenter.default.addObserver(
            forName: .forgeFFOpenFiles,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.object as? [URL], urls)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        delegate.handleOpenFiles(urls: urls)

        wait(for: [expectation], timeout: 1)
    }

    func testTriggerMethodsCallMappedActions() {
        let handler = AppCommandHandler()
        var invocations: [String] = []

        handler.onAddFiles = { invocations.append("addFiles") }
        handler.onAddFolder = { invocations.append("addFolder") }
        handler.onStartOrResume = { invocations.append("start") }
        handler.onToggleStartPause = { invocations.append("toggle") }
        handler.onCancelQueue = { invocations.append("cancel") }
        handler.onRemoveSelected = { invocations.append("remove") }
        handler.onClearQueue = { invocations.append("clearQueue") }
        handler.onClearCompleted = { invocations.append("clearCompleted") }
        handler.onToggleMoreSettings = { invocations.append("toggleMoreSettings") }
        handler.onShowAbout = { invocations.append("showAbout") }

        handler.triggerAddFiles()
        handler.triggerAddFolder()
        handler.triggerStartOrResume()
        handler.triggerToggleStartPause()
        handler.triggerCancelQueue()
        handler.triggerRemoveSelected()
        handler.triggerClearQueue()
        handler.triggerClearCompleted()
        handler.triggerToggleMoreSettings()
        handler.triggerShowAbout()

        XCTAssertEqual(invocations, [
            "addFiles",
            "addFolder",
            "start",
            "toggle",
            "cancel",
            "remove",
            "clearQueue",
            "clearCompleted",
            "toggleMoreSettings",
            "showAbout"
        ])
    }
}
