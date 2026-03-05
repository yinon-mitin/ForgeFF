import AppKit
import SwiftUI

struct AboutForgeFFView: View {
    private var appIcon: NSImage {
        NSApp.applicationIconImage
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        VStack {
            Spacer(minLength: 8)
            VStack(alignment: .center, spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("ForgeFF")
                    .font(.title2.weight(.semibold))

                Text("Version \(versionString) (build \(buildString))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("A presets-first FFmpeg wrapper for batch media conversion on macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                VStack(spacing: 6) {
                    Link("Repository", destination: URL(string: "https://github.com/yinon-mitin/ForgeFF")!)
                    Link("Author: Yinon Mitin", destination: URL(string: "https://github.com/yinon-mitin")!)
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
