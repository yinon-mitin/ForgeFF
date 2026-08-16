import Foundation

enum JobStatus: String, Codable, CaseIterable {
    case queued
    case analyzing
    case ready
    case running
    case paused
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

struct JobResultSummary: Codable, Equatable {
    var outputURL: URL?
    var outputFileSize: Int64?
    var elapsedSeconds: Double?
    var averageSpeed: Double?
    var encodedFrameCount: Int? = nil
    var averageFramesPerSecond: Double? = nil
}

struct FailureDiagnosticReport: Equatable {
    let suggestedFilename: String
    let contents: String

    init(
        job: VideoJob,
        generatedAt: Date = Date(),
        appVersion: String,
        appBuild: String
    ) {
        let timestamp = Self.timestampFormatter.string(from: generatedAt)
        let sourceStem = Self.sanitizedFilenameComponent(
            job.sourceURL.deletingPathExtension().lastPathComponent
        )
        suggestedFilename = "ForgeFF-\(sourceStem)-\(job.status.rawValue)-\(timestamp).txt"

        let options = job.effectiveOptionsForDisplay
        let videoStream = job.metadata?.videoStream
        let resolution = [videoStream?.width, videoStream?.height]
            .compactMap { $0 }
            .count == 2
            ? "\(videoStream?.width ?? 0)x\(videoStream?.height ?? 0)"
            : "Unknown"

        var lines = [
            "ForgeFF Conversion Diagnostic Report",
            "Generated: \(Self.iso8601Formatter.string(from: generatedAt))",
            "Application: ForgeFF \(appVersion) (\(appBuild))",
            "Task ID: \(job.id.uuidString)",
            "Status: \(job.status.rawValue.capitalized)",
            "",
            "Task",
            "Source: \(job.sourceURL.path)",
            "Output: \(job.result?.outputURL?.path ?? "Not created")",
            "Preset: \(options.presetName)",
            "Container: \(options.container.rawValue.uppercased())",
            "Video codec: \(options.videoCodec.displayName)",
            "Audio codec: \(options.audioCodec.displayName)",
            "Resolution: \(resolution)",
            "Source FPS: \(Self.decimalString(videoStream?.frameRateValue))",
            "Dynamic range: \(job.metadata?.dynamicRangeDescription ?? "Unknown")",
            "Input bytes: \(job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes ?? 0)",
            "Elapsed seconds: \(Self.decimalString(job.result?.elapsedSeconds))",
            "Average processing FPS: \(Self.decimalString(job.result?.averageFramesPerSecond))",
            "",
            "Error Summary",
            job.errorSummary ?? (job.status == .cancelled ? "The conversion was cancelled." : "Conversion failed."),
            "",
            "FFmpeg",
            job.ffmpegVersion ?? "Unknown",
            "",
            "Executed Command",
            job.commandLine ?? "Not available",
            "",
            "Error Log",
            job.errorLog ?? "No details available."
        ]
        lines.append("")
        contents = lines.joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func sanitizedFilenameComponent(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return sanitized.isEmpty ? "conversion" : String(sanitized.prefix(80))
    }

    private static func decimalString(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return String(format: "%.2f", value)
    }
}

struct JobExecutionSnapshot: Codable, Equatable {
    var options: ConversionOptions
    var outputDirectory: URL?
    var outputFilename: String
}

struct VideoJob: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceURL: URL
    var outputDirectory: URL?
    var outputFilename: String
    var options: ConversionOptions
    var status: JobStatus
    var progress: Double
    var estimatedRemainingSeconds: Double?
    var currentFramesPerSecond: Double?
    var metadata: MediaMetadata?
    var inputFileSizeBytes: Int64?
    var estimatedOutputSizeBytes: Int64?
    var estimatedOutputDeltaPercent: Double?
    var errorMessage: String?
    var errorDetails: String?
    var commandLine: String?
    var ffmpegVersion: String?
    var result: JobResultSummary?
    var executionSnapshot: JobExecutionSnapshot?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputDirectory: URL? = nil,
        outputFilename: String? = nil,
        options: ConversionOptions = .default
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.outputFilename = outputFilename ?? sourceURL.deletingPathExtension().lastPathComponent
        self.options = options
        self.status = .queued
        self.progress = 0
        self.estimatedRemainingSeconds = nil
        self.currentFramesPerSecond = nil
        self.metadata = nil
        self.inputFileSizeBytes = nil
        self.estimatedOutputSizeBytes = nil
        self.estimatedOutputDeltaPercent = nil
        self.errorMessage = nil
        self.errorDetails = nil
        self.commandLine = nil
        self.ffmpegVersion = nil
        self.result = nil
        self.executionSnapshot = nil
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
    }

    var sourceDisplayName: String {
        sourceURL.lastPathComponent
    }

    var errorSummary: String? {
        errorMessage
    }

    var errorLog: String? {
        errorDetails
    }

    var resolvedOutputFilename: String {
        outputFilename.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : outputFilename
    }

    var previewURL: URL {
        if status == .completed, let outputURL = result?.outputURL {
            return outputURL
        }
        return sourceURL
    }

    var effectiveOptionsForDisplay: ConversionOptions {
        switch status {
        case .running, .paused:
            return executionSnapshot?.options ?? options
        default:
            return options
        }
    }

    var fromFormatSummary: String {
        let container: String = {
            if let formatName = metadata?.format.formatName?
                .split(separator: ",")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !formatName.isEmpty {
                return formatName.uppercased()
            }
            return sourceURL.pathExtension.uppercased()
        }()

        if let videoCodec = metadata?.videoStream?.codecName?.uppercased(), !videoCodec.isEmpty {
            return "\(container) (\(videoCodec))"
        }
        if let audioCodec = metadata?.audioStreams.first?.codecName?.uppercased(), !audioCodec.isEmpty {
            return "\(container) (\(audioCodec))"
        }
        return container
    }

    var toFormatSummary: String {
        let options = effectiveOptionsForDisplay

        if options.isAudioOnly {
            switch options.audioCodec {
            case .mp3:
                return "MP3"
            case .aac:
                return "M4A (AAC)"
            case .copy:
                return "\(options.container.fileExtension.uppercased()) (Keep Audio)"
            case .pcm:
                return "WAV (PCM)"
            }
        }
        return "\(options.container.fileExtension.uppercased()) (\(options.videoCodec.displayName))"
    }

    var formatTransitionSummary: String {
        "\(fromFormatSummary) → \(toFormatSummary)"
    }
}
