import Foundation

enum FFprobeError: LocalizedError {
    case missingBinary
    case failed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "FFprobe is not configured. Set the ffmpeg/ffprobe paths in Settings."
        case let .failed(message):
            return message
        case .invalidOutput:
            return "FFprobe returned unreadable metadata."
        }
    }
}

enum FFprobeService {
    static func analyze(url: URL, ffprobeURL: URL?) async throws -> MediaMetadata {
        guard let executableURL = ffprobeURL else {
            throw FFprobeError.missingBinary
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-show_chapters",
            url.path
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8) ?? "FFprobe exited with \(process.terminationStatus)."
            throw FFprobeError.failed(message)
        }

        return try parse(jsonData: stdout)
    }

    static func parse(jsonData: Data) throws -> MediaMetadata {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(FFprobePayload.self, from: jsonData)
        return MediaMetadata(
            format: payload.format,
            streams: payload.streams,
            chapters: payload.chapters ?? []
        )
    }
}
