import Foundation

struct JobHistoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sourcePath: String
    let outputPath: String?
    let presetName: String
    let status: JobStatus
    let createdAt: Date
    let completedAt: Date?
    let sourceSize: Int64?
    let outputSize: Int64?
    let durationSeconds: Double?
    let averageSpeed: Double?
    let resolutionDescription: String
    let videoCodec: String
    let audioCodec: String
    let dynamicRange: String

    static func from(job: VideoJob) -> JobHistoryRecord {
        let recordedOptions = job.executionSnapshot?.options ?? job.options
        let stream = job.metadata?.videoStream
        let resolution: String
        if let width = stream?.width, let height = stream?.height {
            resolution = "\(width)x\(height)"
        } else {
            resolution = "Unknown"
        }

        return JobHistoryRecord(
            id: job.id,
            sourcePath: job.sourceURL.path,
            outputPath: job.result?.outputURL?.path,
            presetName: recordedOptions.presetName,
            status: job.status,
            createdAt: job.createdAt,
            completedAt: job.completedAt,
            sourceSize: job.metadata?.fileSizeBytes,
            outputSize: job.result?.outputFileSize,
            durationSeconds: job.result?.elapsedSeconds,
            averageSpeed: job.result?.averageSpeed,
            resolutionDescription: resolution,
            videoCodec: recordedOptions.videoCodec.displayName,
            audioCodec: recordedOptions.audioCodec.displayName,
            dynamicRange: job.metadata?.dynamicRangeDescription ?? "SDR"
        )
    }
}
