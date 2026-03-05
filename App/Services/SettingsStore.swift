import AppKit
import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    var ffmpegBinaryPath: String
    var ffprobeBinaryPath: String
    var defaultOutputDirectoryBookmark: Data?
    var allowOverwrite: Bool
    var skipExistingMatchingOutputs: Bool
    var organizeByDate: Bool
    var autoUseVideoToolbox: Bool
    var maxParallelJobs: Int
    var lastSelectedPresetName: String?
    var lastUsedOptionsData: Data?
    var ffmpegHintMessages: [String]

    static let `default` = AppSettings(
        ffmpegBinaryPath: "",
        ffprobeBinaryPath: "",
        defaultOutputDirectoryBookmark: nil,
        allowOverwrite: false,
        skipExistingMatchingOutputs: false,
        organizeByDate: false,
        autoUseVideoToolbox: true,
        maxParallelJobs: 1,
        lastSelectedPresetName: ConversionPreset.builtIns.first?.name,
        lastUsedOptionsData: nil,
        ffmpegHintMessages: []
    )
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let settingsKey = "ForgeFF.appSettings"
    private let pathDetector: FFmpegPathDetector

    @Published var shouldShowFFmpegSetup = false
    @Published var encoderCapabilities: FFmpegEncoderCapabilities = .none

    init(pathDetector: FFmpegPathDetector = FFmpegPathDetector()) {
        self.pathDetector = pathDetector
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }

        refreshBinaryDetection()
    }

    var ffmpegURL: URL? {
        URL.validExecutablePath(settings.ffmpegBinaryPath)
    }

    var ffprobeURL: URL? {
        if let explicit = URL.validExecutablePath(settings.ffprobeBinaryPath) {
            return explicit
        }

        guard let ffmpegURL else { return nil }
        let sibling = ffmpegURL.deletingLastPathComponent().appendingPathComponent("ffprobe")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    var ffmpegHints: [String] {
        settings.ffmpegHintMessages
    }

    var hasRequiredBinaries: Bool {
        ffmpegURL != nil && ffprobeURL != nil
    }

    var defaultOutputDirectoryURL: URL? {
        guard let bookmark = settings.defaultOutputDirectoryBookmark else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        )
    }

    func chooseBinary(for keyPath: WritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = keyPath == \.ffmpegBinaryPath ? "Choose ffmpeg binary" : "Choose ffprobe binary"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings[keyPath: keyPath] = url.path
            refreshBinaryDetection()
        }
    }

    func chooseDefaultOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.defaultOutputDirectoryBookmark = bookmark
    }

    func saveLastUsed(options: ConversionOptions) {
        settings.lastSelectedPresetName = options.presetName
        settings.lastUsedOptionsData = try? JSONEncoder().encode(options)
    }

    func restoreLastUsedOptions() -> ConversionOptions {
        guard let data = settings.lastUsedOptionsData,
              let decoded = try? JSONDecoder().decode(ConversionOptions.self, from: data) else {
            return .default
        }
        return decoded
    }

    func refreshBinaryDetection() {
        let result = pathDetector.detect(
            currentFFmpegPath: settings.ffmpegBinaryPath,
            currentFFprobePath: settings.ffprobeBinaryPath
        )

        if let ffmpegPath = result.ffmpegPath {
            settings.ffmpegBinaryPath = ffmpegPath
        }
        if let ffprobePath = result.ffprobePath {
            settings.ffprobeBinaryPath = ffprobePath
        }
        settings.ffmpegHintMessages = result.hints
        shouldShowFFmpegSetup = !result.isConfigured
        refreshEncoderCapabilities()
    }

    func dismissFFmpegSetup() {
        shouldShowFFmpegSetup = false
    }

    func copyHomebrewInstallCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("brew install ffmpeg", forType: .string)
    }

    func chooseMissingBinary() {
        if ffmpegURL == nil {
            chooseBinary(for: \.ffmpegBinaryPath)
        } else if ffprobeURL == nil {
            chooseBinary(for: \.ffprobeBinaryPath)
        } else {
            chooseBinary(for: \.ffmpegBinaryPath)
        }
    }

    func resetBinaryToAuto(for keyPath: WritableKeyPath<AppSettings, String>) {
        settings[keyPath: keyPath] = ""
        refreshBinaryDetection()
    }

    func refreshEncoderCapabilities() {
        let ffmpegURL = self.ffmpegURL
        Task.detached(priority: .utility) {
            let detected = FFmpegEncoderDiscovery.detectCapabilities(ffmpegURL: ffmpegURL)
            await MainActor.run {
                self.encoderCapabilities = detected
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}

extension URL {
    static func validExecutablePath(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
