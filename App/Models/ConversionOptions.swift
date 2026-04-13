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

enum EncoderOption: String, Codable, CaseIterable, Identifiable {
    case veryFast
    case fast
    case medium
    case slow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veryFast: return "Very Fast"
        case .fast: return "Fast"
        case .medium: return "Medium"
        case .slow: return "Slow"
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

struct ExternalAudioAttachment: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileURL: URL
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
    let encoderOption: EncoderOption
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
        encoderOption: EncoderOption = .medium,
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
        self.encoderOption = encoderOption
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
            encoderOption: .veryFast,
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
            encoderOption: .medium,
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
            encoderOption: .slow,
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
            encoderOption: .veryFast,
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
            encoderOption: .medium,
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
            encoderOption: .slow,
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
            encoderOption: .medium,
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
            encoderOption: .slow,
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
            encoderOption: .medium,
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
            encoderOption: .slow,
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
            encoderOption: .medium,
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
        encoderOption: .medium,
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

struct UserPresetArchive: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    var presets: [UserPreset]

    init(
        schemaVersion: Int = UserPresetArchive.currentSchemaVersion,
        exportedAt: Date = Date(),
        presets: [UserPreset]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.presets = presets
    }
}

struct ConversionOptions: Codable, Equatable {
    var presetName: String
    var isAudioOnly: Bool
    var container: OutputContainer
    var videoCodec: VideoCodec
    var audioCodec: AudioCodec
    var qualityProfile: QualityProfile
    var encoderOption: EncoderOption?
    var resolutionOverride: ResolutionOverride
    var frameRateOption: FrameRateOption
    var customFrameRate: Double?
    var useHardwareAcceleration: Bool
    var removeMetadata: Bool
    var removeChapters: Bool
    var removeEmbeddedSubtitles: Bool
    var subtitleMode: SubtitleHandling?
    var subtitleAttachments: [SubtitleAttachment]
    var externalAudioAttachments: [ExternalAudioAttachment]
    var enableHDRToSDR: Bool
    var toneMapMode: ToneMapMode
    var toneMapPeak: Double
    var webOptimization: Bool
    var outputTemplate: String

    // Advanced sheet values.
    var videoBitrateKbps: Int?
    var audioBitrateKbps: Int?
    var sampleRate: Int?
    var audioChannels: Int?
    var isCustomCommandOverrideEnabled: Bool
    var customCommandTemplate: String

    private enum CodingKeys: String, CodingKey {
        case presetName
        case isAudioOnly
        case container
        case videoCodec
        case audioCodec
        case qualityProfile
        case encoderOption
        case resolutionOverride
        case frameRateOption
        case customFrameRate
        case useHardwareAcceleration
        case removeMetadata
        case removeChapters
        case removeEmbeddedSubtitles
        case subtitleMode
        case subtitleAttachments
        case externalAudioAttachments
        case externalAudioURL
        case enableHDRToSDR
        case toneMapMode
        case toneMapPeak
        case webOptimization
        case outputTemplate
        case videoBitrateKbps
        case audioBitrateKbps
        case sampleRate
        case audioChannels
        case isCustomCommandOverrideEnabled
        case customCommandTemplate
    }

    init(
        presetName: String,
        isAudioOnly: Bool,
        container: OutputContainer,
        videoCodec: VideoCodec,
        audioCodec: AudioCodec,
        qualityProfile: QualityProfile,
        encoderOption: EncoderOption?,
        resolutionOverride: ResolutionOverride,
        frameRateOption: FrameRateOption,
        customFrameRate: Double?,
        useHardwareAcceleration: Bool,
        removeMetadata: Bool,
        removeChapters: Bool,
        removeEmbeddedSubtitles: Bool,
        subtitleMode: SubtitleHandling?,
        subtitleAttachments: [SubtitleAttachment],
        externalAudioAttachments: [ExternalAudioAttachment],
        enableHDRToSDR: Bool,
        toneMapMode: ToneMapMode,
        toneMapPeak: Double,
        webOptimization: Bool,
        outputTemplate: String,
        videoBitrateKbps: Int?,
        audioBitrateKbps: Int?,
        sampleRate: Int?,
        audioChannels: Int?,
        isCustomCommandOverrideEnabled: Bool,
        customCommandTemplate: String
    ) {
        self.presetName = presetName
        self.isAudioOnly = isAudioOnly
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.qualityProfile = qualityProfile
        self.encoderOption = encoderOption
        self.resolutionOverride = resolutionOverride
        self.frameRateOption = frameRateOption
        self.customFrameRate = customFrameRate
        self.useHardwareAcceleration = useHardwareAcceleration
        self.removeMetadata = removeMetadata
        self.removeChapters = removeChapters
        self.removeEmbeddedSubtitles = removeEmbeddedSubtitles
        self.subtitleMode = subtitleMode
        self.subtitleAttachments = subtitleAttachments
        self.externalAudioAttachments = externalAudioAttachments
        self.enableHDRToSDR = enableHDRToSDR
        self.toneMapMode = toneMapMode
        self.toneMapPeak = toneMapPeak
        self.webOptimization = webOptimization
        self.outputTemplate = outputTemplate
        self.videoBitrateKbps = videoBitrateKbps
        self.audioBitrateKbps = audioBitrateKbps
        self.sampleRate = sampleRate
        self.audioChannels = audioChannels
        self.isCustomCommandOverrideEnabled = isCustomCommandOverrideEnabled
        self.customCommandTemplate = customCommandTemplate
    }

    static let `default` = ConversionOptions(
        presetName: ConversionPreset.builtIns[0].name,
        isAudioOnly: false,
        container: .mp4,
        videoCodec: .h264,
        audioCodec: .aac,
        qualityProfile: .balanced,
        encoderOption: nil,
        resolutionOverride: .preserve,
        frameRateOption: .keep,
        customFrameRate: nil,
        useHardwareAcceleration: true,
        removeMetadata: false,
        removeChapters: false,
        removeEmbeddedSubtitles: false,
        subtitleMode: nil,
        subtitleAttachments: [],
        externalAudioAttachments: [],
        enableHDRToSDR: false,
        toneMapMode: .hable,
        toneMapPeak: 1000,
        webOptimization: false,
        outputTemplate: "{name}_{preset}",
        videoBitrateKbps: nil,
        audioBitrateKbps: nil,
        sampleRate: nil,
        audioChannels: nil,
        isCustomCommandOverrideEnabled: false,
        customCommandTemplate: ""
    )

    mutating func apply(preset: ConversionPreset) {
        presetName = preset.name
        isAudioOnly = preset.kind == .audioOnly
        container = preset.container
        videoCodec = preset.videoCodec ?? .h264
        audioCodec = preset.audioCodec
        qualityProfile = preset.quality
        encoderOption = preset.encoderOption
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
        webOptimization = false
        outputTemplate = "{name}_{preset}"
        subtitleMode = .keep
        removeEmbeddedSubtitles = false
        subtitleAttachments = []
        externalAudioAttachments = []
        isCustomCommandOverrideEnabled = false
        customCommandTemplate = ""
        videoBitrateKbps = nil

        if preset.kind == .audioOnly {
            useHardwareAcceleration = false
        }
    }

    var effectiveAudioBitrateKbps: Int? {
        if audioCodec == .copy || audioCodec == .pcm { return nil }
        return audioBitrateKbps
    }

    var effectiveEncoderOption: EncoderOption {
        encoderOption ?? Self.recommendedEncoderOption(
            videoCodec: videoCodec,
            qualityProfile: qualityProfile
        )
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

    var externalAudioURL: URL? {
        get { externalAudioAttachments.first?.fileURL }
        set {
            externalAudioAttachments = newValue.map { [ExternalAudioAttachment(fileURL: $0)] } ?? []
        }
    }

    var isWebOptimizationAvailable: Bool {
        container == .mp4 || container == .mov
    }

    var isCustomCommandEnabled: Bool {
        isCustomCommandOverrideEnabled
    }

    var effectiveCustomCommandTemplate: String {
        customCommandTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ConversionOptions.default

        presetName = try container.decodeIfPresent(String.self, forKey: .presetName) ?? defaults.presetName
        isAudioOnly = try container.decodeIfPresent(Bool.self, forKey: .isAudioOnly) ?? defaults.isAudioOnly
        self.container = try container.decodeIfPresent(OutputContainer.self, forKey: .container) ?? defaults.container
        videoCodec = try container.decodeIfPresent(VideoCodec.self, forKey: .videoCodec) ?? defaults.videoCodec
        audioCodec = try container.decodeIfPresent(AudioCodec.self, forKey: .audioCodec) ?? defaults.audioCodec
        qualityProfile = try container.decodeIfPresent(QualityProfile.self, forKey: .qualityProfile) ?? defaults.qualityProfile
        encoderOption = try container.decodeIfPresent(EncoderOption.self, forKey: .encoderOption)
        resolutionOverride = try container.decodeIfPresent(ResolutionOverride.self, forKey: .resolutionOverride) ?? defaults.resolutionOverride
        frameRateOption = try container.decodeIfPresent(FrameRateOption.self, forKey: .frameRateOption) ?? defaults.frameRateOption
        customFrameRate = try container.decodeIfPresent(Double.self, forKey: .customFrameRate)
        useHardwareAcceleration = try container.decodeIfPresent(Bool.self, forKey: .useHardwareAcceleration) ?? defaults.useHardwareAcceleration
        removeMetadata = try container.decodeIfPresent(Bool.self, forKey: .removeMetadata) ?? defaults.removeMetadata
        removeChapters = try container.decodeIfPresent(Bool.self, forKey: .removeChapters) ?? defaults.removeChapters
        removeEmbeddedSubtitles = try container.decodeIfPresent(Bool.self, forKey: .removeEmbeddedSubtitles) ?? defaults.removeEmbeddedSubtitles
        subtitleMode = try container.decodeIfPresent(SubtitleHandling.self, forKey: .subtitleMode)
        subtitleAttachments = try container.decodeIfPresent([SubtitleAttachment].self, forKey: .subtitleAttachments) ?? defaults.subtitleAttachments
        if let attachments = try container.decodeIfPresent([ExternalAudioAttachment].self, forKey: .externalAudioAttachments) {
            externalAudioAttachments = attachments
        } else if let legacyExternalAudioURL = try container.decodeIfPresent(URL.self, forKey: .externalAudioURL) {
            externalAudioAttachments = [ExternalAudioAttachment(fileURL: legacyExternalAudioURL)]
        } else {
            externalAudioAttachments = defaults.externalAudioAttachments
        }
        enableHDRToSDR = try container.decodeIfPresent(Bool.self, forKey: .enableHDRToSDR) ?? defaults.enableHDRToSDR
        toneMapMode = try container.decodeIfPresent(ToneMapMode.self, forKey: .toneMapMode) ?? defaults.toneMapMode
        toneMapPeak = try container.decodeIfPresent(Double.self, forKey: .toneMapPeak) ?? defaults.toneMapPeak
        webOptimization = try container.decodeIfPresent(Bool.self, forKey: .webOptimization) ?? defaults.webOptimization
        outputTemplate = try container.decodeIfPresent(String.self, forKey: .outputTemplate) ?? defaults.outputTemplate
        videoBitrateKbps = try container.decodeIfPresent(Int.self, forKey: .videoBitrateKbps)
        audioBitrateKbps = try container.decodeIfPresent(Int.self, forKey: .audioBitrateKbps)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate)
        audioChannels = try container.decodeIfPresent(Int.self, forKey: .audioChannels)
        isCustomCommandOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCustomCommandOverrideEnabled) ?? defaults.isCustomCommandOverrideEnabled
        customCommandTemplate = try container.decodeIfPresent(String.self, forKey: .customCommandTemplate) ?? defaults.customCommandTemplate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presetName, forKey: .presetName)
        try container.encode(isAudioOnly, forKey: .isAudioOnly)
        try container.encode(self.container, forKey: .container)
        try container.encode(videoCodec, forKey: .videoCodec)
        try container.encode(audioCodec, forKey: .audioCodec)
        try container.encode(qualityProfile, forKey: .qualityProfile)
        try container.encodeIfPresent(encoderOption, forKey: .encoderOption)
        try container.encode(resolutionOverride, forKey: .resolutionOverride)
        try container.encode(frameRateOption, forKey: .frameRateOption)
        try container.encodeIfPresent(customFrameRate, forKey: .customFrameRate)
        try container.encode(useHardwareAcceleration, forKey: .useHardwareAcceleration)
        try container.encode(removeMetadata, forKey: .removeMetadata)
        try container.encode(removeChapters, forKey: .removeChapters)
        try container.encode(removeEmbeddedSubtitles, forKey: .removeEmbeddedSubtitles)
        try container.encodeIfPresent(subtitleMode, forKey: .subtitleMode)
        try container.encode(subtitleAttachments, forKey: .subtitleAttachments)
        try container.encode(externalAudioAttachments, forKey: .externalAudioAttachments)
        try container.encode(enableHDRToSDR, forKey: .enableHDRToSDR)
        try container.encode(toneMapMode, forKey: .toneMapMode)
        try container.encode(toneMapPeak, forKey: .toneMapPeak)
        try container.encode(webOptimization, forKey: .webOptimization)
        try container.encode(outputTemplate, forKey: .outputTemplate)
        try container.encodeIfPresent(videoBitrateKbps, forKey: .videoBitrateKbps)
        try container.encodeIfPresent(audioBitrateKbps, forKey: .audioBitrateKbps)
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(audioChannels, forKey: .audioChannels)
        try container.encode(isCustomCommandOverrideEnabled, forKey: .isCustomCommandOverrideEnabled)
        try container.encode(customCommandTemplate, forKey: .customCommandTemplate)
    }
}

extension ConversionOptions {
    static func recommendedEncoderOption(
        videoCodec: VideoCodec,
        qualityProfile: QualityProfile
    ) -> EncoderOption {
        switch videoCodec {
        case .h264, .hevc:
            switch qualityProfile {
            case .smaller: return .veryFast
            case .balanced: return .fast
            case .better: return .slow
            }
        case .vp9, .av1:
            switch qualityProfile {
            case .smaller: return .fast
            case .balanced: return .medium
            case .better: return .slow
            }
        case .proRes:
            return .medium
        }
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
