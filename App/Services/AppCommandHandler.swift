import Foundation

@MainActor
final class AppCommandHandler: ObservableObject {
    var onAddFiles: () -> Void = {}
    var onAddFolder: () -> Void = {}
    var onStartOrResume: () -> Void = {}
    var onCancelQueue: () -> Void = {}
    var onRemoveSelected: () -> Void = {}
    var onClearQueue: () -> Void = {}
    var onClearCompleted: () -> Void = {}

    func triggerAddFiles() { onAddFiles() }
    func triggerAddFolder() { onAddFolder() }
    func triggerStartOrResume() { onStartOrResume() }
    func triggerCancelQueue() { onCancelQueue() }
    func triggerRemoveSelected() { onRemoveSelected() }
    func triggerClearQueue() { onClearQueue() }
    func triggerClearCompleted() { onClearCompleted() }
}
