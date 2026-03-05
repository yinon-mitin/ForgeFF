import Foundation

struct FFmpegEncoderCapabilities: Equatable {
    var supportsX264: Bool
    var supportsX265: Bool
    var supportsVP9: Bool
    var supportsSVTAV1: Bool
    var supportsAOMAV1: Bool

    var supportsAV1: Bool { supportsSVTAV1 || supportsAOMAV1 }
    var missingModernVideoEncoders: Bool { !supportsVP9 || !supportsAV1 }

    static let none = FFmpegEncoderCapabilities(
        supportsX264: false,
        supportsX265: false,
        supportsVP9: false,
        supportsSVTAV1: false,
        supportsAOMAV1: false
    )
}

enum FFmpegEncoderDiscovery {
    static func parseEncodersOutput(_ output: String) -> FFmpegEncoderCapabilities {
        let normalized = output.lowercased()
        return FFmpegEncoderCapabilities(
            supportsX264: normalized.contains("libx264"),
            supportsX265: normalized.contains("libx265"),
            supportsVP9: normalized.contains("libvpx-vp9"),
            supportsSVTAV1: normalized.contains("libsvtav1"),
            supportsAOMAV1: normalized.contains("libaom-av1")
        )
    }

    static func detectCapabilities(ffmpegURL: URL?) -> FFmpegEncoderCapabilities {
        guard let ffmpegURL else { return .none }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-hide_banner", "-encoders"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .none
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseEncodersOutput(output + "\n" + stderr)
    }
}
