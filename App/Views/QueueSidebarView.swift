import AppKit
import SwiftUI

struct QueueListView: View {
    @EnvironmentObject private var queueStore: JobQueueStore

    @ObservedObject var viewModel: QueueViewModel
    @Binding var isDropTargeted: Bool
    let onAddFiles: () -> Void
    let onAddFolder: () -> Void

    @State private var isEmptyChoicePopoverPresented = false
    @State private var expandedDetailJobIDs = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            if queueStore.jobs.isEmpty {
                emptyState
            } else {
                List(selection: selectionBinding) {
                    ForEach(queueStore.jobs) { job in
                        QueueRowView(
                            job: job,
                            isSelected: viewModel.selectedJobIDs.contains(job.id),
                            isDetailsExpanded: Binding(
                                get: { expandedDetailJobIDs.contains(job.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedDetailJobIDs.insert(job.id)
                                    } else {
                                        expandedDetailJobIDs.remove(job.id)
                                    }
                                }
                            ),
                            onReveal: { queueStore.revealOutput(for: job.id) },
                            onRetry: {
                                queueStore.retry(jobID: job.id)
                                viewModel.refreshDraftOptions()
                            },
                            onRemove: {
                                let idsToRemove: Set<UUID>
                                if !viewModel.selectedJobIDs.isEmpty, viewModel.selectedJobIDs.contains(job.id) {
                                    idsToRemove = viewModel.selectedJobIDs
                                } else {
                                    idsToRemove = [job.id]
                                    viewModel.selectedJobIDs = [job.id]
                                }
                                queueStore.remove(jobIDs: idsToRemove)
                                viewModel.selectedJobIDs.subtract(idsToRemove)
                                viewModel.refreshDraftOptions()
                            },
                            onCancel: { queueStore.cancel(jobID: job.id) }
                        )
                        .tag(job.id)
                    }
                    .onMove(perform: queueStore.move)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onChange(of: viewModel.selectedJobIDs) { ids in
            if let first = ids.first {
                queueStore.selectedJobID = first
            }
            viewModel.refreshDraftOptions()
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { viewModel.selectedJobIDs },
            set: { viewModel.selectedJobIDs = $0 }
        )
    }

    private var emptyState: some View {
        ZStack {
            Button {
                isEmptyChoicePopoverPresented = true
            } label: {
                Rectangle()
                    .fill(Color.clear)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isEmptyChoicePopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Add Files…", action: onAddFiles)
                    Button("Add Folder…", action: onAddFolder)
                }
                .padding(14)
                .frame(minWidth: 180)
            }

            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Drop files here")
                    .font(.title3.weight(.semibold))
                Text("Or add files and folders to start a batch.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Menu("Add…") {
                    Button("Add Files…", action: onAddFiles)
                    Button("Add Folder…", action: onAddFolder)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QueueRowView: View {
    let job: VideoJob
    let isSelected: Bool
    @Binding var isDetailsExpanded: Bool
    let onReveal: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.sourceDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let metadata = job.metadata {
                    Text(metadata.isHDR ? "HDR" : "SDR")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(metadata.isHDR ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                if job.status == .failed {
                    Text("Failed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Text(job.status.rawValue.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }
            }

            ProgressView(value: job.progress)
                .opacity(job.status == .completed ? 0.35 : 1)

            HStack(spacing: 10) {
                Text("Input \(FileSizeFormatterUtil.string(from: job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let outputSize = job.result?.outputFileSize {
                    Text(outputSummary(outputSize: outputSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let eta = job.estimatedRemainingSeconds {
                    Text("ETA \(etaString(eta))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let message = job.errorSummary, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if job.status == .running {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.link)
                        .focusable(false)
                }

                if job.status == .completed {
                    Button("Reveal", action: onReveal)
                        .buttonStyle(.link)
                        .focusable(false)
                }

                if job.status == .failed || job.status == .cancelled {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.link)
                        .focusable(false)
                }

                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.link)
                    .focusable(false)
            }

            if job.status == .failed || job.status == .cancelled {
                DisclosureGroup("Details", isExpanded: $isDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let details = job.errorLog, !details.isEmpty {
                            ScrollView(.vertical) {
                                Text(details)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        } else {
                            Text("No details available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let commandLine = job.commandLine, !commandLine.isEmpty {
                            ScrollView(.horizontal) {
                                Text(commandLine)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 48)
                        }

                        HStack(spacing: 10) {
                            if let details = job.errorLog, !details.isEmpty {
                                Button("Copy error") {
                                    copyToPasteboard(details)
                                }
                                .buttonStyle(.link)
                            }
                            if let commandLine = job.commandLine, !commandLine.isEmpty {
                                Button("Copy command") {
                                    copyToPasteboard(commandLine)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        .contextMenu {
            if job.status == .completed {
                Button("Reveal in Finder", action: onReveal)
            }
            if job.status == .failed || job.status == .cancelled {
                Button("Retry", action: onRetry)
            }
            if job.status == .running {
                Button("Cancel", action: onCancel)
            }
            Button("Remove", action: onRemove)
        }
    }

    private var secondaryLine: String {
        [
            durationText,
            resolutionText,
            codecSummary
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var durationText: String {
        guard let value = job.metadata?.durationSeconds else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: value) ?? ""
    }

    private var resolutionText: String {
        guard let stream = job.metadata?.videoStream,
              let width = stream.width,
              let height = stream.height else {
            return job.options.isAudioOnly ? "Audio only" : ""
        }
        return "\(width)x\(height)"
    }

    private var codecSummary: String {
        if job.options.isAudioOnly {
            return job.metadata?.audioStreams.first?.codecName?.uppercased() ?? job.options.audioCodec.displayName
        }

        let video = job.metadata?.videoStream?.codecName?.uppercased() ?? job.options.videoCodec.displayName
        let audio = job.metadata?.audioStreams.first?.codecName?.uppercased() ?? job.options.audioCodec.displayName
        return "\(video) + \(audio)"
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .running: return .blue
        case .paused: return .orange
        default: return .secondary
        }
    }

    private func etaString(_ eta: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: eta) ?? "n/a"
    }

    private func outputSummary(outputSize: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let renderedOutput = formatter.string(fromByteCount: outputSize)
        guard let sourceSize = job.metadata?.fileSizeBytes else {
            return renderedOutput
        }

        let delta = outputSize - sourceSize
        let renderedDelta = formatter.string(fromByteCount: abs(delta))
        let sign = delta <= 0 ? "-" : "+"
        return "\(renderedOutput) (\(sign)\(renderedDelta))"
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
