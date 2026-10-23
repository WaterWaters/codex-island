import AppKit
import Carbon
import Observation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case disabled, enabled, approvalRequired, unavailable

    var message: String {
        switch self {
        case .disabled: "登录时启动未开启"
        case .enabled: "系统已允许登录时启动"
        case .approvalRequired: "需要在系统登录项设置中允许"
        case .unavailable: "当前运行方式不支持登录项，请使用已安装的应用"
        }
    }
}

@MainActor protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor struct SystemLoginItem: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .approvalRequired
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

/// The displayed value always comes from macOS, never a persisted wish.
@MainActor @Observable final class LoginItemController {
    private let service: (any LoginItemManaging)?
    private(set) var status: LoginItemStatus = .unavailable
    private(set) var failed = false
    init(service: (any LoginItemManaging)? = nil) { self.service = service; refresh() }
    func refresh() { status = service?.status ?? .unavailable }
    func setEnabled(_ enabled: Bool) {
        failed = false
        guard let service else { refresh(); return }
        do { try service.setEnabled(enabled) } catch { failed = true }
        refresh()
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor protocol ShortcutRegistering: AnyObject {
    func register(action: @escaping @MainActor () -> Void) -> OSStatus
    func unregister()
}

/// A deliberate, opt-in chord; Carbon registration needs no Accessibility grant.
@MainActor final class SystemShortcut: ShortcutRegistering {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private let identifier = EventHotKeyID(signature: 0x4349534C, id: 1)

    func register(action: @escaping @MainActor () -> Void) -> OSStatus {
        unregister()
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<SystemShortcut>.fromOpaque(context).takeUnretainedValue()
                var key = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard status == noErr, key.signature == owner.identifier.signature,
                      key.id == owner.identifier.id else { return OSStatus(eventNotHandledErr) }
                owner.action?()
                return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { unregister(); return result }
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey | cmdKey),
            identifier, GetApplicationEventTarget(), 0, &hotKey)
        if registration != noErr { unregister() }
        return registration
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
}

@MainActor @Observable final class ShortcutController {
    enum Status: Equatable { case disabled, registered, failed(OSStatus) }
    private let service: any ShortcutRegistering
    private var requested = false
    private(set) var status: Status = .disabled
    init(service: any ShortcutRegistering = SystemShortcut()) { self.service = service }
    func configure(enabled: Bool, action: @escaping @MainActor () -> Void) {
        guard requested != enabled else { return }
        requested = enabled
        if enabled {
            let result = service.register(action: action)
            status = result == noErr ? .registered : .failed(result)
        } else { service.unregister(); status = .disabled }
    }
    func close() { service.unregister(); requested = false; status = .disabled }
}

/// Sleep, display sleep and session lock can overlap. One wake must not clear
/// another reason and let the panel or polling resume behind the lock screen.
struct SuspensionState {
    enum Reason: Hashable { case systemSleep, displaySleep, inactiveSession }
    private(set) var reasons: Set<Reason> = []
    var isSuspended: Bool { !reasons.isEmpty }
    mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}
