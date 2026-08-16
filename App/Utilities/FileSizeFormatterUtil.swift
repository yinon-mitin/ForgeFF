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
        let relativePercent = (Double(outputBytes) / Double(sourceBytes)) * 100
        return "Output: \(renderedOutput) (\(relativePercentString(relativePercent)) of input)"
    }

    private static func relativePercentString(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
