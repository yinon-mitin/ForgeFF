import Foundation

enum OutputTemplateRenderer {
    static func render(template: String, job: VideoJob) -> String {
        let metadata = job.metadata
        let resolutionToken: String = {
            if let dimensions = job.options.resolutionOverride.dimensions {
                return "\(dimensions.0)x\(dimensions.1)"
            }
            if let width = metadata?.videoStream?.width, let height = metadata?.videoStream?.height {
                return "\(width)x\(height)"
            }
            return "source"
        }()

        let replacements: [String: String] = [
            "{name}": job.sourceURL.deletingPathExtension().lastPathComponent,
            "{preset}": FilenameRenamer.sanitize(job.options.presetName.lowercased().replacingOccurrences(of: " ", with: "_")),
            "{resolution}": resolutionToken,
            "{codec}": job.options.videoCodec.rawValue
        ]

        var rendered = template.isEmpty ? "{name}_{preset}" : template
        for (token, value) in replacements {
            rendered = rendered.replacingOccurrences(of: token, with: value)
        }
        return FilenameRenamer.sanitize(rendered)
    }
}
