import Foundation

struct AVConvertCapabilities: Equatable {
    var isAvailable: Bool
    var executableURL: URL?

    static let unavailable = AVConvertCapabilities(isAvailable: false, executableURL: nil)
}

enum ToneMappingBackend: String, Codable, CaseIterable, Identifiable, Equatable {
    case appleAVConvert
    case ffmpegFilters

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleAVConvert:
            return "Apple"
        case .ffmpegFilters:
            return "FFmpeg"
        }
    }
}

enum AVConvertDiscovery {
    static let defaultExecutableURL = URL(fileURLWithPath: "/usr/bin/avconvert")

    static func detectCapabilities(fileManager: FileManager = .default) -> AVConvertCapabilities {
        guard fileManager.isExecutableFile(atPath: defaultExecutableURL.path) else {
            return .unavailable
        }
        return AVConvertCapabilities(isAvailable: true, executableURL: defaultExecutableURL)
    }
}
