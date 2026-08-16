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

struct FFmpegFilterCapabilities: Equatable {
    var hasScanned: Bool
    var supportsLibplacebo: Bool
    var supportsZscale: Bool
    var supportsTonemap: Bool
    var supportsColorspace: Bool
    var supportsFormat: Bool
    var supportsEq: Bool

    var supportsZscaleToneMapping: Bool {
        supportsZscale && supportsTonemap
    }

    var supportsToneMapping: Bool {
        supportsLibplacebo || supportsZscaleToneMapping
    }

    static let unknown = FFmpegFilterCapabilities(
        hasScanned: false,
        supportsLibplacebo: false,
        supportsZscale: false,
        supportsTonemap: false,
        supportsColorspace: false,
        supportsFormat: false,
        supportsEq: false
    )

    static let none = FFmpegFilterCapabilities(
        hasScanned: true,
        supportsLibplacebo: false,
        supportsZscale: false,
        supportsTonemap: false,
        supportsColorspace: false,
        supportsFormat: false,
        supportsEq: false
    )

    static let fullySupported = FFmpegFilterCapabilities(
        hasScanned: true,
        supportsLibplacebo: true,
        supportsZscale: true,
        supportsTonemap: true,
        supportsColorspace: true,
        supportsFormat: true,
        supportsEq: true
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

enum FFmpegFilterDiscovery {
    static func parseFiltersOutput(_ output: String) -> FFmpegFilterCapabilities {
        let filterNames = parsedFilterNames(from: output)
        return FFmpegFilterCapabilities(
            hasScanned: true,
            supportsLibplacebo: filterNames.contains("libplacebo"),
            supportsZscale: filterNames.contains("zscale"),
            supportsTonemap: filterNames.contains("tonemap"),
            supportsColorspace: filterNames.contains("colorspace"),
            supportsFormat: filterNames.contains("format"),
            supportsEq: filterNames.contains("eq")
        )
    }

    static func detectCapabilities(ffmpegURL: URL?) -> FFmpegFilterCapabilities {
        guard let ffmpegURL else { return .none }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-hide_banner", "-filters"]

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
        return parseFiltersOutput(output + "\n" + stderr)
    }

    private static func parsedFilterNames(from output: String) -> Set<String> {
        Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard columns.count >= 2 else { return nil }
                    let candidate = columns[1].lowercased()
                    guard candidate.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil else {
                        return nil
                    }
                    return candidate
                }
        )
    }
}
