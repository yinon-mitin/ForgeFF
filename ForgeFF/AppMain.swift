import SwiftUI

@main
struct ForgeFFApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var historyStore: HistoryStore
    @StateObject private var queueStore: JobQueueStore
    @StateObject private var viewModel: QueueViewModel
    @StateObject private var commandHandler: AppCommandHandler

    init() {
        let settingsStore = SettingsStore()
        let historyStore = HistoryStore()
        let queueStore = JobQueueStore(settingsStore: settingsStore, historyStore: historyStore)
        let commandHandler = AppCommandHandler()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _queueStore = StateObject(wrappedValue: queueStore)
        _viewModel = StateObject(wrappedValue: QueueViewModel(queueStore: queueStore))
        _commandHandler = StateObject(wrappedValue: commandHandler)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
                .environmentObject(settingsStore)
                .environmentObject(historyStore)
                .environmentObject(queueStore)
                .environmentObject(commandHandler)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Files") {
                    commandHandler.triggerAddFiles()
                }
                .keyboardShortcut("o")

                Button("Add Folder") {
                    commandHandler.triggerAddFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Queue") {
                Button(queueStore.isQueuePaused ? "Resume Queue" : "Start Queue") {
                    commandHandler.triggerStartOrResume()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Cancel Queue") {
                    commandHandler.triggerCancelQueue()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Remove Selected Item(s)") {
                    commandHandler.triggerRemoveSelected()
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                Button("Clear Queue…") {
                    commandHandler.triggerClearQueue()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

                Button("Clear Completed Results") {
                    commandHandler.triggerClearCompleted()
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}
