@preconcurrency import ApplicationServices
import AppKit
import IslandCore

enum ApprovalUIReading: Sendable { case pending, clear, permissionRequired, unavailable }

/// Opt-in only. Reads roles and enabled button labels from Codex windows;
/// never sets an AX attribute or performs an AX action.
actor ApprovalUIObserver {
    func read(processID: pid_t) -> ApprovalUIReading {
        guard AXIsProcessTrusted() else { return .permissionRequired }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return .unavailable }
        let deadline = Date().addingTimeInterval(0.15)
        var budget = 2500
        var exhausted = false
        func visit(_ element: AXUIElement, depth: Int) -> (pending: Bool, controls: [ApprovalControl]) {
            guard budget > 0, depth < 36, Date() < deadline else { exhausted = true; return (false, []) }
            budget -= 1
            if (attribute(element, kAXHiddenAttribute) as? Bool) == true { return (false, []) }
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXButtonRole {
                guard (attribute(element, kAXEnabledAttribute) as? Bool) == true else { return (false, []) }
                let label: String
                if let title = attribute(element, kAXTitleAttribute) as? String {
                    label = title
                } else {
                    label = (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
                }
                return (false, [ApprovalControl(label: String(label.prefix(120)))])
            }
            var controls: [ApprovalControl] = []
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            // Recent transcript controls are normally at the end of the tree.
            if children.count > 128 { exhausted = true }
            for child in children.suffix(128).reversed() {
                let result = visit(child, depth: depth + 1)
                if result.pending { return (true, []) }
                if controls.count <= 12 { controls.append(contentsOf: result.controls.prefix(13)) }
                if exhausted && Date() >= deadline { break }
            }
            let container = role == kAXGroupRole || role == kAXWindowRole
            return (container && ApprovalControls.isPending(controls), Array(controls.prefix(13)))
        }
        for window in windows.prefix(12) {
            if (attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
            if visit(window, depth: 0).pending { return .pending }
        }
        return exhausted ? .unavailable : .clear
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

@MainActor
enum ApprovalAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
