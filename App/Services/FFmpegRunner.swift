import Darwin
import Foundation

struct FFmpegProgress {
    var ratio: Double
    var encodedSeconds: Double
    var speed: Double?
    var etaSeconds: Double?
}

enum FFmpegRunnerError: LocalizedError {
    case missingBinary
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "FFmpeg is not configured. Set the ffmpeg binary path in Settings."
        case let .processFailed(message):
            return message
        case .cancelled:
            return "The conversion was cancelled."
        }
    }
}

final class FFmpegRunner {
    private var currentProcess: Process?
    private var isCancelled = false

    func run(
        job: VideoJob,
        ffmpegURL: URL?,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities = .none,
        progress: @escaping @Sendable (FFmpegProgress) -> Void
    ) async throws -> JobResultSummary {
        guard let executableURL = ffmpegURL else {
            throw FFmpegRunnerError.missingBinary
        }

        isCancelled = false
        let outputURL = FFmpegCommandBuilder.outputURL(for: job, settings: settings)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let startDate = Date()
        var lastSpeed: Double?
        let finalSpeed = try await execute(
            executableURL: executableURL,
            arguments: FFmpegCommandBuilder.buildArguments(for: job, settings: settings, capabilities: capabilities),
            totalDuration: job.metadata?.durationSeconds,
            progress: progress
        ) { update in
            lastSpeed = update.speed
        }
        lastSpeed = finalSpeed

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return JobResultSummary(
            outputURL: outputURL,
            outputFileSize: fileSize,
            elapsedSeconds: Date().timeIntervalSince(startDate),
            averageSpeed: lastSpeed
        )
    }

    func pause() {
        guard let pid = currentProcess?.processIdentifier else { return }
        Darwin.kill(pid_t(pid), SIGSTOP)
    }

    func resume() {
        guard let pid = currentProcess?.processIdentifier else { return }
        Darwin.kill(pid_t(pid), SIGCONT)
    }

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
    }

    @discardableResult
    private func execute(
        executableURL: URL,
        arguments: [String],
        totalDuration: Double?,
        progress: @escaping @Sendable (FFmpegProgress) -> Void,
        progressTap: @escaping (FFmpegProgress) -> Void
    ) async throws -> Double? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        currentProcess = process

        let accumulatedError = SynchronizedDataBuffer()
        let handle = stderrPipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            accumulatedError.append(data)

            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                guard let parsed = Self.parseProgress(line: String(line), totalDuration: totalDuration) else { continue }
                progress(parsed)
                progressTap(parsed)
            }
        }

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] process in
                handle.readabilityHandler = nil
                self?.currentProcess = nil

                if self?.isCancelled == true {
                    continuation.resume(throwing: FFmpegRunnerError.cancelled)
                    return
                }

                guard process.terminationStatus == 0 else {
                    let message = String(data: accumulatedError.data, encoding: .utf8) ?? "FFmpeg exited with \(process.terminationStatus)."
                    continuation.resume(throwing: FFmpegRunnerError.processFailed(message))
                    return
                }

                let summary = String(data: accumulatedError.data, encoding: .utf8) ?? ""
                let speed = Self.lastSpeed(in: summary)
                continuation.resume(returning: speed)
            }
        }
    }

    static func parseProgress(line: String, totalDuration: Double?) -> FFmpegProgress? {
        guard let timeToken = value(in: line, key: "time") else { return nil }
        let encodedSeconds = parseTimestamp(timeToken)
        let speed = value(in: line, key: "speed").flatMap(parseSpeed)
        let ratio = totalDuration.map { min(max(encodedSeconds / $0, 0), 1) } ?? 0
        let eta = totalDuration.flatMap { total -> Double? in
            guard let speed, speed > 0 else { return nil }
            let remaining = max(total - encodedSeconds, 0)
            return remaining / speed
        }
        return FFmpegProgress(ratio: ratio, encodedSeconds: encodedSeconds, speed: speed, etaSeconds: eta)
    }

    private static func value(in line: String, key: String) -> String? {
        let pattern = "\(key)=\\s*([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private static func parseTimestamp(_ text: String) -> Double {
        let components = text.split(separator: ":").compactMap { Double($0) }
        guard components.count == 3 else { return 0 }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private static func parseSpeed(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "x", with: ""))
    }

    private static func lastSpeed(in stderr: String) -> Double? {
        stderr
            .split(whereSeparator: \.isNewline)
            .reversed()
            .compactMap { value(in: String($0), key: "speed") }
            .compactMap(parseSpeed)
            .first
    }
}

private final class SynchronizedDataBuffer {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
