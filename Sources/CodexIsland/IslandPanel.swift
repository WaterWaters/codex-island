import AppKit
import SwiftUI
import IslandCore

final class FloatingPanel: NSPanel {
    var middleClick: (@MainActor () -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .otherMouseDown && event.buttonNumber == 2 {
            middleClick?()
            return
        }
        super.sendEvent(event)
    }
}

/// WindowServer-level click-through for transparent corners and camera housing.
/// A SwiftUI contentShape alone does not pass clicks to other applications.
@MainActor
final class IslandPanelController {
    private let panel: FloatingPanel
    private var geometry: IslandGeometry?
    private var hostingView: NSHostingView<IslandView>?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var clickThrough = ClickThroughLease()
    private var restoreTask: Task<Void, Never>?
    var onClickThroughChange: (@MainActor (Bool) -> Void)?
    var clickThroughSecondsRemaining: Int { clickThrough.remainingSeconds(now: Date()) }

    init() {
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Codex Island"
        panel.ignoresMouseEvents = true
        panel.middleClick = { [weak self] in self?.beginClickThrough() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitRegion() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateHitRegion() }
            return event
        }
    }

    func update(model: IslandModel, openCodex: @escaping @MainActor () -> Void) {
        guard model.shouldShow, let screen = NSScreen.screens.first else { hide(); return }
        let inset = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat
        if let left, let right, inset > 0 { notchWidth = max(0, right.minX - left.maxX) }
        else { notchWidth = 0 }
        let next = IslandGeometry.layout(screenWidth: screen.frame.width, notchWidth: notchWidth,
                                         notchHeight: inset, expanded: model.isExpanded,
                                         contentHeight: model.preferences.values.contentHeight)
        let rect = NSRect(x: screen.frame.midX - next.width / 2,
                          y: next.hasNotch ? screen.frame.maxY - next.height : screen.visibleFrame.maxY - next.height - 8,
                          width: next.width, height: next.height)
        // Keep the current view alive across duplicate snapshots (including animation ticks).
        let changed = geometry != next
        let animate = changed && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if changed {
            geometry = next
            let root = IslandView(model: model, geometry: next, openCodex: openCodex)
            if let hostingView { hostingView.rootView = root }
            else {
                let host = NSHostingView(rootView: root)
                hostingView = host
                panel.contentView = host
            }
        }
        panel.level = next.hasNotch ? .statusBar : .floating
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                panel.animator().setFrame(rect, display: true)
            }
        } else if panel.frame != rect { panel.setFrame(rect, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateHitRegion()
    }

    private func updateHitRegion() {
        guard panel.isVisible, let geometry else { return }
        if clickThrough.isActive(now: Date()) {
            panel.alphaValue = 0.4
            panel.ignoresMouseEvents = true
            return
        }
        panel.alphaValue = 1
        let point = NSEvent.mouseLocation
        let local = NSPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        var visible = IslandShape(notched: geometry.hasNotch)
            .path(in: CGRect(origin: .zero, size: panel.frame.size)).contains(local)
        if geometry.hasNotch,
           abs(point.x - panel.frame.midX) < geometry.notchWidth / 2,
           local.y < geometry.notchHeight { visible = false }
        panel.ignoresMouseEvents = !visible
    }

    func hide() { panel.orderOut(nil); panel.ignoresMouseEvents = true }

    func beginClickThrough() {
        guard panel.isVisible else { return }
        restoreTask?.cancel()
        clickThrough.begin(now: Date())
        panel.alphaValue = 0.4
        panel.ignoresMouseEvents = true
        onClickThroughChange?(true)
        restoreTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.endClickThrough()
        }
    }

    func endClickThrough() {
        restoreTask?.cancel()
        restoreTask = nil
        clickThrough.end()
        panel.alphaValue = 1
        updateHitRegion()
        onClickThroughChange?(false)
    }

    func close() {
        restoreTask?.cancel()
        panel.middleClick = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        mouseMonitor = nil
        localMouseMonitor = nil
        panel.close()
    }
}
