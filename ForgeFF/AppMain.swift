import AppKit
import SwiftUI

extension Notification.Name {
    static let forgeFFOpenFiles = Notification.Name("ForgeFF.openFiles")
}

@MainActor
final class ForgeFFAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenFiles(urls: urls)
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        handleOpenFiles(urls: filenames.map { URL(fileURLWithPath: $0) })
    }

    func handleOpenFiles(urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        guard !fileURLs.isEmpty else { return }
        pendingOpenURLs.append(contentsOf: fileURLs)
        NotificationCenter.default.post(name: .forgeFFOpenFiles, object: fileURLs)
    }

    func consumePendingOpenURLs() -> [URL] {
        defer { pendingOpenURLs.removeAll() }
        return pendingOpenURLs
    }
}

@main
struct ForgeFFApp: App {
    @NSApplicationDelegateAdaptor(ForgeFFAppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var historyStore: HistoryStore
    @StateObject private var userPresetStore: UserPresetStore
    @StateObject private var queueStore: JobQueueStore
    @StateObject private var dockProgressController: DockProgressController
    @StateObject private var viewModel: QueueViewModel
    @StateObject private var commandHandler: AppCommandHandler
    @StateObject private var updateService: AppUpdateService

    init() {
        let settingsStore = SettingsStore()
        let historyStore = HistoryStore()
        let userPresetStore = UserPresetStore()
        let queueStore = JobQueueStore(settingsStore: settingsStore, historyStore: historyStore)
        let dockProgressController = DockProgressController(queueStore: queueStore)
        let commandHandler = AppCommandHandler()
        let updateService = AppUpdateService()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _userPresetStore = StateObject(wrappedValue: userPresetStore)
        _queueStore = StateObject(wrappedValue: queueStore)
        _dockProgressController = StateObject(wrappedValue: dockProgressController)
        _viewModel = StateObject(wrappedValue: QueueViewModel(queueStore: queueStore, userPresetStore: userPresetStore))
        _commandHandler = StateObject(wrappedValue: commandHandler)
        _updateService = StateObject(wrappedValue: updateService)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 480)
                .environmentObject(settingsStore)
                .environmentObject(historyStore)
                .environmentObject(queueStore)
                .environmentObject(commandHandler)
                .environmentObject(dockProgressController)
                .environmentObject(appDelegate)
                .environmentObject(updateService)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            ForgeFFCommands(
                queueStore: queueStore,
                viewModel: viewModel,
                commandHandler: commandHandler
            )
        }
    }
}

private struct ForgeFFCommands: Commands {
    @ObservedObject var queueStore: JobQueueStore
    @ObservedObject var viewModel: QueueViewModel
    let commandHandler: AppCommandHandler

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About ForgeFF") {
                commandHandler.triggerShowAbout()
            }
            .keyboardShortcut("/", modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Toggle More Settings") {
                commandHandler.triggerToggleMoreSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(after: .newItem) {
            Button(queueStore.acceptsLiveQueueAdditions ? "Add Files to Queue" : "Add Files") {
                commandHandler.triggerAddFiles()
            }
            .keyboardShortcut("o")

            Button(queueStore.acceptsLiveQueueAdditions ? "Add Folder to Queue" : "Add Folder") {
                commandHandler.triggerAddFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("Queue") {
            Button("\(queueStore.startButtonTitle(selectedJobIDs: viewModel.selectedJobIDs)) Queue") {
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
