import Foundation

enum OutputContainer: String, Codable, CaseIterable, Identifiable {
    case mp4
    case mov
    case mkv

    var id: String { rawValue }
    var fileExtension: String { rawValue }
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable {
    case h264
    case hevc
    case proRes = "prores"
    case vp9
    case av1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes: return "ProRes"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        }
    }

    func ffmpegCodec(useHardwareAcceleration: Bool) -> String {
        switch self {
        case .h264:
            return useHardwareAcceleration ? "h264_videotoolbox" : "libx264"
        case .hevc:
            return useHardwareAcceleration ? "hevc_videotoolbox" : "libx265"
        case .proRes:
            return "prores_ks"
        case .vp9:
            return "libvpx-vp9"
        case .av1:
            return "libsvtav1"
        }
    }
}

enum AudioCodec: String, Codable, CaseIterable, Identifiable {
    case copy
    case aac
    case mp3
    case pcm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copy: return "Keep"
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .pcm: return "PCM"
        }
    }

    var ffmpegCodec: String {
        switch self {
        case .copy: return "copy"
        case .aac: return "aac"
        case .mp3: return "libmp3lame"
        case .pcm: return "pcm_s16le"
        }
    }
}

enum QualityProfile: String, Codable, CaseIterable, Identifiable {
    case smaller
    case balanced
    case better

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smaller: return "Smaller"
        case .balanced: return "Balanced"
        case .better: return "Better"
        }
    }

    var ffmpegPreset: String {
        switch self {
        case .smaller: return "faster"
        case .balanced: return "medium"
        case .better: return "slow"
        }
    }

    func crf(for codec: VideoCodec) -> Int? {
        switch codec {
        case .h264:
            switch self {
            case .smaller: return 25
            case .balanced: return 21
            case .better: return 18
            }
        case .hevc:
            switch self {
            case .smaller: return 29
            case .balanced: return 25
            case .better: return 21
            }
        case .proRes:
            return nil
        case .vp9:
            return nil
        case .av1:
            return nil
        }
    }

    var defaultAudioBitrateKbps: Int {
        switch self {
        case .smaller: return 128
        case .balanced: return 192
        case .better: return 256
        }
    }
}

enum FrameRateOption: String, Codable, CaseIterable, Identifiable {
    case keep
    case fps24
    case fps30
    case fps60
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .fps24: return "24"
        case .fps30: return "30"
        case .fps60: return "60"
        case .custom: return "Custom"
        }
    }

    var numericValue: Double? {
        switch self {
        case .keep: return nil
        case .fps24: return 24
        case .fps30: return 30
        case .fps60: return 60
        case .custom: return nil
        }
    }
}

enum ResolutionOverride: Codable, Equatable, Hashable {
    case preserve
    case preset(width: Int, height: Int, label: String)
    case custom(width: Int, height: Int)

    var displayName: String {
        switch self {
        case .preserve:
            return "Keep"
        case let .preset(_, _, label):
            return label
        case let .custom(width, height):
            return "\(width)x\(height)"
        }
    }

    var dimensions: (Int, Int)? {
        switch self {
        case .preserve:
            return nil
        case let .preset(width, height, _):
            return (width, height)
        case let .custom(width, height):
            return (width, height)
        }
    }

    static var preset720p: ResolutionOverride { .preset(width: 1280, height: 720, label: "720p") }
    static var preset1080p: ResolutionOverride { .preset(width: 1920, height: 1080, label: "1080p") }
    static var preset2k: ResolutionOverride { .preset(width: 2560, height: 1440, label: "2K (1440p)") }
    static var preset4k: ResolutionOverride { .preset(width: 3840, height: 2160, label: "4K (2160p)") }
}

enum ToneMapMode: String, Codable, CaseIterable, Identifiable {
    case hable
    case reinhard

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum SubtitleHandling: String, Codable, CaseIterable, Identifiable {
    case keep
    case remove
    case addExternal

    var id: String { rawValue }
}

struct SubtitleAttachment: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileURL: URL
    var languageCode: String
}

struct ConversionPreset: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case video
        case audioOnly
    }

    let id: UUID
    let name: String
    let summary: String
    let tradeoff: String
    let kind: Kind
    let container: OutputContainer
    let videoCodec: VideoCodec?
    let audioCodec: AudioCodec
    let quality: QualityProfile
    let enableHardwareAcceleration: Bool

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        tradeoff: String,
        kind: Kind = .video,
        container: OutputContainer,
        videoCodec: VideoCodec?,
        audioCodec: AudioCodec,
        quality: QualityProfile,
        enableHardwareAcceleration: Bool
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.tradeoff = tradeoff
        self.kind = kind
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.quality = quality
        self.enableHardwareAcceleration = enableHardwareAcceleration
    }

    static let builtIns: [ConversionPreset] = [
        ConversionPreset(
            name: "MP4 — H.264 (Fast)",
            summary: "Fast: quickest encode, larger files.",
            tradeoff: "Great for quick exports and older devices.",
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            quality: .smaller,
            enableHardwareAcceleration: true
        ),
        ConversionPreset(
            name: "MP4 — H.264 (Balanced)",
            summary: "Balanced: good quality and size.",
            tradeoff: "Best default for most H.264 exports.",
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            quality: .balanced,
            enableHardwareAcceleration: true
        ),
        ConversionPreset(
            name: "MP4 — H.264 (High Quality)",
            summary: "High Quality: slower, cleaner output.",
            tradeoff: "Takes longer, best visual quality.",
            container: .mp4,
            videoCodec: .h264,
            audioCodec: .aac,
            quality: .better,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MP4 — HEVC (Fast)",
            summary: "Fast: quickest HEVC encode.",
            tradeoff: "Smaller files than H.264 at similar quality.",
            container: .mp4,
            videoCodec: .hevc,
            audioCodec: .aac,
            quality: .smaller,
            enableHardwareAcceleration: true
        ),
        ConversionPreset(
            name: "MP4 — HEVC (Balanced)",
            summary: "Balanced: strong quality/size ratio.",
            tradeoff: "Good default for modern playback.",
            container: .mp4,
            videoCodec: .hevc,
            audioCodec: .aac,
            quality: .balanced,
            enableHardwareAcceleration: true
        ),
        ConversionPreset(
            name: "MP4 — HEVC (High Quality)",
            summary: "High Quality: slower, better detail retention.",
            tradeoff: "Smaller, higher quality results.",
            container: .mp4,
            videoCodec: .hevc,
            audioCodec: .aac,
            quality: .better,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MKV — VP9 (Balanced)",
            summary: "Balanced: practical VP9 quality and speed.",
            tradeoff: "Good web/archive compatibility in MKV.",
            container: .mkv,
            videoCodec: .vp9,
            audioCodec: .aac,
            quality: .balanced,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MKV — VP9 (High Quality)",
            summary: "High Quality: slower VP9 encode.",
            tradeoff: "Better visual quality at the cost of time.",
            container: .mkv,
            videoCodec: .vp9,
            audioCodec: .aac,
            quality: .better,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MKV — AV1 (Balanced)",
            summary: "Balanced: modern compression with practical speed.",
            tradeoff: "Smaller output, slower than HEVC.",
            container: .mkv,
            videoCodec: .av1,
            audioCodec: .aac,
            quality: .balanced,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MKV — AV1 (High Quality)",
            summary: "High Quality: slower AV1 encode.",
            tradeoff: "Best compression and quality, longest encode.",
            container: .mkv,
            videoCodec: .av1,
            audioCodec: .aac,
            quality: .better,
            enableHardwareAcceleration: false
        ),
        ConversionPreset(
            name: "MOV — ProRes 422 (Editing)",
            summary: "Editing: ProRes 422 mezzanine output.",
            tradeoff: "Large files, very edit-friendly.",
            container: .mov,
            videoCodec: .proRes,
            audioCodec: .aac,
            quality: .better,
            enableHardwareAcceleration: false
        )
    ]

    static let custom = ConversionPreset(
        name: "Custom",
        summary: "Manual tweaks are active.",
        tradeoff: "Your current settings differ from saved presets.",
        container: .mp4,
        videoCodec: .h264,
        audioCodec: .aac,
        quality: .balanced,
        enableHardwareAcceleration: true
    )
}

struct UserPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var options: ConversionOptions
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        options: ConversionOptions,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.options = options
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ConversionOptions: Codable, Equatable {
    var presetName: String
    var isAudioOnly: Bool
    var container: OutputContainer
    var videoCodec: VideoCodec
    var audioCodec: AudioCodec
    var qualityProfile: QualityProfile
    var resolutionOverride: ResolutionOverride
    var frameRateOption: FrameRateOption
    var customFrameRate: Double?
    var useHardwareAcceleration: Bool
    var removeMetadata: Bool
    var removeChapters: Bool
    var removeEmbeddedSubtitles: Bool
    var subtitleMode: SubtitleHandling?
    var subtitleAttachments: [SubtitleAttachment]
    var enableHDRToSDR: Bool
    var toneMapMode: ToneMapMode
    var toneMapPeak: Double
    var outputTemplate: String

    // Advanced sheet values.
    var videoBitrateKbps: Int?
    var audioBitrateKbps: Int?
    var sampleRate: Int?
    var audioChannels: Int?
    var customFFmpegArguments: String

    static let `default` = ConversionOptions(
        presetName: ConversionPreset.builtIns[0].name,
        isAudioOnly: false,
        container: .mp4,
        videoCodec: .h264,
        audioCodec: .aac,
        qualityProfile: .balanced,
        resolutionOverride: .preserve,
        frameRateOption: .keep,
        customFrameRate: nil,
        useHardwareAcceleration: true,
        removeMetadata: false,
        removeChapters: false,
        removeEmbeddedSubtitles: false,
        subtitleMode: nil,
        subtitleAttachments: [],
        enableHDRToSDR: false,
        toneMapMode: .hable,
        toneMapPeak: 1000,
        outputTemplate: "{name}_{preset}",
        videoBitrateKbps: nil,
        audioBitrateKbps: nil,
        sampleRate: nil,
        audioChannels: nil,
        customFFmpegArguments: ""
    )

    mutating func apply(preset: ConversionPreset) {
        presetName = preset.name
        isAudioOnly = preset.kind == .audioOnly
        container = preset.container
        videoCodec = preset.videoCodec ?? .h264
        audioCodec = preset.audioCodec
        qualityProfile = preset.quality
        useHardwareAcceleration = preset.enableHardwareAcceleration
        resolutionOverride = .preserve
        frameRateOption = .keep
        customFrameRate = nil
        audioBitrateKbps = nil
        audioChannels = nil
        sampleRate = nil
        removeMetadata = false
        removeChapters = false
        enableHDRToSDR = false
        toneMapMode = .hable
        outputTemplate = "{name}_{preset}"
        subtitleMode = .keep
        removeEmbeddedSubtitles = false
        subtitleAttachments = []
        customFFmpegArguments = ""
        videoBitrateKbps = nil

        if preset.kind == .audioOnly {
            useHardwareAcceleration = false
        }
    }

    var effectiveAudioBitrateKbps: Int? {
        if audioCodec == .copy || audioCodec == .pcm { return nil }
        return audioBitrateKbps
    }

    var effectiveSubtitleMode: SubtitleHandling {
        if let subtitleMode {
            return subtitleMode
        }
        if !subtitleAttachments.isEmpty {
            return .addExternal
        }
        return removeEmbeddedSubtitles ? .remove : .keep
    }
}

extension ConversionOptions {
    static let orderedResolutionChoices: [ResolutionOverride] = [
        .preserve,
        .preset720p,
        .preset1080p,
        .preset2k,
        .preset4k
    ]

    static func resolveExternalSubtitleSelection(
        previousMode: SubtitleHandling,
        previousAttachmentURL: URL?,
        pickedURL: URL?
    ) -> (mode: SubtitleHandling, attachmentURL: URL?) {
        if let pickedURL {
            return (.addExternal, pickedURL)
        }

        if previousMode == .addExternal {
            return (.addExternal, previousAttachmentURL)
        }

        return (previousMode, nil)
    }
}

extension VideoCodec {
    static func allowedCodecs(
        for container: OutputContainer
    ) -> [VideoCodec] {
        switch container {
        case .mov:
            return [.h264, .hevc, .proRes]
        case .mp4:
            return [.h264, .hevc, .av1]
        case .mkv:
            return [.h264, .hevc, .vp9, .av1]
        }
    }
}

struct BatchRenameConfiguration: Equatable {
    var replaceText: String = ""
    var replaceWith: String = ""
    var prefix: String = ""
    var suffix: String = ""
    var sanitizeFilename: Bool = true
}
