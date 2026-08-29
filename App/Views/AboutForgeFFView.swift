import AppKit
import SwiftUI

struct AboutForgeFFOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            AboutForgeFFView(onClose: onClose)
                .padding(32)
                .onTapGesture { }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About ForgeFF")
    }
}

struct AboutForgeFFView: View {
    let onClose: () -> Void
    @EnvironmentObject private var updateService: AppUpdateService

    private var appIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close About")
                .accessibilityLabel("Close About")
            }

            HStack(alignment: .top, spacing: 22) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 7) {
                    Text("ForgeFF")
                        .font(.largeTitle.weight(.bold))

                    Text("Simple and powerful video conversion for macOS.")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Version \(BuildIdentity.versionString) (build \(BuildIdentity.buildString))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let buildDetails = buildDetailsLine {
                        Text(buildDetails)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created by Yinon Mitin")
                        .font(.callout.weight(.semibold))
                    Text("Open-source macOS utility built around FFmpeg.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("GitHub", destination: authorURL)
            }

            HStack(spacing: 12) {
                Link("View Repository", destination: repositoryURL)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("Made for fast, dependable batch conversion.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            updateControls
        }
        .padding(24)
        .frame(width: 520, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 34, y: 18)
    }

    @ViewBuilder
    private var updateControls: some View {
        HStack(spacing: 10) {
            switch updateService.state {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Checking GitHub for updates…")
            case let .available(release):
                Text("Version \(release.version) is available")
                Spacer()
                Button("Update Now") {
                    Task { await updateService.downloadAndInstall() }
                }
            case .downloading:
                ProgressView()
                    .controlSize(.small)
                Text("Downloading and verifying update…")
            case .ready:
                Text("Update installed. Restarting ForgeFF…")
            case .upToDate:
                Text("ForgeFF is up to date.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check Again") {
                    Task { await updateService.checkForUpdates() }
                }
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try Again") {
                    Task { await updateService.checkForUpdates() }
                }
            default:
                Text("ForgeFF checks GitHub Releases for checksum-verified updates.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") {
                    Task { await updateService.checkForUpdates() }
                }
            }
        }
        .font(.caption)
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
