import Foundation

enum FileSizeFormatterUtil {
    static func string(from byteCount: Int64?) -> String {
        guard let byteCount else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    static func outputSummary(outputBytes: Int64, sourceBytes: Int64?) -> String {
        let renderedOutput = string(from: outputBytes)
        guard let sourceBytes, sourceBytes > 0 else {
            return "Output: \(renderedOutput)"
        }
        let delta = outputBytes - sourceBytes
        let renderedDelta = string(from: abs(delta))
        let sign = delta <= 0 ? "-" : "+"
        return "Output: \(renderedOutput) (\(sign)\(renderedDelta))"
    }
}
