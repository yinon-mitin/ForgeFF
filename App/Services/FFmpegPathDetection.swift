import Foundation

struct FFmpegPathDetectionResult: Equatable {
    var ffmpegPath: String?
    var ffprobePath: String?
    var hints: [String]

    var isConfigured: Bool {
        ffmpegPath != nil && ffprobePath != nil
    }
}

struct FFmpegPathDetector {
    var isExecutable: (String) -> Bool
    var commandLookup: (String) -> String?
    var pathExists: (String) -> Bool

    init(
        isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        commandLookup: @escaping (String) -> String? = FFmpegPathDetector.lookupInSystemPath,
        pathExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.isExecutable = isExecutable
        self.commandLookup = commandLookup
        self.pathExists = pathExists
    }

    func detect(currentFFmpegPath: String, currentFFprobePath: String) -> FFmpegPathDetectionResult {
        let ffmpeg = resolveBinary(
            currentValue: currentFFmpegPath,
            candidates: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ],
            lookupName: "ffmpeg"
        )

        let ffprobe = resolveBinary(
            currentValue: currentFFprobePath,
            candidates: [
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
                "/usr/bin/ffprobe"
            ],
            lookupName: "ffprobe"
        )

        var hints: [String] = []
        if pathExists("/opt/homebrew/bin/brew") || pathExists("/opt/homebrew/bin") {
            if ffmpeg == nil || ffprobe == nil {
                hints.append("Homebrew was detected at /opt/homebrew, but FFmpeg tools are incomplete.")
            }
        }
        if pathExists("/usr/local/bin/brew") || pathExists("/usr/local/bin") {
            if ffmpeg == nil || ffprobe == nil {
                hints.append("Intel Homebrew paths were checked at /usr/local/bin.")
            }
        }
        if ffmpeg == nil && ffprobe == nil {
            hints.append("Install with Homebrew, then relaunch ForgeFF.")
        }

        return FFmpegPathDetectionResult(ffmpegPath: ffmpeg, ffprobePath: ffprobe, hints: hints)
    }

    static func shouldShowOnboarding(ffmpegPath: String, ffprobePath: String) -> Bool {
        guard URL.validExecutablePath(ffmpegPath) != nil else { return true }
        guard URL.validExecutablePath(ffprobePath) != nil else { return true }
        return false
    }

    private func resolveBinary(currentValue: String, candidates: [String], lookupName: String) -> String? {
        if isExecutable(currentValue) {
            return currentValue
        }

        for candidate in candidates where isExecutable(candidate) {
            return candidate
        }

        if let discovered = commandLookup(lookupName), isExecutable(discovered) {
            return discovered
        }

        return nil
    }

    private static func lookupInSystemPath(command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let resolved = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let resolved, !resolved.isEmpty else { return nil }
            return resolved
        } catch {
            return nil
        }
    }
}
