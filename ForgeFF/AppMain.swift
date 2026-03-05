import SwiftUI

@main
struct ForgeFFApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var historyStore: HistoryStore
    @StateObject private var userPresetStore: UserPresetStore
    @StateObject private var queueStore: JobQueueStore
    @StateObject private var viewModel: QueueViewModel
    @StateObject private var commandHandler: AppCommandHandler

    init() {
        let settingsStore = SettingsStore()
        let historyStore = HistoryStore()
        let userPresetStore = UserPresetStore()
        let queueStore = JobQueueStore(settingsStore: settingsStore, historyStore: historyStore)
        let commandHandler = AppCommandHandler()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _userPresetStore = StateObject(wrappedValue: userPresetStore)
        _queueStore = StateObject(wrappedValue: queueStore)
        _viewModel = StateObject(wrappedValue: QueueViewModel(queueStore: queueStore, userPresetStore: userPresetStore))
        _commandHandler = StateObject(wrappedValue: commandHandler)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(settingsStore)
                .environmentObject(historyStore)
                .environmentObject(queueStore)
                .environmentObject(commandHandler)
        }
        .defaultSize(width: 1100, height: 700)
        Window("About ForgeFF", id: "about-forgeff") {
            AboutForgeFFView()
                .frame(minWidth: 440, minHeight: 240)
        }
        .windowResizability(.contentSize)
        .commands {
            ForgeFFCommands(
                queueStore: queueStore,
                commandHandler: commandHandler
            )
        }
    }
}

private struct ForgeFFCommands: Commands {
    @ObservedObject var queueStore: JobQueueStore
    let commandHandler: AppCommandHandler
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About ForgeFF") {
                openWindow(id: "about-forgeff")
            }
        }

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
            Button("\(queueStore.startButtonTitle) Queue") {
                commandHandler.triggerStartOrResume()
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button(queueStore.queueState == .running ? "Pause (⌘P)" : "Play/Pause (⌘P)") {
                commandHandler.triggerToggleStartPause()
            }
            .keyboardShortcut("p", modifiers: [.command])

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
