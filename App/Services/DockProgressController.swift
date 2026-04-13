import AppKit
import Combine
import Foundation

@MainActor
final class DockProgressController: ObservableObject {
    private weak var queueStore: JobQueueStore?
    private var cancellables = Set<AnyCancellable>()
    private var lastRenderedProgress: Double = -1
    private let overlayView: DockProgressView

    init(queueStore: JobQueueStore) {
        self.queueStore = queueStore
        self.overlayView = DockProgressView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            baseIcon: Self.baseApplicationIcon()
        )
        bind(queueStore: queueStore)
    }

    private func bind(queueStore: JobQueueStore) {
        queueStore.$jobs
            .combineLatest(queueStore.$queueState)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateDockTile()
            }
            .store(in: &cancellables)
    }

    private func updateDockTile() {
        guard let queueStore else { return }
        guard let progress = queueStore.dockProgressFraction else {
            clearDockTileOverlay()
            return
        }

        if abs(progress - lastRenderedProgress) < 0.005 {
            return
        }
        lastRenderedProgress = progress

        let dockSize = NSApp.dockTile.size
        if overlayView.frame.size != dockSize {
            overlayView.frame = NSRect(origin: .zero, size: dockSize)
        }
        overlayView.progress = progress
        if NSApp.dockTile.contentView !== overlayView {
            NSApp.dockTile.contentView = overlayView
        }
        NSApp.dockTile.display()
    }

    private func clearDockTileOverlay() {
        guard NSApp.dockTile.contentView != nil || lastRenderedProgress >= 0 else { return }
        lastRenderedProgress = -1
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    private static func baseApplicationIcon() -> NSImage {
        if let namedIcon = NSImage(named: NSImage.applicationIconName)?.copy() as? NSImage {
            return namedIcon
        }
        if let liveIcon = NSApp.applicationIconImage.copy() as? NSImage {
            return liveIcon
        }
        return NSImage(size: NSSize(width: 128, height: 128))
    }
}

private final class DockProgressView: NSView {
    private let baseIcon: NSImage

    var progress: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }

    init(frame frameRect: NSRect, baseIcon: NSImage) {
        self.baseIcon = baseIcon
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        baseIcon.draw(in: bounds)

        let horizontalInset = max(10, bounds.width * 0.1)
        let barHeight = max(10, bounds.height * 0.075)
        let padding = max(9, bounds.height * 0.07)
        let barRect = NSRect(
            x: horizontalInset,
            y: bounds.height - barHeight - padding,
            width: bounds.width - horizontalInset * 2,
            height: barHeight
        )

        let trackPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: barHeight / 2,
            yRadius: barHeight / 2
        )
        NSColor.black.withAlphaComponent(0.34).setFill()
        trackPath.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        let fillInset: CGFloat = 1.5
        let availableFillRect = barRect.insetBy(dx: fillInset, dy: fillInset)
        let filledWidth = max(0, min(availableFillRect.width, availableFillRect.width * CGFloat(progress)))
        guard filledWidth > 0 else { return }

        let filledRect = NSRect(
            x: availableFillRect.minX,
            y: availableFillRect.minY,
            width: filledWidth,
            height: availableFillRect.height
        )
        let fillRadius = availableFillRect.height / 2
        let fillPath = NSBezierPath(
            roundedRect: filledRect,
            xRadius: fillRadius,
            yRadius: fillRadius
        )
        NSColor.controlAccentColor.setFill()
        fillPath.fill()
    }
}
