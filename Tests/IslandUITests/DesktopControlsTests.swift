import Carbon
import Foundation
import Testing
@testable import CodexIsland

@MainActor private final class LoginItemMock: LoginItemManaging {
    enum Failure: Error { case denied }
    var status: LoginItemStatus
    var nextStatus: LoginItemStatus?
    var shouldFail = false
    private(set) var requests: [Bool] = []

    init(status: LoginItemStatus) { self.status = status }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let nextStatus { status = nextStatus }
        if shouldFail { throw Failure.denied }
    }
}

@MainActor private final class ShortcutMock: ShortcutRegistering {
    var result: OSStatus = noErr
    private(set) var registrationCount = 0
    private(set) var unregistrationCount = 0
    private var action: (@MainActor () -> Void)?

    func register(action: @escaping @MainActor () -> Void) -> OSStatus {
        registrationCount += 1
        self.action = result == noErr ? action : nil
        return result
    }

    func unregister() {
        unregistrationCount += 1
        action = nil
    }

    func press() { action?() }
}

@MainActor @Test func loginItemInitializationAndRefreshOnlyReadActualSystemStatus() {
    let service = LoginItemMock(status: .enabled)
    let controller = LoginItemController(service: service)
    #expect(controller.status == .enabled)
    #expect(service.requests.isEmpty)
    for actualStatus in [LoginItemStatus.disabled, .approvalRequired, .unavailable, .enabled] {
        service.status = actualStatus
        controller.refresh()
        #expect(controller.status == actualStatus)
    }
    #expect(service.requests.isEmpty)
    #expect(!controller.failed)
}

@MainActor @Test func loginItemEnableRequiresObservedSystemApprovalInsteadOfAssumingSuccess() {
    let service = LoginItemMock(status: .disabled)
    let controller = LoginItemController(service: service)
    service.nextStatus = .approvalRequired
    controller.setEnabled(true)
    #expect(service.requests == [true])
    #expect(controller.status == .approvalRequired)
    #expect(!controller.failed)
    service.status = .enabled
    controller.refresh()
    #expect(controller.status == .enabled)
    service.nextStatus = .disabled
    controller.setEnabled(false)
    #expect(service.requests == [true, false])
    #expect(controller.status == .disabled)
}

@MainActor @Test func loginItemFailurePreservesActualStatusAndNextRequestCanRecover() {
    let service = LoginItemMock(status: .enabled)
    let controller = LoginItemController(service: service)
    service.shouldFail = true
    controller.setEnabled(false)
    #expect(controller.failed)
    #expect(controller.status == .enabled)
    // An API error may still change the system's reported state. Always re-read.
    service.nextStatus = .approvalRequired
    controller.setEnabled(true)
    #expect(controller.failed)
    #expect(controller.status == .approvalRequired)
    service.shouldFail = false
    service.nextStatus = .disabled
    controller.setEnabled(false)
    #expect(!controller.failed && controller.status == .disabled)
    #expect(service.requests == [false, true, false])
}

@MainActor @Test func unavailableLoginItemControllerNeverReportsARegistration() {
    let controller = LoginItemController()
    #expect(controller.status == .unavailable)
    controller.setEnabled(true)
    #expect(controller.status == .unavailable)
    controller.setEnabled(false)
    #expect(controller.status == .unavailable)
}

@MainActor @Test func shortcutIsOptInAndRepeatedConfigurationDoesNotRegisterAgain() {
    let service = ShortcutMock()
    let controller = ShortcutController(service: service)
    var presses = 0
    #expect(controller.status == .disabled)
    controller.configure(enabled: false) { presses += 1 }
    #expect(service.registrationCount == 0 && service.unregistrationCount == 0)
    service.press()
    #expect(presses == 0)
    controller.configure(enabled: true) { presses += 1 }
    #expect(controller.status == .registered)
    controller.configure(enabled: true) { presses += 100 }
    #expect(service.registrationCount == 1)
    service.press()
    #expect(presses == 1)
}

@MainActor @Test func shortcutRegistrationFailureIsVisibleAndCanRetryAfterDisabling() {
    let service = ShortcutMock()
    service.result = OSStatus(eventHotKeyExistsErr)
    let controller = ShortcutController(service: service)
    var presses = 0
    controller.configure(enabled: true) { presses += 1 }
    #expect(controller.status == .failed(OSStatus(eventHotKeyExistsErr)))
    service.press()
    #expect(presses == 0)
    // Routine preference refreshes must not repeatedly claim the same key.
    controller.configure(enabled: true) { presses += 1 }
    #expect(service.registrationCount == 1)
    controller.configure(enabled: false) { presses += 1 }
    #expect(controller.status == .disabled)
    service.result = noErr
    controller.configure(enabled: true) { presses += 1 }
    #expect(controller.status == .registered && service.registrationCount == 2)
    service.press()
    #expect(presses == 1)
}

@MainActor @Test func disablingAndClosingShortcutReleaseTheCallbackAndAllowReopening() {
    let service = ShortcutMock()
    let controller = ShortcutController(service: service)
    var presses = 0
    controller.configure(enabled: true) { presses += 1 }
    controller.configure(enabled: false) { presses += 100 }
    #expect(controller.status == .disabled && service.unregistrationCount == 1)
    controller.configure(enabled: false) { presses += 100 }
    #expect(service.unregistrationCount == 1)
    service.press()
    #expect(presses == 0)
    controller.configure(enabled: true) { presses += 1 }
    service.press()
    controller.close()
    #expect(controller.status == .disabled && service.unregistrationCount == 2)
    service.press()
    #expect(presses == 1)
    controller.configure(enabled: true) { presses += 10 }
    service.press()
    #expect(presses == 11 && service.registrationCount == 3)
    controller.close()
}

@Test func overlappingSleepDisplayAndLockReasonsCannotResumeEachOther() {
    var state = SuspensionState()
    #expect(!state.isSuspended)
    state.set(.inactiveSession, active: true)
    state.set(.systemSleep, active: true)
    state.set(.displaySleep, active: true)
    // Duplicate notifications must not require duplicate wakes.
    state.set(.systemSleep, active: true)
    state.set(.systemSleep, active: false)
    #expect(state.isSuspended)
    #expect(state.reasons == [.inactiveSession, .displaySleep])
    state.set(.displaySleep, active: false)
    #expect(state.isSuspended && state.reasons == [.inactiveSession])
    state.set(.systemSleep, active: false)
    #expect(state.isSuspended)
    state.set(.inactiveSession, active: false)
    #expect(!state.isSuspended)
}

@Test func wakingOneReasonBeforeAnotherStartsDoesNotLoseTheNewSuspension() {
    var state = SuspensionState()
    state.set(.displaySleep, active: true)
    state.set(.displaySleep, active: false)
    #expect(!state.isSuspended)
    state.set(.inactiveSession, active: true)
    state.set(.displaySleep, active: false)
    #expect(state.isSuspended)
    state.set(.inactiveSession, active: false)
    #expect(!state.isSuspended)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_SYSTEM_SHORTCUT"] == "1",
    "Opt in on a desktop to register and immediately release the real system chord"))
func realSystemShortcutDetectsConflictAndReleasesRegistration() {
    let first = SystemShortcut()
    let duplicate = SystemShortcut()
    defer { first.unregister(); duplicate.unregister() }
    let result = first.register {}
    #expect(result == noErr)
    guard result == noErr else { return }
    #expect(duplicate.register {} == OSStatus(eventHotKeyExistsErr))
    first.unregister()
    #expect(duplicate.register {} == noErr)
}
