import AppKit
import SwiftUI

struct AboutForgeFFView: View {
    private var appIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .center, spacing: 6) {
                Text("ForgeFF")
                    .font(.title2.weight(.semibold))

                Text("Version \(BuildIdentity.versionString) (build \(BuildIdentity.buildString))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let buildDetails = buildDetailsLine {
                    Text(buildDetails)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("A presets-first FFmpeg wrapper for batch media conversion on macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Link("Repository", destination: repositoryURL)
                Link("Author", destination: authorURL)
            }
            .font(.callout)
        }
        .padding(28)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 280, alignment: .top)
    }

    private var buildDetailsLine: String? {
        var components = [String]()
        if let hash = BuildIdentity.shortGitHash {
            components.append("Git \(hash)")
        }
        if let timestamp = BuildIdentity.buildTimestamp {
            components.append(timestamp)
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/yinon-mitin/ForgeFF")!
    }

    private var authorURL: URL {
        URL(string: "https://github.com/yinon-mitin")!
    }
}
