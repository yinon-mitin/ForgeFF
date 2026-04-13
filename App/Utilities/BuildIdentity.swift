import Foundation

enum BuildIdentity {
    private static let gitHashKey = "ForgeFFBuildGitHash"
    private static let timestampKey = "ForgeFFBuildTimestamp"

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    static var shortGitHash: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: gitHashKey) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "UNKNOWN" ? nil : trimmed
    }

    static var buildTimestamp: String? {
        if let executableTimestamp = formattedTimestamp(
            for: Bundle.main.executableURL ?? Bundle.main.bundleURL as URL?
        ) {
            return executableTimestamp
        }

        if let explicit = Bundle.main.object(forInfoDictionaryKey: timestampKey) as? String {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func formattedTimestamp(for url: URL?) -> String? {
        guard let url,
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}
