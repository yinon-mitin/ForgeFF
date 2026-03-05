import Foundation

enum FileSizeFormatterUtil {
    static func string(from byteCount: Int64?) -> String {
        guard let byteCount else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}
