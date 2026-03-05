import AppKit
import SwiftUI

enum SidebarFocusTarget: Hashable {
    case presets
    case chooseDefaultOutputFolder
    case chooseOutputFolderForSelection
    case videoToolboxDefault
    case allowOverwrite
    case container
    case videoCodec
    case quality
    case resolution
    case resolutionCustomWidth
    case resolutionCustomHeight
    case fps
    case fpsCustomValue
    case audioCodec
    case audioBitrate
    case audioChannels
    case subtitles
    case cleanupMetadata
    case cleanupChapters
    case hdrEnable
    case hdrToneMap
    case advancedHeader
    case advancedFFmpegChange
    case advancedFFmpegReset
    case advancedFFprobeChange
    case advancedFFprobeReset
    case advancedVideoBitrate
    case advancedSubtitleLanguage
    case advancedCustomArgs
    case advancedCustomArgsReset
    case renamePrefix
    case renameSuffix
    case renameReplace
    case renameWith
    case renameSanitize
    case renameApply

    var scrollID: String {
        switch self {
        case .presets: return "focus.presets"
        case .chooseDefaultOutputFolder: return "focus.defaults.output"
        case .chooseOutputFolderForSelection: return "focus.defaults.selectionOutput"
        case .videoToolboxDefault: return "focus.defaults.videotoolbox"
        case .allowOverwrite: return "focus.defaults.overwrite"
        case .container: return "focus.essentials.container"
        case .videoCodec: return "focus.essentials.videoCodec"
        case .quality: return "focus.essentials.quality"
        case .resolution: return "focus.essentials.resolution"
        case .resolutionCustomWidth: return "focus.essentials.resolution.customWidth"
        case .resolutionCustomHeight: return "focus.essentials.resolution.customHeight"
        case .fps: return "focus.essentials.fps"
        case .fpsCustomValue: return "focus.essentials.fps.customValue"
        case .audioCodec: return "focus.essentials.audioCodec"
        case .audioBitrate: return "focus.essentials.audioBitrate"
        case .audioChannels: return "focus.essentials.audioChannels"
        case .subtitles: return "focus.subtitles.mode"
        case .cleanupMetadata: return "focus.cleanup.metadata"
        case .cleanupChapters: return "focus.cleanup.chapters"
        case .hdrEnable: return "focus.hdr.enable"
        case .hdrToneMap: return "focus.hdr.tonemap"
        case .advancedHeader: return "focus.advanced.header"
        case .advancedFFmpegChange: return "focus.advanced.ffmpeg.change"
        case .advancedFFmpegReset: return "focus.advanced.ffmpeg.reset"
        case .advancedFFprobeChange: return "focus.advanced.ffprobe.change"
        case .advancedFFprobeReset: return "focus.advanced.ffprobe.reset"
        case .advancedVideoBitrate: return "focus.advanced.videoBitrate"
        case .advancedSubtitleLanguage: return "focus.advanced.subtitleLanguage"
        case .advancedCustomArgs: return "focus.advanced.customArgs"
        case .advancedCustomArgsReset: return "focus.advanced.customArgs.reset"
        case .renamePrefix: return "focus.rename.prefix"
        case .renameSuffix: return "focus.rename.suffix"
        case .renameReplace: return "focus.rename.replace"
        case .renameWith: return "focus.rename.with"
        case .renameSanitize: return "focus.rename.sanitize"
        case .renameApply: return "focus.rename.apply"
        }
    }

    var headerScrollID: String {
        "header.\(scrollID)"
    }
}

@MainActor
final class SidebarFocusRouter: ObservableObject {
    enum FocusChangeSource {
        case keyboardTab
        case keyboardShiftTab
        case mouse
        case programmatic
    }

    enum CoarseScrollAnchor {
        case center
        case top
    }

    private struct PendingFocusRequest {
        var target: SidebarFocusTarget
        var source: FocusChangeSource
        var retries: Int
    }

    @Published var activeTarget: SidebarFocusTarget?
    @Published fileprivate(set) var currentFocusedTarget: SidebarFocusTarget?

    private struct TargetConfig {
        var isEnabled: () -> Bool
        var onFocusGained: () -> Void
        var onKeyDown: (NSEvent) -> Bool
    }

    private weak var window: NSWindow?
    private weak var scopeView: NSView?
    private var proxyViews = [SidebarFocusTarget: WeakBox<FocusProxyView>]()
    private var targetConfigs = [SidebarFocusTarget: TargetConfig]()
    private var order: [SidebarFocusTarget] = []
    private var keyMonitor: Any?
    private var pendingFocusRequest: PendingFocusRequest?
    private var pendingInitialTabTarget: SidebarFocusTarget?
    private var logicalIsEnabled: ((SidebarFocusTarget) -> Bool)?
    private var coarseScrollRequest: ((SidebarFocusTarget, CoarseScrollAnchor) -> Void)?
    private let maxPendingRetries = 2
    private var isSidebarVisible = true

    func configureOrder(
        _ order: [SidebarFocusTarget],
        logicalIsEnabled: ((SidebarFocusTarget) -> Bool)? = nil
    ) {
        self.order = order
        self.logicalIsEnabled = logicalIsEnabled
    }

    func setCoarseScrollRequest(_ request: @escaping (SidebarFocusTarget, CoarseScrollAnchor) -> Void) {
        coarseScrollRequest = request
    }

    func setSidebarVisible(_ isVisible: Bool) {
        guard isSidebarVisible != isVisible else { return }
        isSidebarVisible = isVisible
        if !isVisible {
            pendingFocusRequest = nil
            pendingInitialTabTarget = nil
            activeTarget = nil
            currentFocusedTarget = nil
        }
    }

    func reconcileFocus(reason _: String, preferredFallback: SidebarFocusTarget? = nil) {
        guard isSidebarVisible else { return }
        let enabledOrder = order.filter { isTargetEnabled($0) }

        if let pending = pendingFocusRequest,
           !enabledOrder.contains(pending.target) {
            pendingFocusRequest = nil
        }

        guard let current = currentFocusedTarget ?? activeTarget else { return }
        guard !enabledOrder.contains(current) else { return }

        let fallback = chooseFallbackTarget(
            from: current,
            enabledOrder: enabledOrder,
            preferred: preferredFallback
        )
        guard let fallback else {
            currentFocusedTarget = nil
            activeTarget = nil
            return
        }
        focus(fallback, source: .programmatic)
    }

    func invalidate() {
        // Keep the last logical focus target so Tab can continue
        // even when SwiftUI updates control state (e.g. pill selection changes).
    }

    func register(
        target: SidebarFocusTarget,
        proxyView: FocusProxyView,
        isEnabled: @escaping () -> Bool,
        onFocusGained: @escaping () -> Void,
        onKeyDown: @escaping (NSEvent) -> Bool
    ) {
        proxyViews[target] = WeakBox(value: proxyView)
        targetConfigs[target] = TargetConfig(isEnabled: isEnabled, onFocusGained: onFocusGained, onKeyDown: onKeyDown)
        scopeView = resolveScope(from: proxyView)
        window = proxyView.window
        installKeyMonitorIfNeeded()

        if let pending = pendingFocusRequest, pending.target == target {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focus(target, source: pending.source)
            }
        }
    }

    func unregister(target: SidebarFocusTarget) {
        proxyViews[target] = nil
        targetConfigs[target] = nil
    }

    func focus(_ target: SidebarFocusTarget, source: FocusChangeSource = .programmatic) {
        guard isSidebarVisible else { return }
        guard isTargetEnabled(target) else { return }
        currentFocusedTarget = target
        guard let view = proxyViews[target]?.value,
              let window = view.window else {
            pendingFocusRequest = PendingFocusRequest(target: target, source: source, retries: 0)
            if source == .keyboardTab || source == .keyboardShiftTab {
                invokeCoarseScroll(for: target, attempt: 0)
                schedulePendingResolve()
            }
            return
        }
        let didFocus = window.makeFirstResponder(view)
        if !didFocus {
            pendingFocusRequest = PendingFocusRequest(target: target, source: source, retries: 0)
            if source == .keyboardTab || source == .keyboardShiftTab {
                invokeCoarseScroll(for: target, attempt: 0)
                schedulePendingResolve()
            }
            return
        }
        pendingFocusRequest = nil
        activeTarget = target
        if source == .keyboardTab || source == .keyboardShiftTab {
            centerTargetInScrollViewOnNextRunLoop(target, reason: "focus")
        }
    }

    func focusNext(from target: SidebarFocusTarget, backwards: Bool) {
        guard isSidebarVisible else { return }
        let enabledOrder = order.filter { isTargetEnabled($0) }
        guard !enabledOrder.isEmpty else { return }
        guard let index = enabledOrder.firstIndex(of: target) else {
            moveFocus(
                backwards ? enabledOrder.last! : enabledOrder.first!,
                source: backwards ? .keyboardShiftTab : .keyboardTab
            )
            return
        }
        let step = backwards ? -1 : 1
        let nextIndex = (index + step + enabledOrder.count) % enabledOrder.count
        moveFocus(enabledOrder[nextIndex], source: backwards ? .keyboardShiftTab : .keyboardTab)
    }

    func handleKeyDown(for target: SidebarFocusTarget, event: NSEvent) -> Bool {
        guard isSidebarVisible else { return false }
        if event.keyCode == 48 {
            if pendingFocusRequest != nil {
                resolvePendingFocusIfNeeded()
                return true
            }
            let source = currentFocusedTarget ?? target
            focusNext(from: source, backwards: event.modifierFlags.contains(.shift))
            return true
        }
        if let handler = targetConfigs[target]?.onKeyDown {
            return handler(event)
        }
        return false
    }

    func detach() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        proxyViews.removeAll()
        targetConfigs.removeAll()
        scopeView = nil
        window = nil
        activeTarget = nil
        currentFocusedTarget = nil
        pendingFocusRequest = nil
        logicalIsEnabled = nil
        coarseScrollRequest = nil
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 48 else { return event } // Tab
            guard let window = self.window ?? self.scopeView?.window else { return event }
            guard window.isKeyWindow else { return event }
            guard self.isSidebarVisible else { return event }

            let isTextEditing = self.isTextEditingResponder(window.firstResponder)

            let hasRouterContext = self.currentFocusedTarget != nil
                || self.activeTarget != nil
                || self.pendingFocusRequest != nil
            if !hasRouterContext && isTextEditing {
                return event
            }

            if self.pendingFocusRequest != nil {
                self.resolvePendingFocusIfNeeded()
                return nil
            }

            let enabledOrder = self.order.filter { self.isTargetEnabled($0) }
            guard !enabledOrder.isEmpty else { return event }

            if self.currentFocusedTarget == nil && self.activeTarget == nil {
                let backwards = event.modifierFlags.contains(.shift)
                let initialTarget = backwards ? enabledOrder.last! : enabledOrder.first!
                self.pendingInitialTabTarget = initialTarget
                self.moveFocus(initialTarget, source: backwards ? .keyboardShiftTab : .keyboardTab)
                return nil
            }

            let currentTarget = self.currentFocusedTarget ?? self.activeTarget!
            if !enabledOrder.contains(currentTarget) {
                let healed = self.chooseFallbackTarget(from: currentTarget, enabledOrder: enabledOrder, preferred: nil)
                guard let healed else { return nil }
                self.currentFocusedTarget = healed
                self.activeTarget = healed
                self.focusNext(from: healed, backwards: event.modifierFlags.contains(.shift))
                return nil
            }
            self.focusNext(from: currentTarget, backwards: event.modifierFlags.contains(.shift))
            return nil
        }
    }

    private func resolveScope(from view: NSView) -> NSView {
        var current = view
        while let superview = current.superview {
            if superview is NSSplitView {
                break
            }
            current = superview
        }
        return current
    }

    private func isTargetEnabled(_ target: SidebarFocusTarget) -> Bool {
        let logicalEnabled = logicalIsEnabled?(target) ?? true
        let mountedEnabled = targetConfigs[target]?.isEnabled() ?? true
        return logicalEnabled && mountedEnabled
    }

    private func schedulePendingResolve() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.resolvePendingFocusIfNeeded()
        }
    }

    private func resolvePendingFocusIfNeeded() {
        guard isSidebarVisible else {
            pendingFocusRequest = nil
            return
        }
        guard var pending = pendingFocusRequest else { return }
        let target = pending.target

        if let view = proxyViews[target]?.value,
           let window = view.window {
            _ = window.makeFirstResponder(view)
            activeTarget = target
            currentFocusedTarget = target
            pendingFocusRequest = nil
            if pending.source == .keyboardTab || pending.source == .keyboardShiftTab {
                centerTargetInScrollViewOnNextRunLoop(target, reason: "pending")
            }
            return
        }

        guard pending.retries < maxPendingRetries else {
            pending.retries = 0
            pendingFocusRequest = pending
            invokeCoarseScroll(for: target, attempt: 0)
            schedulePendingResolve()
            return
        }

        pending.retries += 1
        pendingFocusRequest = pending
        invokeCoarseScroll(for: target, attempt: pending.retries)
        schedulePendingResolve()
    }

    private func invokeCoarseScroll(for target: SidebarFocusTarget, attempt _: Int) {
        guard isSidebarVisible else { return }
        let anchor: CoarseScrollAnchor = .center
        coarseScrollRequest?(target, anchor)
    }

    private func chooseFallbackTarget(
        from current: SidebarFocusTarget,
        enabledOrder: [SidebarFocusTarget],
        preferred: SidebarFocusTarget?
    ) -> SidebarFocusTarget? {
        if let preferred, enabledOrder.contains(preferred) {
            return preferred
        }
        guard !enabledOrder.isEmpty else { return nil }
        guard let currentIndex = order.firstIndex(of: current) else {
            return enabledOrder.first
        }

        var bestTarget: SidebarFocusTarget?
        var bestDistance = Int.max
        for target in enabledOrder {
            guard let idx = order.firstIndex(of: target) else { continue }
            let distance = abs(idx - currentIndex)
            if distance < bestDistance {
                bestDistance = distance
                bestTarget = target
            }
        }

        return bestTarget ?? enabledOrder.first
    }

    private func isTextEditingResponder(_ responder: AnyObject?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }

    private func centerTargetInScrollView(_ target: SidebarFocusTarget) {
        guard isSidebarVisible else { return }
        guard let proxyView = proxyViews[target]?.value else { return }
        guard let scrollView = findEnclosingScrollView(from: proxyView),
              let documentView = scrollView.documentView else { return }

        let anchorView = anchorViewForScroll(from: proxyView, within: documentView)
        let targetRect = anchorView.convert(anchorView.bounds, to: documentView)
        let visibleRect = scrollView.contentView.documentVisibleRect

        var newY = targetRect.midY - (visibleRect.height / 2)
        let maxY = max(0, documentView.bounds.height - visibleRect.height)
        let contentInsetTop = scrollView.contentInsets.top
        let minY = min(maxY, -contentInsetTop)
        newY = min(max(newY, minY), maxY)

        let delta = newY - visibleRect.origin.y
        if abs(delta) < 0.5 { return }

        scrollView.contentView.scroll(to: NSPoint(x: visibleRect.origin.x, y: newY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func centerTargetInScrollViewOnNextRunLoop(_ target: SidebarFocusTarget, reason _: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isSidebarVisible else { return }
            self.centerTargetInScrollView(target)
            if self.pendingInitialTabTarget == target {
                self.pendingInitialTabTarget = nil
            }
        }
    }

    private func moveFocus(_ target: SidebarFocusTarget, source: FocusChangeSource) {
        focus(target, source: source)
    }

    private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let node = current {
            if let scrollView = node as? NSScrollView {
                return scrollView
            }
            if let enclosing = node.enclosingScrollView {
                return enclosing
            }
            current = node.superview
        }
        return nil
    }

    private func anchorViewForScroll(from proxyView: NSView, within documentView: NSView) -> NSView {
        var current: NSView = proxyView
        while let superview = current.superview,
              superview.isDescendant(of: documentView) {
            if current.bounds.width >= 2, current.bounds.height >= 2 {
                return current
            }
            current = superview
        }
        return current
    }
}

final class FocusProxyView: NSView {
    var onFocusChanged: ((Bool) -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize { .zero }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusChanged?(true)
            needsDisplay = true
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        onFocusChanged?(false)
        needsDisplay = true
        return result
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(value: T?) {
        self.value = value
    }
}

struct FocusableContainer<Content: View>: View {
    @ObservedObject var router: SidebarFocusRouter
    let target: SidebarFocusTarget
    var isEnabled: Bool = true
    var onFocusGained: () -> Void = {}
    let onKeyDown: (NSEvent) -> Bool
    let content: () -> Content

    var body: some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(router.activeTarget == target ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                router.focus(target, source: .mouse)
            })
            .overlay(alignment: .topLeading) {
                FocusProxyRepresentable(
                    router: router,
                    target: target,
                    isEnabled: { isEnabled },
                    onFocusGained: onFocusGained,
                    onKeyDown: onKeyDown
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .id(target.scrollID)
        .accessibilityElement(children: .contain)
    }
}

private struct FocusProxyRepresentable: NSViewRepresentable {
    @ObservedObject var router: SidebarFocusRouter
    let target: SidebarFocusTarget
    let isEnabled: () -> Bool
    let onFocusGained: () -> Void
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> FocusProxyView {
        let view = FocusProxyView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onFocusChanged = { isFocused in
            if isFocused {
                router.activeTarget = target
                router.currentFocusedTarget = target
                onFocusGained()
            } else if router.activeTarget == target {
                router.activeTarget = nil
            }
        }
        view.onKeyDown = { event in
            if router.handleKeyDown(for: target, event: event) {
                return true
            }
            return onKeyDown(event)
        }
        DispatchQueue.main.async {
            router.register(
                target: target,
                proxyView: view,
                isEnabled: isEnabled,
                onFocusGained: onFocusGained,
                onKeyDown: onKeyDown
            )
        }
        return view
    }

    func updateNSView(_ nsView: FocusProxyView, context: Context) {
        nsView.onKeyDown = { event in
            if router.handleKeyDown(for: target, event: event) {
                return true
            }
            return onKeyDown(event)
        }
        DispatchQueue.main.async {
            router.register(
                target: target,
                proxyView: nsView,
                isEnabled: isEnabled,
                onFocusGained: onFocusGained,
                onKeyDown: onKeyDown
            )
        }
    }

    static func dismantleNSView(_ nsView: FocusProxyView, coordinator: ()) {
        // no-op; router cleanup handled by sidebar lifecycle
    }
}
