import Foundation

enum FFmpegCommandBuilder {
    struct CommandInvocation: Equatable {
        let executableURL: URL
        let arguments: [String]
        let commandLine: String
    }

    enum CommandInvocationError: Error, Equatable {
        case invalidCustomTemplate(String)
        case unsupportedToneMapping(String)
    }

    struct CustomCommandTemplateValidation: Equatable {
        let errorMessage: String?
    }

    enum Mode: Equatable {
        case singlePass
        case pass(Int, logPrefix: String)
    }

    struct InputSourceLayout: Equatable {
        let videoSourceURL: URL
        let originalMediaSourceURL: URL?

        static func standard(sourceURL: URL) -> InputSourceLayout {
            InputSourceLayout(videoSourceURL: sourceURL, originalMediaSourceURL: nil)
        }

        static func toneMappedIntermediate(videoSourceURL: URL, originalMediaSourceURL: URL) -> InputSourceLayout {
            InputSourceLayout(videoSourceURL: videoSourceURL, originalMediaSourceURL: originalMediaSourceURL)
        }

        var ancillarySourceInputIndex: Int {
            originalMediaSourceURL == nil ? 0 : 1
        }

        var firstAttachmentInputIndex: Int {
            originalMediaSourceURL == nil ? 1 : 2
        }
    }

    static func outputURL(for job: VideoJob, settings: AppSettings) -> URL {
        let baseFolder = resolveBaseFolder(for: job, settings: settings)
        let sourceBaseName = job.sourceURL.deletingPathExtension().lastPathComponent
        let preferredFilename: String
        if job.outputFilename.isEmpty || job.outputFilename == sourceBaseName {
            preferredFilename = OutputTemplateRenderer.render(template: job.options.outputTemplate, job: job)
        } else {
            preferredFilename = job.outputFilename
        }
        let initialURL = baseFolder
            .appendingPathComponent(preferredFilename)
            .appendingPathExtension(job.options.container.fileExtension)

        if settings.allowOverwrite {
            return initialURL
        }

        return uniquedOutputURL(for: initialURL)
    }

    static func buildArguments(for job: VideoJob, settings: AppSettings, mode: Mode = .singlePass) -> [String] {
        buildArguments(
            for: job,
            settings: settings,
            capabilities: .none,
            filterCapabilities: .fullySupported,
            sourceLayout: nil,
            mode: mode
        )
    }

    static func buildInvocation(
        for job: VideoJob,
        ffmpegURL: URL,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities = .none,
        filterCapabilities: FFmpegFilterCapabilities = .fullySupported,
        sourceLayout: InputSourceLayout? = nil,
        mode: Mode = .singlePass
    ) throws -> CommandInvocation {
        if job.options.isCustomCommandEnabled {
            return try buildCustomCommandInvocation(
                template: job.options.effectiveCustomCommandTemplate,
                inputURL: job.sourceURL,
                outputURL: outputURL(for: job, settings: settings),
                resolvedFFmpegURL: ffmpegURL
            )
        }

        if let toneMappingError = toneMappingSupportError(for: job, filterCapabilities: filterCapabilities) {
            throw CommandInvocationError.unsupportedToneMapping(toneMappingError)
        }

        let args = buildArguments(
            for: job,
            settings: settings,
            capabilities: capabilities,
            filterCapabilities: filterCapabilities,
            sourceLayout: sourceLayout,
            mode: mode
        )
        return CommandInvocation(
            executableURL: ffmpegURL,
            arguments: args,
            commandLine: commandLine(executableURL: ffmpegURL, arguments: args)
        )
    }

    static func buildArguments(
        for job: VideoJob,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities,
        filterCapabilities: FFmpegFilterCapabilities = .fullySupported,
        sourceLayout: InputSourceLayout? = nil,
        mode: Mode = .singlePass
    ) -> [String] {
        let outputURL = outputURL(for: job, settings: settings)
        let inputLayout = sourceLayout ?? .standard(sourceURL: job.sourceURL)
        var arguments = ["-hide_banner", settings.allowOverwrite ? "-y" : "-n", "-i", inputLayout.videoSourceURL.path]

        if let originalMediaSourceURL = inputLayout.originalMediaSourceURL {
            arguments.append(contentsOf: ["-i", originalMediaSourceURL.path])
        }

        for attachment in job.options.externalAudioAttachments {
            arguments.append(contentsOf: ["-i", attachment.fileURL.path])
        }

        for subtitle in job.options.subtitleAttachments {
            arguments.append(contentsOf: ["-i", subtitle.fileURL.path])
        }

        appendMetadataAndChapterMapping(
            for: job,
            inputLayout: inputLayout,
            into: &arguments
        )

        if job.options.isAudioOnly {
            arguments.append("-vn")
            appendAudioMaps(for: job, inputLayout: inputLayout, into: &arguments)
        } else {
            arguments.append(contentsOf: ["-map", "0:v:0"])
            appendAudioMaps(for: job, inputLayout: inputLayout, into: &arguments)
            if !job.options.externalAudioAttachments.isEmpty {
                arguments.append("-shortest")
            }

            if !job.options.removeEmbeddedSubtitles {
                if job.options.effectiveSubtitleMode != .remove {
                    arguments.append(contentsOf: ["-map", "\(inputLayout.ancillarySourceInputIndex):s?"])
                }
            }

            appendExternalSubtitleMaps(for: job, inputLayout: inputLayout, into: &arguments)
            appendVideoEncoding(
                for: job,
                settings: settings,
                capabilities: capabilities,
                filterCapabilities: filterCapabilities,
                into: &arguments
            )
        }

        appendAudioEncoding(for: job, into: &arguments)
        appendSubtitleEncoding(for: job, into: &arguments)
        if job.options.webOptimization && job.options.isWebOptimizationAvailable {
            arguments.append(contentsOf: ["-movflags", "+faststart"])
        }
        switch mode {
        case .singlePass:
            arguments.append(outputURL.path)
        case let .pass(number, logPrefix):
            arguments.append(contentsOf: ["-pass", "\(number)", "-passlogfile", logPrefix])
            if number == 1 {
                arguments.append(contentsOf: ["-f", "null", "/dev/null"])
            } else {
                arguments.append(outputURL.path)
            }
        }

        return arguments
    }

    static func commandLine(executableURL: URL, arguments: [String]) -> String {
        ([executableURL.path] + arguments).map(shellEscaped).joined(separator: " ")
    }

    static func validateCustomCommandTemplate(_ rawValue: String, enabled: Bool) -> CustomCommandTemplateValidation {
        guard enabled else {
            return CustomCommandTemplateValidation(errorMessage: nil)
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CustomCommandTemplateValidation(errorMessage: "Custom FFmpeg command template cannot be empty.")
        }
        guard trimmed.contains("{input}") else {
            return CustomCommandTemplateValidation(errorMessage: "Custom FFmpeg command must include {input}.")
        }
        guard trimmed.contains("{output}") else {
            return CustomCommandTemplateValidation(errorMessage: "Custom FFmpeg command must include {output}.")
        }
        let tokens = tokenizeCommandTemplate(trimmed)
        guard !tokens.isEmpty else {
            return CustomCommandTemplateValidation(errorMessage: "Custom FFmpeg command template cannot be parsed.")
        }
        return CustomCommandTemplateValidation(errorMessage: nil)
    }

    private static func buildCustomCommandInvocation(
        template: String,
        inputURL: URL,
        outputURL: URL,
        resolvedFFmpegURL: URL
    ) throws -> CommandInvocation {
        let validation = validateCustomCommandTemplate(template, enabled: true)
        if let error = validation.errorMessage {
            throw CommandInvocationError.invalidCustomTemplate(error)
        }

        let tokens = tokenizeCommandTemplate(template)
        guard !tokens.isEmpty else {
            throw CommandInvocationError.invalidCustomTemplate("Custom FFmpeg command template cannot be parsed.")
        }

        let substitutedTokens = tokens.map {
            $0.replacingOccurrences(of: "{input}", with: inputURL.path)
                .replacingOccurrences(of: "{output}", with: outputURL.path)
        }

        let executableToken = substitutedTokens[0]
        let executableURL: URL
        if executableToken == "ffmpeg" {
            executableURL = resolvedFFmpegURL
        } else {
            let explicitURL = URL(fileURLWithPath: executableToken)
            guard FileManager.default.isExecutableFile(atPath: explicitURL.path) else {
                throw CommandInvocationError.invalidCustomTemplate("Custom FFmpeg command executable not found or not executable.")
            }
            executableURL = explicitURL
        }

        let arguments = Array(substitutedTokens.dropFirst())
        return CommandInvocation(
            executableURL: executableURL,
            arguments: arguments,
            commandLine: commandLine(executableURL: executableURL, arguments: arguments)
        )
    }

    private static func appendVideoEncoding(
        for job: VideoJob,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities,
        filterCapabilities: FFmpegFilterCapabilities,
        into arguments: inout [String]
    ) {
        let useHardwareAcceleration = shouldUseVideoToolbox(for: job.options, settings: settings)

        switch job.options.videoCodec {
        case .h264:
            if useHardwareAcceleration {
                arguments.append(contentsOf: ["-c:v", "h264_videotoolbox"])
                if let bitrate = customOrDefaultVideoToolboxBitrateKbps(options: job.options, codec: .h264) {
                    arguments.append(contentsOf: ["-b:v", "\(bitrate)k"])
                }
            } else {
                arguments.append(contentsOf: ["-c:v", "libx264"])
                arguments.append(contentsOf: ["-preset", x264Preset(for: job.options.effectiveEncoderOption)])
                if let customBitrate = job.options.videoBitrateKbps {
                    arguments.append(contentsOf: ["-b:v", "\(customBitrate)k"])
                } else {
                    arguments.append(contentsOf: ["-crf", "\(h264CRF(for: job.options.qualityProfile))"])
                }
            }
        case .hevc:
            if useHardwareAcceleration {
                arguments.append(contentsOf: ["-c:v", "hevc_videotoolbox"])
                if let bitrate = customOrDefaultVideoToolboxBitrateKbps(options: job.options, codec: .hevc) {
                    arguments.append(contentsOf: ["-b:v", "\(bitrate)k"])
                }
            } else {
                arguments.append(contentsOf: ["-c:v", "libx265"])
                arguments.append(contentsOf: ["-preset", x265Preset(for: job.options.effectiveEncoderOption)])
                if let customBitrate = job.options.videoBitrateKbps {
                    arguments.append(contentsOf: ["-b:v", "\(customBitrate)k"])
                } else {
                    arguments.append(contentsOf: ["-crf", "\(hevcCRF(for: job.options.qualityProfile))"])
                }
            }
        case .proRes:
            arguments.append(contentsOf: ["-c:v", "prores_ks", "-profile:v", "3"])
        case .vp9:
            arguments.append(contentsOf: ["-c:v", "libvpx-vp9"])
            if let customBitrate = job.options.videoBitrateKbps {
                arguments.append(contentsOf: ["-b:v", "\(customBitrate)k"])
            } else {
                arguments.append(contentsOf: ["-b:v", "0", "-crf", "\(vp9CRF(for: job.options.qualityProfile))"])
            }
            arguments.append(contentsOf: ["-cpu-used", "\(vp9CPUUsed(for: job.options.effectiveEncoderOption))"])
            arguments.append(contentsOf: ["-row-mt", "1", "-threads", "\(defaultThreadCount())"])
        case .av1:
            appendAV1Encoding(for: job.options, capabilities: capabilities, into: &arguments)
        }

        if shouldForceHEVCCompatibleTag(for: job.options) {
            arguments.append(contentsOf: ["-tag:v", "hvc1"])
        }

        if let frameRate = resolvedFrameRate(for: job.options) {
            arguments.append(contentsOf: ["-r", frameRate])
        }

        let filters = buildFilters(for: job, filterCapabilities: filterCapabilities)
        if !filters.isEmpty {
            arguments.append(contentsOf: ["-vf", filters.joined(separator: ",")])
        }

        if job.options.videoPixelFormat == .yuv420p {
            arguments.append(contentsOf: ["-pix_fmt", "yuv420p"])
        }
    }

    private static func appendAudioEncoding(for job: VideoJob, into arguments: inout [String]) {
        arguments.append(contentsOf: ["-c:a", job.options.audioCodec.ffmpegCodec])

        if let bitrate = job.options.effectiveAudioBitrateKbps {
            arguments.append(contentsOf: ["-b:a", "\(bitrate)k"])
        }

        if let channels = resolvedAudioChannels(for: job.options), channels > 0 {
            arguments.append(contentsOf: ["-ac", "\(channels)"])
        }
    }

    private static func appendSubtitleEncoding(for job: VideoJob, into arguments: inout [String]) {
        if job.options.effectiveSubtitleMode == .remove && job.options.subtitleAttachments.isEmpty {
            arguments.append("-sn")
            return
        }

        guard job.options.effectiveSubtitleMode == .addExternal,
              !job.options.subtitleAttachments.isEmpty else { return }
        let subtitleCodec = job.options.container == .mp4 ? "mov_text" : "srt"
        arguments.append(contentsOf: ["-c:s", subtitleCodec])
    }

    private static func appendExternalSubtitleMaps(
        for job: VideoJob,
        inputLayout: InputSourceLayout,
        into arguments: inout [String]
    ) {
        guard job.options.effectiveSubtitleMode == .addExternal else { return }
        let subtitleStartIndex = inputLayout.firstAttachmentInputIndex + job.options.externalAudioAttachments.count
        for (index, subtitle) in job.options.subtitleAttachments.enumerated() {
            arguments.append(contentsOf: ["-map", "\(subtitleStartIndex + index):0"])
            let streamIndex = (job.metadata?.subtitleStreams.count ?? 0) + index
            arguments.append(contentsOf: ["-metadata:s:s:\(streamIndex)", "language=\(subtitle.languageCode)"])
        }
    }

    private static func appendAudioMaps(
        for job: VideoJob,
        inputLayout: InputSourceLayout,
        into arguments: inout [String]
    ) {
        if job.options.externalAudioAttachments.isEmpty {
            arguments.append(contentsOf: ["-map", "\(inputLayout.ancillarySourceInputIndex):a?"])
            return
        }

        for index in job.options.externalAudioAttachments.indices {
            arguments.append(contentsOf: ["-map", "\(inputLayout.firstAttachmentInputIndex + index):a:0?"])
        }
    }

    private static func appendMetadataAndChapterMapping(
        for job: VideoJob,
        inputLayout: InputSourceLayout,
        into arguments: inout [String]
    ) {
        if job.options.removeMetadata {
            arguments.append(contentsOf: ["-map_metadata", "-1"])
        } else if inputLayout.originalMediaSourceURL != nil {
            arguments.append(contentsOf: ["-map_metadata", "\(inputLayout.ancillarySourceInputIndex)"])
        }

        if job.options.removeChapters {
            arguments.append(contentsOf: ["-map_chapters", "-1"])
        } else if inputLayout.originalMediaSourceURL != nil {
            arguments.append(contentsOf: ["-map_chapters", "\(inputLayout.ancillarySourceInputIndex)"])
        }
    }

    static func toneMappingSupportError(
        for job: VideoJob,
        filterCapabilities: FFmpegFilterCapabilities
    ) -> String? {
        guard job.options.enableHDRToSDR, job.metadata?.isHDR == true else { return nil }
        return filterCapabilities.supportsToneMapping ? nil : unsupportedToneMappingHelpText
    }

    private static func buildFilters(
        for job: VideoJob,
        filterCapabilities: FFmpegFilterCapabilities
    ) -> [String] {
        let options = job.options
        var filters = [String]()

        if let dimensions = options.resolutionOverride.dimensions {
            filters.append("scale=\(dimensions.0):\(dimensions.1):force_original_aspect_ratio=decrease")
        }

        if options.enableHDRToSDR,
           job.metadata?.isHDR == true,
           let toneMappingPipeline = resolvedToneMappingPipeline(for: job, filterCapabilities: filterCapabilities) {
            switch toneMappingPipeline {
            case .libplacebo:
                filters.append(libplaceboToneMappingFilter(for: options))
            case .zscale:
                let nominalPeak = String(format: "%.0f", resolvedToneMapNominalPeak(for: options))
                filters.append("zscale=t=linear:npl=\(nominalPeak)")
                filters.append("tonemap=tonemap=\(zscaleToneMapMode(for: options.toneMapMode)):desat=0.15")
                filters.append("zscale=p=bt709:t=bt709:m=bt709:r=tv")
                if filterCapabilities.supportsEq {
                    filters.append("eq=gamma=1.05:contrast=1.02:brightness=0.02")
                }
                filters.append("format=yuv420p")
            }
        }

        return filters
    }

    private enum ToneMappingPipeline {
        case libplacebo
        case zscale
    }

    private static func resolvedFrameRate(for options: ConversionOptions) -> String? {
        if let preset = options.frameRateOption.numericValue {
            return String(Int(preset))
        }

        guard options.frameRateOption == .custom,
              let custom = options.customFrameRate,
              custom > 0 else {
            return nil
        }

        if custom.rounded(.towardZero) == custom {
            return String(Int(custom))
        }
        return String(custom)
    }

    private static func shouldUseVideoToolbox(for options: ConversionOptions, settings: AppSettings) -> Bool {
        guard settings.autoUseVideoToolbox,
              options.useHardwareAcceleration,
              options.qualityProfile != .better else {
            return false
        }

        return options.videoCodec == .h264 || options.videoCodec == .hevc
    }

    private static func h264CRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 23
        case .balanced: return 21
        case .better: return 19
        }
    }

    private static func hevcCRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 28
        case .balanced: return 26
        case .better: return 24
        }
    }

    private static func x264Preset(for option: EncoderOption) -> String {
        switch option {
        case .veryFast: return "veryfast"
        case .fast: return "fast"
        case .medium: return "medium"
        case .slow: return "slow"
        }
    }

    private static func x265Preset(for option: EncoderOption) -> String {
        switch option {
        case .veryFast: return "veryfast"
        case .fast: return "fast"
        case .medium: return "medium"
        case .slow: return "slow"
        }
    }

    private static func shouldForceHEVCCompatibleTag(for options: ConversionOptions) -> Bool {
        options.videoCodec == .hevc && (options.container == .mp4 || options.container == .mov)
    }

    private static func customOrDefaultVideoToolboxBitrateKbps(options: ConversionOptions, codec: VideoCodec) -> Int? {
        if let custom = options.videoBitrateKbps { return custom }
        switch (codec, options.qualityProfile) {
        case (.h264, .smaller): return 4_000
        case (.h264, .balanced): return 6_000
        case (.h264, .better): return 8_000
        case (.hevc, .smaller): return 2_500
        case (.hevc, .balanced): return 4_000
        case (.hevc, .better): return 5_500
        default: return nil
        }
    }

    private static func vp9CRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 36
        case .balanced: return 32
        case .better: return 28
        }
    }

    private static func vp9CPUUsed(for option: EncoderOption) -> Int {
        switch option {
        case .veryFast: return 6
        case .fast: return 5
        case .medium: return 4
        case .slow: return 2
        }
    }

    private static func defaultThreadCount() -> Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 8)
    }

    private static func appendAV1Encoding(
        for options: ConversionOptions,
        capabilities: FFmpegEncoderCapabilities,
        into arguments: inout [String]
    ) {
        if capabilities.supportsSVTAV1 {
            arguments.append(contentsOf: ["-c:v", "libsvtav1"])
            arguments.append(contentsOf: ["-crf", "\(av1SVTCRF(for: options.qualityProfile))"])
            arguments.append(contentsOf: ["-preset", "\(svtAV1Preset(for: options.effectiveEncoderOption))"])
            return
        }

        arguments.append(contentsOf: ["-c:v", "libaom-av1"])
        arguments.append(contentsOf: ["-crf", "\(av1AOMCRF(for: options.qualityProfile))"])
        arguments.append(contentsOf: ["-cpu-used", "\(aomAV1CPUUsed(for: options.effectiveEncoderOption))"])
    }

    private static func av1SVTCRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 34
        case .balanced: return 30
        case .better: return 26
        }
    }

    private static func svtAV1Preset(for option: EncoderOption) -> Int {
        switch option {
        case .veryFast: return 8
        case .fast: return 6
        case .medium: return 5
        case .slow: return 4
        }
    }

    private static func av1AOMCRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 36
        case .balanced: return 32
        case .better: return 28
        }
    }

    private static func aomAV1CPUUsed(for option: EncoderOption) -> Int {
        switch option {
        case .veryFast: return 6
        case .fast: return 5
        case .medium: return 4
        case .slow: return 2
        }
    }

    private static var unsupportedToneMappingHelpText: String {
        "HDR tone mapping requires Apple's avconvert or an FFmpeg build with libplacebo or zscale."
    }

    private static func resolvedToneMappingPipeline(
        for job: VideoJob,
        filterCapabilities: FFmpegFilterCapabilities
    ) -> ToneMappingPipeline? {
        guard job.options.enableHDRToSDR else { return nil }
        guard toneMappingSupportError(for: job, filterCapabilities: filterCapabilities) == nil else { return nil }

        if filterCapabilities.supportsLibplacebo {
            return .libplacebo
        }

        if filterCapabilities.supportsZscale {
            return .zscale
        }

        return nil
    }

    private static func libplaceboToneMappingFilter(for options: ConversionOptions) -> String {
        "libplacebo=tonemapping=\(libplaceboToneMapMode(for: options.toneMapMode)):peak_detect=true:colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv:format=yuv420p"
    }

    private static func libplaceboToneMapMode(for mode: ToneMapMode) -> String {
        switch mode {
        case .hable:
            return "hable"
        case .reinhard:
            // BT.2390 produces a brighter, more standard SDR result than raw Hable in libplacebo.
            return "bt.2390"
        }
    }

    private static func zscaleToneMapMode(for mode: ToneMapMode) -> String {
        switch mode {
        case .hable:
            return "hable"
        case .reinhard:
            return "reinhard"
        }
    }

    private static func resolvedToneMapNominalPeak(for options: ConversionOptions) -> Double {
        // Older builds stored 1000 as a source-style HDR peak. Clamp legacy values back to an SDR-ish nominal peak.
        if options.toneMapPeak > 300 {
            return 100
        }
        return max(48, min(options.toneMapPeak, 203))
    }

    private static func resolveBaseFolder(for job: VideoJob, settings: AppSettings) -> URL {
        if let outputDirectory = job.outputDirectory {
            return outputDirectory
        }

        if let bookmark = settings.defaultOutputDirectoryBookmark,
           let bookmarkedURL = resolveBookmarkURL(bookmark) {
            if settings.organizeByDate {
                let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
                return bookmarkedURL.appendingPathComponent(String(date), isDirectory: true)
            }
            return bookmarkedURL
        }

        return job.sourceURL.deletingLastPathComponent()
    }

    private static func resolveBookmarkURL(_ bookmarkData: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            bookmarkDataIsStale: &stale
        )
    }

    private static func uniquedOutputURL(for candidate: URL) -> URL {
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let directory = candidate.deletingLastPathComponent()
        let baseName = candidate.deletingPathExtension().lastPathComponent
        let fileExtension = candidate.pathExtension

        for index in 1...999 {
            let next = directory
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension(fileExtension)
            if !FileManager.default.fileExists(atPath: next.path) {
                return next
            }
        }

        return candidate
    }

    private static func resolvedAudioChannels(for options: ConversionOptions) -> Int? {
        guard options.audioCodec != .copy else { return nil }
        guard let requested = options.audioChannels, requested > 0 else { return nil }
        if options.audioCodec == .mp3, requested > 2 {
            return 2
        }
        return requested
    }

    static func tokenizeCommandTemplate(_ rawValue: String) -> [String] {
        var tokens = [String]()
        var current = ""
        var quoteCharacter: Character?
        var escaping = false

        for character in rawValue {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if let openQuote = quoteCharacter {
                if character == openQuote {
                    quoteCharacter = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quoteCharacter = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func shellEscaped(_ token: String) -> String {
        if token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil &&
            !token.contains("\"") && !token.contains("'") {
            return token
        }
        return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
