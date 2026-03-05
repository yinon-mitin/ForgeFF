import Foundation

enum FilenameRenamer {
    static func preview(
        for jobs: [VideoJob],
        configuration: BatchRenameConfiguration
    ) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: jobs.map { job in
            let base = job.sourceURL.deletingPathExtension().lastPathComponent
            return (job.id, apply(to: base, configuration: configuration))
        })
    }

    static func apply(
        to baseName: String,
        configuration: BatchRenameConfiguration
    ) -> String {
        var result = baseName

        if !configuration.replaceText.isEmpty {
            result = result.replacingOccurrences(of: configuration.replaceText, with: configuration.replaceWith)
        }

        if configuration.sanitizeFilename {
            result = sanitize(result)
        }

        result = configuration.prefix + result + configuration.suffix
        return result.isEmpty ? "output" : result
    }

    static func sanitize(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = text.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_")
        return joined.replacingOccurrences(of: " ", with: "_")
    }
}
