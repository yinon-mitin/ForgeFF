import AVFoundation
import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct QueueListView: View {
    @EnvironmentObject private var queueStore: JobQueueStore

    @ObservedObject var viewModel: QueueViewModel
    @Binding var isDropTargeted: Bool
    let onAddFiles: () -> Void
    let onAddFolder: () -> Void

    @State private var isEmptyChoicePopoverPresented = false
    @State private var selectedFilter: QueueFilter = .all
    @State private var expandedFailureGroupKeys = Set<String>()
    @StateObject private var thumbnailStore = QueueThumbnailStore()
    @StateObject private var rowPresentationState = QueueRowPresentationState()

    var body: some View {
        VStack(spacing: 0) {
            if queueStore.jobs.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar

                    if !failureGroups.isEmpty {
                        failureGroupsSummary
                    }

                    List(selection: selectionBinding) {
                        ForEach(filteredJobs) { job in
                            QueueRowView(
                                job: job,
                                displayStatus: queueStore.displayStatus(for: job),
                                previewURL: job.previewURL,
                                thumbnail: thumbnailStore.image(for: job.previewURL),
                                isSelected: viewModel.selectedJobIDs.contains(job.id),
                                isDetailsExpanded: Binding(
                                    get: { rowPresentationState.isDetailsExpanded(for: job.id) },
                                    set: { rowPresentationState.setDetailsExpanded($0, for: job.id) }
                                ),
                                onReveal: { queueStore.revealOutput(for: job.id) },
                                onOpenOutput: {
                                    selectJob(job.id)
                                    queueStore.openCompletedOutput(for: job.id)
                                },
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
                                onCancel: { queueStore.cancel(jobID: job.id) },
                                onOpenSource: { queueStore.openSource(for: job.id) },
                                onOpenOutputFolder: { queueStore.openOutputFolder(for: job.id) }
                            )
                            .id(job.id)
                            .tag(job.id)
                            .onAppear {
                                thumbnailStore.loadThumbnail(for: job.previewURL)
                            }
                            .onChange(of: job.previewURL) { previewURL in
                                thumbnailStore.loadThumbnail(for: previewURL, forceReload: true)
                            }
                            .onChange(of: job.completedAt) { _ in
                                guard job.status == .completed else { return }
                                thumbnailStore.loadThumbnail(for: job.previewURL, forceReload: true)
                            }
                        }
                        .onMove(perform: queueStore.move)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .onChange(of: viewModel.selectedJobIDs) { ids in
            queueStore.selectedJobID = ids.first
            viewModel.refreshDraftOptions()
        }
        .onChange(of: queueStore.jobs.map(\.id)) { ids in
            let idSet = Set(ids)
            let intersection = viewModel.selectedJobIDs.intersection(idSet)
            if intersection != viewModel.selectedJobIDs {
                viewModel.selectedJobIDs = intersection
            }
            rowPresentationState.reconcile(validJobIDs: idSet)
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: { viewModel.selectedJobIDs },
            set: { viewModel.selectedJobIDs = $0 }
        )
    }

    private func selectJob(_ jobID: UUID) {
        viewModel.selectedJobIDs = [jobID]
        queueStore.selectedJobID = jobID
    }

    private var filteredJobs: [VideoJob] {
        queueStore.jobs.filter { selectedFilter.matches(queueStore.displayStatus(for: $0)) }
    }

    private var failureGroups: [QueueFailureGroup] {
        let failedJobs = queueStore.jobs.filter { $0.status == .failed }
        let grouped = Dictionary(grouping: failedJobs) { QueueFailureGroup.normalizedKey(for: $0) }
        return grouped
            .compactMap { key, jobs in
                guard jobs.count > 1 else { return nil }
                return QueueFailureGroup(key: key, jobs: jobs)
            }
            .sorted { lhs, rhs in
                if lhs.jobs.count == rhs.jobs.count {
                    return lhs.title < rhs.title
                }
                return lhs.jobs.count > rhs.jobs.count
            }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QueueFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(selectedFilter == filter ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                Capsule()
                                    .stroke(selectedFilter == filter ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private var failureGroupsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(failureGroups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedFailureGroupKeys.contains(group.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedFailureGroupKeys.insert(group.id)
                            } else {
                                expandedFailureGroupKeys.remove(group.id)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(group.jobs) { job in
                            Text(job.sourceDisplayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("\(group.jobs.count) failed (same reason)")
                        .font(.callout.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.04))
    }

    private var emptyState: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isEmptyChoicePopoverPresented = true
                }
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
                presetCards
                Menu("Add…") {
                    Button("Add Files…", action: onAddFiles)
                    Button("Add Folder…", action: onAddFolder)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var presetCards: some View {
        VStack(spacing: 10) {
            ForEach(recommendedPresetCards, id: \.title) { card in
                Button {
                    viewModel.selectPreset(named: card.presetName)
                    onAddFiles()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.headline)
                        Text(card.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320)
    }

    private var recommendedPresetCards: [(title: String, subtitle: String, presetName: String)] {
        [
            ("Fast MP4 (H.264)", "Quick export for broad playback.", "MP4 — H.264 (Fast)"),
            ("Efficient HEVC", "Smaller modern playback default.", "MP4 — HEVC (Balanced)"),
            ("Editing ProRes", "Large edit-friendly mezzanine output.", "MOV — ProRes 422 (Editing)")
        ]
    }
}

private struct QueueRowView: View {
    let job: VideoJob
    let displayStatus: QueueJobDisplayStatus
    let previewURL: URL
    let thumbnail: NSImage?
    let isSelected: Bool
    @Binding var isDetailsExpanded: Bool
    let onReveal: () -> Void
    let onOpenOutput: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void
    let onOpenSource: () -> Void
    let onOpenOutputFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                thumbnailView

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.sourceDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.formatTransitionSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let dynamicRangeBadgeText {
                    Text(dynamicRangeBadgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(dynamicRangeBadgeBackground)
                        .foregroundStyle(dynamicRangeBadgeForeground)
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                if displayStatus == .failed {
                    Text(displayStatus.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    HStack(spacing: 6) {
                        Text(displayStatus.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusColor)

                        if let progressPercentageText {
                            Text(progressPercentageText)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(statusColor)
                        }
                    }
                }
            }

            ProgressView(value: job.progress)
                .opacity(job.status == .completed ? 0.35 : 1)

            HStack(spacing: 10) {
                Text("Input \(FileSizeFormatterUtil.string(from: job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(sizeSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if job.result?.outputFileSize == nil, let eta = job.estimatedRemainingSeconds {
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

                if displayStatus == .running {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.link)
                }

                if job.status == .completed {
                    Button("Reveal", action: onReveal)
                        .buttonStyle(.link)
                }

                if job.status == .failed || job.status == .cancelled {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.link)
                }

                if job.status == .failed || job.status == .cancelled {
                    Button(isDetailsExpanded ? "Hide Details" : "Details") {
                        isDetailsExpanded.toggle()
                    }
                    .buttonStyle(.link)
                }

                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.link)
            }

            if isDetailsExpanded, job.status == .failed || job.status == .cancelled {
                failureDetailsView
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        .overlay(alignment: .topLeading) {
            QueueRowDoubleClickBridge {
                guard job.status == .completed else { return }
                onOpenOutput()
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .contextMenu {
            if job.status == .completed {
                Button("Reveal in Finder", action: onReveal)
            }
            if job.status == .failed || job.status == .cancelled {
                Button("Retry", action: onRetry)
            }
            if displayStatus == .running {
                Button("Cancel", action: onCancel)
            }
            Button("Remove", action: onRemove)
        }
    }

    private var failureDetailsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.errorSummary ?? "Conversion failed.")
                .font(.caption.weight(.semibold))

            if let ffmpegVersion = job.ffmpegVersion, !ffmpegVersion.isEmpty {
                Text(ffmpegVersion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Executed command")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Text(commandLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 48)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if let details = job.errorLog, !details.isEmpty {
                        Button("Copy Error Log") {
                            copyToPasteboard(details)
                        }
                        .buttonStyle(.link)
                    }
                    if let commandLine = job.commandLine, !commandLine.isEmpty {
                        Button("Copy Command") {
                            copyToPasteboard(commandLine)
                        }
                        .buttonStyle(.link)
                    }
                    if let ffmpegVersion = job.ffmpegVersion, !ffmpegVersion.isEmpty {
                        Button("Copy FFmpeg Version") {
                            copyToPasteboard(ffmpegVersion)
                        }
                        .buttonStyle(.link)
                    }
                }

                HStack(spacing: 10) {
                    Button("Open Source", action: onOpenSource)
                        .buttonStyle(.link)

                    if job.result?.outputURL != nil {
                        Button("Reveal Output", action: onReveal)
                            .buttonStyle(.link)
                        Button("Open Output Folder", action: onOpenOutputFolder)
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }

    private var secondaryLine: String {
        [
            durationText,
            resolutionText,
            dynamicRangeSummary.isEmpty ? codecSummary : dynamicRangeSummary
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var dynamicRangeBadgeText: String? {
        guard let metadata = job.metadata else { return nil }
        if metadata.isHDR {
            return job.options.enableHDRToSDR ? "HDR → SDR" : "HDR"
        }
        return "SDR"
    }

    private var dynamicRangeSummary: String {
        guard let metadata = job.metadata, metadata.isHDR else { return "" }
        return job.options.enableHDRToSDR
            ? "\(metadata.dynamicRangeDescription) → SDR"
            : metadata.dynamicRangeDescription
    }

    private var dynamicRangeBadgeBackground: Color {
        guard let metadata = job.metadata, metadata.isHDR else {
            return Color.secondary.opacity(0.12)
        }
        return Color.orange.opacity(job.options.enableHDRToSDR ? 0.22 : 0.15)
    }

    private var dynamicRangeBadgeForeground: Color {
        guard let metadata = job.metadata, metadata.isHDR else {
            return .secondary
        }
        return .orange
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
        switch displayStatus {
        case .completed:
            return .green
        case .failed, .cancelled:
            return .red
        case .running:
            return .blue
        case .paused:
            return .orange
        default:
            return .secondary
        }
    }

    private var progressPercentageText: String? {
        switch displayStatus {
        case .running, .paused, .completed:
            let clampedProgress = max(0, min(job.progress, 1))
            let percentage = Int((clampedProgress * 100).rounded())
            guard percentage > 0 || displayStatus == .completed else { return nil }
            return "\(percentage)%"
        default:
            return nil
        }
    }

    private func etaString(_ eta: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: eta) ?? "n/a"
    }

    private var sizeSummaryText: String {
        if let outputSize = job.result?.outputFileSize {
            return outputSummary(outputSize: outputSize)
        }
        if job.status == .completed {
            return "Output: —"
        }
        return estimatedOutputSummary
    }

    private func outputSummary(outputSize: Int64) -> String {
        FileSizeFormatterUtil.outputSummary(
            outputBytes: outputSize,
            sourceBytes: job.inputFileSizeBytes ?? job.metadata?.fileSizeBytes
        )
    }

    private var estimatedOutputSummary: String {
        guard let estimated = job.estimatedOutputSizeBytes else {
            return "Est. output: —"
        }

        var value = "Est. output: ~\(FileSizeFormatterUtil.string(from: estimated))"
        if let delta = job.estimatedOutputDeltaPercent {
            value += String(format: " (~%+.0f%%)", delta)
        }
        return value
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private var thumbnailView: some View {
        let image = thumbnail ?? QueueThumbnailStore.placeholderImage(for: previewURL)
        return Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

private enum QueueFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    func matches(_ status: QueueJobDisplayStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return status == .running || status == .paused || status == .analyzing || status == .inQueue
        case .completed:
            return status == .completed
        case .failed:
            return status == .failed || status == .cancelled
        }
    }
}

@MainActor
final class QueueRowPresentationState: ObservableObject {
    @Published private(set) var expandedDetailJobIDs = Set<UUID>()

    func isDetailsExpanded(for jobID: UUID) -> Bool {
        expandedDetailJobIDs.contains(jobID)
    }

    func setDetailsExpanded(_ isExpanded: Bool, for jobID: UUID) {
        if isExpanded {
            expandedDetailJobIDs.insert(jobID)
        } else {
            expandedDetailJobIDs.remove(jobID)
        }
    }

    func toggleDetails(for jobID: UUID) {
        setDetailsExpanded(!isDetailsExpanded(for: jobID), for: jobID)
    }

    func reconcile(validJobIDs: Set<UUID>) {
        expandedDetailJobIDs.formIntersection(validJobIDs)
    }
}

private struct QueueFailureGroup: Identifiable {
    let key: String
    let jobs: [VideoJob]

    var id: String { key }

    var title: String {
        jobs.first?.errorSummary ?? "Unknown error"
    }

    static func normalizedKey(for job: VideoJob) -> String {
        let source = (job.errorSummary ?? job.errorLog ?? "unknown error").lowercased()
        let withoutPaths = source.replacingOccurrences(
            of: "/[^\\s]+",
            with: "<path>",
            options: .regularExpression
        )
        let withoutNumbers = withoutPaths.replacingOccurrences(
            of: "\\b\\d+\\b",
            with: "#",
            options: .regularExpression
        )
        return withoutNumbers.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QueueRowDoubleClickBridge: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDoubleClick = onDoubleClick
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var onDoubleClick: () -> Void

        private weak var hostView: NSView?
        private lazy var recognizer: NSClickGestureRecognizer = {
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
            recognizer.numberOfClicksRequired = 2
            recognizer.buttonMask = 0x1
            recognizer.delaysPrimaryMouseButtonEvents = false
            recognizer.delegate = self
            return recognizer
        }()

        init(onDoubleClick: @escaping () -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        func attachIfNeeded(from markerView: NSView) {
            guard let resolvedHostView = resolveHostView(from: markerView) else { return }
            guard hostView !== resolvedHostView else { return }

            detach()
            resolvedHostView.addGestureRecognizer(recognizer)
            hostView = resolvedHostView
        }

        func detach() {
            hostView?.removeGestureRecognizer(recognizer)
            hostView = nil
        }

        @objc
        private func handleDoubleClick() {
            onDoubleClick()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let hostView else { return false }
            let location = gestureRecognizer.location(in: hostView)
            guard let hitView = hostView.hitTest(location) else { return false }
            return !containsControl(in: hitView)
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith event: NSGestureRecognizer) -> Bool {
            true
        }

        private func resolveHostView(from markerView: NSView) -> NSView? {
            var current = markerView.superview
            while let view = current {
                if view.bounds.width >= 2, view.bounds.height >= 2 {
                    return view
                }
                current = view.superview
            }
            return markerView.superview
        }

        private func containsControl(in view: NSView) -> Bool {
            var current: NSView? = view
            while let currentView = current {
                if currentView is NSControl {
                    return true
                }
                current = currentView.superview
            }
            return false
        }
    }
}

@MainActor
private final class QueueThumbnailStore: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var loadingKeys = Set<String>()

    func image(for url: URL) -> NSImage? {
        images[cacheKey(for: url)]
    }

    func loadThumbnail(for url: URL, forceReload: Bool = false) {
        let key = cacheKey(for: url)
        if forceReload {
            images.removeValue(forKey: key)
        }
        guard images[key] == nil, !loadingKeys.contains(key) else { return }

        loadingKeys.insert(key)
        Task(priority: .utility) {
            let thumbnail = await Self.generateThumbnailWithRetries(for: url)
            self.images[key] = thumbnail ?? Self.placeholderImage(for: url)
            self.loadingKeys.remove(key)
        }
    }

    static func placeholderImage(for url: URL) -> NSImage {
        let image: NSImage
        if url.pathExtension.isEmpty {
            image = NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
        } else {
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .movie)
        }
        image.size = NSSize(width: 52, height: 52)
        return image
    }

    private func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(url.path)|\(timestamp)|\(fileSize)"
    }

    private nonisolated static func generateThumbnailWithRetries(for url: URL) async -> NSImage? {
        let delays: [UInt64] = [
            0,
            150_000_000,
            400_000_000,
            900_000_000
        ]

        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            if let thumbnail = await generateThumbnail(for: url) {
                return thumbnail
            }
        }

        return await generateVideoFramePreview(for: url)
    }

    private nonisolated static func generateThumbnail(for url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 104, height: 104),
                scale: 2,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                guard error == nil, let thumbnail else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: thumbnail.nsImage)
            }
        }
    }

    private nonisolated static func generateVideoFramePreview(for url: URL) async -> NSImage? {
        guard isVideoFileURL(url) else { return nil }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        let targetSeconds: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            targetSeconds = min(max(durationSeconds * 0.1, 0), 2)
        } else {
            targetSeconds = 0
        }

        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: targetTime, actualTime: nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 104, height: 104))
    }

    private nonisolated static func isVideoFileURL(_ url: URL) -> Bool {
        guard let contentType = UTType(filenameExtension: url.pathExtension) else { return false }
        return contentType.conforms(to: .movie) || contentType.conforms(to: .video)
    }
}
