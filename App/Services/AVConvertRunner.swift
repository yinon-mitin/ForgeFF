import Darwin
import Foundation

enum AVConvertRunnerError: LocalizedError {
    case unavailable
    case processFailed(summary: String, details: String, commandLine: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple HDR to SDR conversion is not available on this Mac."
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

struct AVConvertCommandInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
    let commandLine: String
}

enum AVConvertPreset: String {
    case preset640x480 = "Preset640x480"
    case preset960x540 = "Preset960x540"
    case preset1280x720 = "Preset1280x720"
    case preset1920x1080 = "Preset1920x1080"
    case preset3840x2160 = "Preset3840x2160"
    case presetHighestQuality = "PresetHighestQuality"

    static func bestMatch(for metadata: MediaMetadata?) -> AVConvertPreset {
        guard let stream = metadata?.videoStream,
              let width = stream.width,
              let height = stream.height else {
            return .presetHighestQuality
        }

        let longEdge = max(width, height)
        let shortEdge = min(width, height)

        if longEdge <= 640, shortEdge <= 480 {
            return .preset640x480
        }
        if longEdge <= 960, shortEdge <= 540 {
            return .preset960x540
        }
        if longEdge <= 1280, shortEdge <= 720 {
            return .preset1280x720
        }
        if longEdge <= 1920, shortEdge <= 1080 {
            return .preset1920x1080
        }
        if longEdge <= 3840, shortEdge <= 2160 {
            return .preset3840x2160
        }

        return .presetHighestQuality
    }
}

final class AVConvertRunner {
    private var currentProcess: Process?
    private var isCancelled = false

    func buildInvocation(
        sourceURL: URL,
        outputURL: URL,
        preset: AVConvertPreset,
        replaceExisting: Bool,
        executableURL: URL? = AVConvertDiscovery.defaultExecutableURL
    ) throws -> AVConvertCommandInvocation {
        guard let executableURL else {
            throw AVConvertRunnerError.unavailable
        }

        var arguments = [
            "--source", sourceURL.path,
            "--preset", preset.rawValue,
            "--output", outputURL.path,
            "--disableFastStart",
            "--progress",
            "--verbose"
        ]

        if replaceExisting {
            arguments.append("--replace")
        }

        return AVConvertCommandInvocation(
            executableURL: executableURL,
            arguments: arguments,
            commandLine: FFmpegCommandBuilder.commandLine(executableURL: executableURL, arguments: arguments)
        )
    }

    func run(
        invocation: AVConvertCommandInvocation,
        progress: @MainActor @escaping (Double?) -> Void
    ) async throws -> String {
        isCancelled = false

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        currentProcess = process

        let accumulatedOutput = SynchronizedProcessBuffer()
        let progressGate = ProcessProgressEmissionGate(minimumInterval: 0.1)
        let handle = outputPipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            accumulatedOutput.append(data)

            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                guard let ratio = Self.parseProgress(line: String(line)) else { continue }
                guard progressGate.shouldEmit(force: ratio >= 1) else { continue }
                Task { @MainActor in
                    progress(ratio)
                }
            }
        }

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] process in
                handle.readabilityHandler = nil
                self?.currentProcess = nil

                if self?.isCancelled == true {
                    continuation.resume(throwing: AVConvertRunnerError.cancelled)
                    return
                }

                let output = String(data: accumulatedOutput.data, encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: AVConvertRunnerError.processFailed(
                            summary: Self.errorSummary(from: output),
                            details: output,
                            commandLine: invocation.commandLine
                        )
                    )
                    return
                }

                continuation.resume(returning: output)
            }
        }
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

    private static func parseProgress(line: String) -> Double? {
        if let percentValue = firstCapturedDouble(
            in: line,
            pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#
        ) {
            return min(max(percentValue / 100, 0), 1)
        }

        guard let numericValue = firstCapturedDouble(
            in: line,
            pattern: #"progress[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ) else {
            return nil
        }

        if numericValue <= 1 {
            return min(max(numericValue, 0), 1)
        }

        return min(max(numericValue / 100, 0), 1)
    }

    private static func firstCapturedDouble(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    private static func errorSummary(from output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let specific = lines.reversed().first(where: { $0.localizedCaseInsensitiveContains("error") }) {
            return "Apple HDR to SDR conversion failed: \(specific)"
        }

        return "Apple HDR to SDR conversion failed."
    }
}

private final class SynchronizedProcessBuffer {
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
