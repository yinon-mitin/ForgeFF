import Foundation

enum FilenameRenamer {
    enum FieldKind {
        case filenameComponent
        case searchPattern
    }

    static let maxBaseNameLength = 200

    static func preview(
        for jobs: [VideoJob],
        configuration: BatchRenameConfiguration
    ) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: jobs.map { job in
            let base = job.sourceURL.deletingPathExtension().lastPathComponent
            return (job.id, apply(to: base, configuration: configuration, originalFallback: base))
        })
    }

    static func apply(
        to baseName: String,
        configuration: BatchRenameConfiguration,
        originalFallback: String? = nil
    ) -> String {
        let effectiveConfiguration = normalizedConfiguration(
            configuration,
            sanitizeFields: configuration.sanitizeFilename
        )
        var result = baseName

        if !effectiveConfiguration.replaceText.isEmpty {
            result = result.replacingOccurrences(of: effectiveConfiguration.replaceText, with: effectiveConfiguration.replaceWith)
        }

        if effectiveConfiguration.sanitizeFilename {
            result = sanitize(result)
        } else {
            result = sanitizePathUnsafeText(result)
        }

        result = effectiveConfiguration.prefix + result + effectiveConfiguration.suffix
        if effectiveConfiguration.sanitizeFilename {
            result = sanitize(result)
        } else {
            result = sanitizePathUnsafeText(result)
        }
        result = truncateBaseName(result)

        if result.isEmpty {
            if let originalFallback, !originalFallback.isEmpty {
                return truncateBaseName(sanitizePathUnsafeText(originalFallback))
            }
            return "output"
        }

        return result
    }

    static func normalizedConfiguration(
        _ configuration: BatchRenameConfiguration,
        sanitizeFields: Bool
    ) -> BatchRenameConfiguration {
        var normalized = configuration
        normalized.prefix = normalizeInputField(configuration.prefix, sanitize: sanitizeFields, fieldKind: .filenameComponent)
        normalized.suffix = normalizeInputField(configuration.suffix, sanitize: sanitizeFields, fieldKind: .filenameComponent)
        normalized.replaceText = normalizeInputField(configuration.replaceText, sanitize: sanitizeFields, fieldKind: .searchPattern)
        normalized.replaceWith = normalizeInputField(configuration.replaceWith, sanitize: sanitizeFields, fieldKind: .filenameComponent)
        return normalized
    }

    static func normalizeInputField(
        _ value: String,
        sanitize shouldSanitize: Bool,
        fieldKind: FieldKind
    ) -> String {
        if shouldSanitize {
            switch fieldKind {
            case .filenameComponent:
                return truncateBaseName(sanitizeForFilenameComponent(value))
            case .searchPattern:
                return truncateBaseName(sanitizeForSearchPattern(value))
            }
        }
        switch fieldKind {
        case .filenameComponent:
            return truncateBaseName(sanitizePathUnsafeText(value))
        case .searchPattern:
            return truncateBaseName(sanitizeForSearchPattern(value))
        }
    }

    static func sanitizeForFilenameComponent(_ text: String) -> String {
        sanitize(text)
    }

    static func sanitizeForSearchPattern(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let parts = text.components(separatedBy: invalid)
        let joined = parts.joined()
        let withoutTraversal = joined.replacingOccurrences(of: "..", with: "")
        return String(withoutTraversal.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }

    static func sanitize(_ text: String) -> String {
        let whitespaceCollapsed = text.replacingOccurrences(
            of: "\\s+",
            with: "_",
            options: .regularExpression
        )
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = whitespaceCollapsed.components(separatedBy: invalid)
        let joined = parts.joined(separator: "_")
        let withoutTraversal = joined.replacingOccurrences(of: "..", with: "")
        let withoutControls = String(withoutTraversal.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return collapseUnderscores(in: withoutControls).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func sanitizePathUnsafeText(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let parts = text.components(separatedBy: invalid)
        let joined = parts.joined()
        let withoutTraversal = joined.replacingOccurrences(of: "..", with: "")
        let withoutControls = String(withoutTraversal.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseUnderscores(in text: String) -> String {
        text.replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
    }

    static func truncateBaseName(_ text: String) -> String {
        if text.count <= maxBaseNameLength {
            return text
        }
        return String(text.prefix(maxBaseNameLength))
    }
}
