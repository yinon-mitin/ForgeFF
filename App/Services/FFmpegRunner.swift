import Darwin
import Foundation

struct FFmpegProgress {
    var ratio: Double
    var encodedSeconds: Double
    var framesPerSecond: Double?
    var speed: Double?
    var etaSeconds: Double?
    var outputBytes: Int64?
}

enum FFmpegRunnerError: LocalizedError {
    case missingBinary
    case invalidCustomCommand(String)
    case invalidConfiguration(String)
    case processFailed(summary: String, details: String, commandLine: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "FFmpeg is not configured. Set the ffmpeg binary path in Settings."
        case let .invalidCustomCommand(message):
            return message
        case let .invalidConfiguration(message):
            return message
        case let .processFailed(summary, _, _):
            return summary
        case .cancelled:
            return "The conversion was cancelled."
        }
    }

    var details: String? {
        switch self {
        case let .processFailed(_, details, _):
            return details
        default:
            return nil
        }
    }

    var commandLine: String? {
        switch self {
        case let .processFailed(_, _, commandLine):
            return commandLine
        default:
            return nil
        }
    }
}

final class FFmpegRunner {
    private var currentProcess: Process?
    private var isCancelled = false
    private(set) var lastResolvedVersion: String?

    func clearResolvedVersion() {
        lastResolvedVersion = nil
    }

    func run(
        job: VideoJob,
        ffmpegURL: URL?,
        settings: AppSettings,
        capabilities: FFmpegEncoderCapabilities = .none,
        filterCapabilities: FFmpegFilterCapabilities = .fullySupported,
        progress: @MainActor @escaping (FFmpegProgress) -> Void
    ) async throws -> JobResultSummary {
        guard let executableURL = ffmpegURL else {
            throw FFmpegRunnerError.missingBinary
        }

        isCancelled = false
        let invocation: FFmpegCommandBuilder.CommandInvocation
        do {
            invocation = try FFmpegCommandBuilder.buildInvocation(
                for: job,
                ffmpegURL: executableURL,
                settings: settings,
                capabilities: capabilities,
                filterCapabilities: filterCapabilities
            )
        } catch let FFmpegCommandBuilder.CommandInvocationError.invalidCustomTemplate(message) {
            throw FFmpegRunnerError.invalidCustomCommand(message)
        } catch let FFmpegCommandBuilder.CommandInvocationError.unsupportedToneMapping(message) {
            throw FFmpegRunnerError.invalidConfiguration(message)
        } catch {
            throw FFmpegRunnerError.invalidCustomCommand("Invalid custom FFmpeg command template.")
        }
        return try await run(
            invocation: invocation,
            outputURL: FFmpegCommandBuilder.outputURL(for: job, settings: settings),
            totalDuration: job.metadata?.durationSeconds,
            progress: progress
        )
    }

    func run(
        invocation: FFmpegCommandBuilder.CommandInvocation,
        outputURL: URL,
        totalDuration: Double?,
        progress: @MainActor @escaping (FFmpegProgress) -> Void
    ) async throws -> JobResultSummary {
        isCancelled = false
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let startDate = Date()
        var lastSpeed: Double?
        lastResolvedVersion = await Self.resolveVersionString(for: invocation.executableURL)
        let finalSpeed = try await execute(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            totalDuration: totalDuration,
            commandLine: invocation.commandLine,
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

    func cancel(force: Bool = false) {
        isCancelled = true
        guard let process = currentProcess else { return }
        if force {
            Darwin.kill(pid_t(process.processIdentifier), SIGKILL)
        } else {
            process.terminate()
        }
    }

    @discardableResult
    private func execute(
        executableURL: URL,
        arguments: [String],
        totalDuration: Double?,
        commandLine: String,
        progress: @MainActor @escaping (FFmpegProgress) -> Void,
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
        let progressGate = ProcessProgressEmissionGate(minimumInterval: 0.1)
        let handle = stderrPipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            accumulatedError.append(data)

            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                guard let parsed = Self.parseProgress(line: String(line), totalDuration: totalDuration) else { continue }
                progressTap(parsed)
                guard progressGate.shouldEmit(force: parsed.ratio >= 1) else { continue }
                Task { @MainActor in
                    progress(parsed)
                }
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
                    let stderrOutput = String(data: accumulatedError.data, encoding: .utf8) ?? "FFmpeg exited with \(process.terminationStatus)."
                    let summary = Self.errorSummary(from: stderrOutput)
                    continuation.resume(
                        throwing: FFmpegRunnerError.processFailed(
                            summary: summary,
                            details: stderrOutput,
                            commandLine: commandLine
                        )
                    )
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
        guard let encodedSeconds = parseTimestamp(timeToken) else { return nil }
        let framesPerSecond = value(in: line, key: "fps").flatMap(Double.init)
        let speed = value(in: line, key: "speed").flatMap(parseSpeed)
        let outputBytes = value(in: line, key: "size").flatMap(parseOutputSize)
        let ratio = totalDuration.map { min(max(encodedSeconds / $0, 0), 1) } ?? 0
        let eta = totalDuration.flatMap { total -> Double? in
            guard let speed, speed > 0 else { return nil }
            let remaining = max(total - encodedSeconds, 0)
            return remaining / speed
        }
        return FFmpegProgress(
            ratio: ratio,
            encodedSeconds: encodedSeconds,
            framesPerSecond: framesPerSecond,
            speed: speed,
            etaSeconds: eta,
            outputBytes: outputBytes
        )
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

    private static func parseTimestamp(_ text: String) -> Double? {
        let components = text.split(separator: ":").compactMap { Double($0) }
        guard components.count == 3 else { return nil }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private static func parseSpeed(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "x", with: ""))
    }

    private static func parseOutputSize(_ text: String) -> Int64? {
        let numberText = text.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(numberText), value > 0 else { return nil }

        let unit = text.dropFirst(numberText.count).lowercased()
        let multiplier: Double
        switch unit {
        case "", "b": multiplier = 1
        case "kb": multiplier = 1_000
        case "kib": multiplier = 1_024
        case "mb": multiplier = 1_000_000
        case "mib": multiplier = 1_048_576
        case "gb": multiplier = 1_000_000_000
        case "gib": multiplier = 1_073_741_824
        default: return nil
        }
        return Int64(value * multiplier)
    }

    private static func lastSpeed(in stderr: String) -> Double? {
        stderr
            .split(whereSeparator: \.isNewline)
            .reversed()
            .compactMap { value(in: String($0), key: "speed") }
            .compactMap(parseSpeed)
            .first
    }

    private static func errorSummary(from stderr: String) -> String {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let specific = lines.reversed().first(where: { $0.lowercased().contains("error") }) {
            return specific
        }
        return lines.last ?? "FFmpeg failed with no error output."
    }

    private static func resolveVersionString(for executableURL: URL) async -> String? {
        let key = executableURL.path
        if let cached = await VersionCache.shared.value(for: key) {
            return cached
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-version"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            let data = try await captureOutput(process: process, handle: outputPipe.fileHandleForReading)
            let firstLine = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await VersionCache.shared.store(firstLine, for: key)
            return firstLine
        } catch {
            await VersionCache.shared.store(nil, for: key)
            return nil
        }
    }

    private static func captureOutput(process: Process, handle: FileHandle) async throws -> Data {
        let buffer = SynchronizedDataBuffer()
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty { buffer.append(data) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                handle.readabilityHandler = nil
                buffer.append(handle.readDataToEndOfFile())
                continuation.resume(returning: buffer.data)
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private actor VersionCache {
    static let shared = VersionCache()

    private var values: [String: String?] = [:]

    func value(for key: String) -> String? {
        values[key] ?? nil
    }

    func store(_ value: String?, for key: String) {
        values[key] = value
    }
}

private final class SynchronizedDataBuffer {
    private let lock = NSLock()
    private var storage = Data()
    private let maxBytes = 200_000

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        if storage.count > maxBytes {
            storage = storage.suffix(maxBytes)
        }
        lock.unlock()
    }
}

final class ProcessProgressEmissionGate {
    private let minimumInterval: TimeInterval
    private let lock = NSLock()
    private var lastEmissionTime: TimeInterval?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    func shouldEmit(now: TimeInterval = ProcessInfo.processInfo.systemUptime, force: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if force || lastEmissionTime == nil || now - (lastEmissionTime ?? 0) >= minimumInterval {
            lastEmissionTime = now
            return true
        }
        return false
    }
}
