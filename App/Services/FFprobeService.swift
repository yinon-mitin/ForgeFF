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

        let result = try await run(
            process: process,
            outputHandle: output.fileHandleForReading,
            errorHandle: error.fileHandleForReading
        )

        guard result.status == 0 else {
            let message = String(data: result.stderr, encoding: .utf8) ?? "FFprobe exited with \(result.status)."
            throw FFprobeError.failed(message)
        }

        return try parse(jsonData: result.stdout)
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

    private static func run(
        process: Process,
        outputHandle: FileHandle,
        errorHandle: FileHandle
    ) async throws -> (stdout: Data, stderr: Data, status: Int32) {
        let stdout = FFprobeDataBuffer()
        let stderr = FFprobeDataBuffer()

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdout.append(data) }
        }
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderr.append(data) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                stdout.append(outputHandle.readDataToEndOfFile())
                stderr.append(errorHandle.readDataToEndOfFile())
                continuation.resume(returning: (stdout.data, stderr.data, finishedProcess.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class FFprobeDataBuffer {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
