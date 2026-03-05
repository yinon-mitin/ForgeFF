import XCTest
@testable import ForgeFF

@MainActor
final class AppCommandHandlerTests: XCTestCase {
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

        handler.triggerAddFiles()
        handler.triggerAddFolder()
        handler.triggerStartOrResume()
        handler.triggerToggleStartPause()
        handler.triggerCancelQueue()
        handler.triggerRemoveSelected()
        handler.triggerClearQueue()
        handler.triggerClearCompleted()

        XCTAssertEqual(invocations, [
            "addFiles",
            "addFolder",
            "start",
            "toggle",
            "cancel",
            "remove",
            "clearQueue",
            "clearCompleted"
        ])
    }
}
