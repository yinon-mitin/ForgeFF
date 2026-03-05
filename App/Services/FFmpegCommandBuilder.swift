import Foundation

enum FFmpegCommandBuilder {
    enum Mode: Equatable {
        case singlePass
        case pass(Int, logPrefix: String)
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
        buildArguments(for: job, settings: settings, capabilities: .none, mode: mode)
    }

    static func buildArguments(
        for job: VideoJob,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities,
        mode: Mode = .singlePass
    ) -> [String] {
        let outputURL = outputURL(for: job, settings: settings)
        var arguments = ["-hide_banner", settings.allowOverwrite ? "-y" : "-n", "-i", job.sourceURL.path]

        for subtitle in job.options.subtitleAttachments {
            arguments.append(contentsOf: ["-i", subtitle.fileURL.path])
        }

        if job.options.removeMetadata {
            arguments.append(contentsOf: ["-map_metadata", "-1"])
        }

        if job.options.removeChapters {
            arguments.append(contentsOf: ["-map_chapters", "-1"])
        }

        if job.options.isAudioOnly {
            arguments.append("-vn")
            arguments.append(contentsOf: ["-map", "0:a?"])
        } else {
            arguments.append(contentsOf: ["-map", "0:v:0", "-map", "0:a?"])

            if !job.options.removeEmbeddedSubtitles {
                if job.options.effectiveSubtitleMode != .remove {
                    arguments.append(contentsOf: ["-map", "0:s?"])
                }
            }

            appendExternalSubtitleMaps(for: job, into: &arguments)
            appendVideoEncoding(for: job, settings: settings, capabilities: capabilities, into: &arguments)
        }

        appendAudioEncoding(for: job, into: &arguments)
        appendSubtitleEncoding(for: job, into: &arguments)

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

    private static func appendVideoEncoding(
        for job: VideoJob,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities,
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
                arguments.append(contentsOf: ["-preset", h264SpeedPreset(for: job.options)])
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
                arguments.append(contentsOf: ["-preset", hevcSpeedPreset(for: job.options)])
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
            arguments.append(contentsOf: ["-row-mt", "1", "-threads", "\(defaultThreadCount())"])
        case .av1:
            appendAV1Encoding(for: job.options, capabilities: capabilities, into: &arguments)
        }

        if let frameRate = resolvedFrameRate(for: job.options) {
            arguments.append(contentsOf: ["-r", frameRate])
        }

        let filters = buildFilters(for: job.options)
        if !filters.isEmpty {
            arguments.append(contentsOf: ["-vf", filters.joined(separator: ",")])
        }
    }

    private static func appendAudioEncoding(for job: VideoJob, into arguments: inout [String]) {
        arguments.append(contentsOf: ["-c:a", job.options.audioCodec.ffmpegCodec])

        if let bitrate = job.options.effectiveAudioBitrateKbps {
            arguments.append(contentsOf: ["-b:a", "\(bitrate)k"])
        }

        if let channels = job.options.audioChannels, channels > 0 {
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

    private static func appendExternalSubtitleMaps(for job: VideoJob, into arguments: inout [String]) {
        guard job.options.effectiveSubtitleMode == .addExternal else { return }
        let subtitleStartIndex = 1
        for (index, subtitle) in job.options.subtitleAttachments.enumerated() {
            arguments.append(contentsOf: ["-map", "\(subtitleStartIndex + index):0"])
            let streamIndex = (job.metadata?.subtitleStreams.count ?? 0) + index
            arguments.append(contentsOf: ["-metadata:s:s:\(streamIndex)", "language=\(subtitle.languageCode)"])
        }
    }

    private static func buildFilters(for options: ConversionOptions) -> [String] {
        var filters = [String]()

        if let dimensions = options.resolutionOverride.dimensions {
            filters.append("scale=\(dimensions.0):\(dimensions.1):force_original_aspect_ratio=decrease")
        }

        if options.enableHDRToSDR {
            let peak = String(format: "%.0f", options.toneMapPeak)
            filters.append("zscale=t=linear:npl=\(peak)")
            filters.append("tonemap=tonemap=\(options.toneMapMode.rawValue):peak=\(peak)")
            filters.append("zscale=t=bt709:m=bt709:r=tv")
            filters.append("format=yuv420p")
        }

        return filters
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

    private static func h264SpeedPreset(for options: ConversionOptions) -> String {
        if options.presetName.contains("(Fast)") { return "veryfast" }
        if options.presetName.contains("(High Quality)") { return "slow" }
        return "medium"
    }

    private static func hevcSpeedPreset(for options: ConversionOptions) -> String {
        if options.presetName.contains("(Fast)") { return "fast" }
        if options.presetName.contains("(High Quality)") { return "slow" }
        return "medium"
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
            arguments.append(contentsOf: ["-preset", "\(av1SVTPreset(for: options.qualityProfile))"])
            return
        }

        arguments.append(contentsOf: ["-c:v", "libaom-av1"])
        arguments.append(contentsOf: ["-crf", "\(av1AOMCRF(for: options.qualityProfile))"])
        arguments.append(contentsOf: ["-cpu-used", "\(av1AOMCPUUsed(for: options.qualityProfile))"])
    }

    private static func av1SVTCRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 34
        case .balanced: return 30
        case .better: return 26
        }
    }

    private static func av1SVTPreset(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 8
        case .balanced: return 6
        case .better: return 4
        }
    }

    private static func av1AOMCRF(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 36
        case .balanced: return 32
        case .better: return 28
        }
    }

    private static func av1AOMCPUUsed(for quality: QualityProfile) -> Int {
        switch quality {
        case .smaller: return 8
        case .balanced: return 6
        case .better: return 4
        }
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
}
