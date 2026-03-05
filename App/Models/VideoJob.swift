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
    var metadata: MediaMetadata?
    var inputFileSizeBytes: Int64?
    var errorMessage: String?
    var errorDetails: String?
    var commandLine: String?
    var result: JobResultSummary?
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
        self.metadata = nil
        self.inputFileSizeBytes = nil
        self.errorMessage = nil
        self.errorDetails = nil
        self.commandLine = nil
        self.result = nil
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
}
