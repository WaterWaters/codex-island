import AppKit
import DesktopFeed
import Foundation
import IslandCore
import OSLog

struct Options {
    var demo: WorkState?
    var statusFile: URL?
    var diagnose = false
    var help = false
    var renderPath: URL?
    var galleryPath: URL?
    var mini = false
    var checkResources = false
    private var isPreviewBundle = false

    var permitsPersistentChanges: Bool {
        demo == nil && statusFile == nil && !diagnose && !help && !checkResources && renderPath == nil && galleryPath == nil && !isPreviewBundle && !mini
    }

    init(arguments: [String], previewState: String? = Bundle.main.object(forInfoDictionaryKey: "CodexIslandPreviewState") as? String) throws {
        isPreviewBundle = previewState.flatMap(WorkState.init(rawValue:)) != nil
        if arguments.isEmpty, let value = previewState {
            demo = WorkState(rawValue: value)
        }
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--demo":
                index += 1
                guard index < arguments.count, let value = WorkState(rawValue: arguments[index]) else { throw OptionError.invalid }
                demo = value
            case "--status-file":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/") else { throw OptionError.invalid }
                statusFile = URL(fileURLWithPath: arguments[index])
            case "--diagnose": diagnose = true
            case "--mini": mini = true
            case "--check-resources": checkResources = true
            case "--render-previews":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/") else { throw OptionError.invalid }
                renderPath = URL(fileURLWithPath: arguments[index])
            case "--render-gallery":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/") else { throw OptionError.invalid }
                galleryPath = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--help", "-h": help = true
            default:
                if !arguments[index].hasPrefix("-psn_") { throw OptionError.invalid }
            }
            index += 1
        }
        if demo != nil && statusFile != nil { throw OptionError.invalid }
        if galleryPath != nil && renderPath != nil { throw OptionError.invalid }
    }
    enum OptionError: Error { case invalid }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: Options
    private let model: IslandModel
    private let onboardingProgress: OnboardingProgress
    private let launcher = CodexLauncher()
    private var panel: IslandPanelController?
    private var pollTask: Task<Void, Never>?
    private var petTask: Task<Void, Never>?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var requestedPetID: String?
    private let approvalObserver = ApprovalUIObserver()
    private var gate = SnapshotGate()
    private var suspension = SuspensionState()
    private var suspended: Bool { suspension.isSuspended }
    private let loginItem: LoginItemController
    private let shortcut = ShortcutController()
    private var refreshInFlight = false
    private var sourceGeneration = 0
    private var source: any StatusSource
    private var observers: [NSObjectProtocol] = []

    init(options: Options) {
        self.options = options
        let defaults: UserDefaults? = options.permitsPersistentChanges ? .standard : nil
        model = IslandModel(preferences: IslandPreferences(defaults: defaults))
        if options.mini { model.preferences.values.displayMode = .mini }
        loginItem = LoginItemController(service: options.permitsPersistentChanges ? SystemLoginItem() : nil)
        onboardingProgress = OnboardingProgress(defaults: defaults,
            permitsAutomaticPresentation: options.permitsPersistentChanges)
        if let state = options.demo { source = DemoStatusSource(state: state) }
        else if let url = options.statusFile { source = SnapshotFileSource(url: url) }
        else { source = DesktopStatusSource() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !options.diagnose && NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.water.codex-island").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        if options.diagnose { diagnose(); NSApp.terminate(nil); return }
        L10n.shared.configure(language: model.preferences.values.language)
        configureShortcut()
        model.isDemo = options.demo != nil
        model.isExternalFeed = options.statusFile != nil
        model.isLocalFeed = options.demo == nil && options.statusFile == nil
        panel = IslandPanelController()
        panel?.onClickThroughChange = { @MainActor @Sendable [weak self] active in
            self?.model.isClickThrough = active
            self?.menuBar?.updateStatus()
        }
        model.preferences.onChange = { [weak self] in self?.preferencesDidChange() }
        menuBar = MenuBarController(model: model, openCodex: { [weak self] in self?.openCodex() },
            showSettings: { [weak self] in self?.showSettings() }, refreshPets: { [weak self] in self?.synchronizePets(force: true) },
            refreshStatus: { [weak self] in self?.resynchronizeStatus() },
            toggleClickThrough: { [weak self] in
                guard let self else { return }
                if panel?.clickThroughSecondsRemaining ?? 0 > 0 { panel?.endClickThrough() }
                else { panel?.beginClickThrough() }
            }, remainingSeconds: { [weak self] in self?.panel?.clickThroughSecondsRemaining ?? 0 })
        synchronizePets(force: false)
        observeSystem()
        startPolling()
        if onboardingProgress.shouldPresentAutomatically { showOnboarding() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended { await self.refresh() }
                let interval: Duration = self.options.demo != nil ? .seconds(2) : .milliseconds(500)
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    private func refresh() async {
        // Workspace notifications and polling can interleave at actor awaits.
        // Coalesce them; the next poll will observe any newer state.
        guard !suspended, !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        let generation = sourceGeneration
        if options.demo == nil && options.statusFile == nil && launcher.runningApplication == nil {
            await source.reset()
            guard !suspended, !Task.isCancelled, generation == sourceGeneration else { return }
            model.connection = launcher.applicationURL == nil ? .appNotInstalled : .appNotRunning
            model.sourceFailureReason = nil
            model.sessionTitle = nil
            model.activity = nil
            model.approvalUIIsPending = false
        } else {
            let reading = await source.read()
            guard !suspended, !Task.isCancelled, generation == sourceGeneration else { return }
            switch reading {
            case .snapshot(let snapshot, let health):
                do {
                    let summary = try gate.accept(snapshot, now: Date())
                    if model.summary != summary { model.summary = summary }
                    let title = snapshot.displaySessionTitle
                    if model.sessionTitle != title { model.sessionTitle = title }
                    if model.activity != snapshot.activity { model.activity = snapshot.activity }
                    model.connection = .connected
                    model.sourceFailureReason = nil
                    model.localFeedHealth = health
                } catch {
                    if model.connection != .unavailable {
                        let logger = Logger(subsystem: "dev.water.codex-island", category: "SnapshotGate")
                        logger.error("Status snapshot rejected: \(String(describing: error), privacy: .public)")
                    }
                    model.connection = .unavailable
                    model.sourceFailureReason = .snapshotRejected
                }
            case .unsupported:
                model.connection = .unsupported
                model.sourceFailureReason = .incompatibleSchema
            case .missingLocalData:
                model.connection = .missingLocalData
                model.sourceFailureReason = .missingDatabase
            case .unavailable:
                model.connection = .unavailable
                model.sourceFailureReason = .sourceUnavailable
            case .failure(let reason):
                model.connection = .unavailable
                model.sourceFailureReason = reason
            }
        }
        if model.connection != .connected {
            model.localFeedHealth = nil
            model.summary = .reduce([])
            model.activity = nil
            model.sessionTitle = nil
        }
        if options.demo == nil && options.statusFile == nil,
           model.preferences.values.approvalRecognitionEnabled == true,
           let running = launcher.runningApplication {
            let reading = await approvalObserver.read(processID: running.processIdentifier)
            guard !suspended, !Task.isCancelled, generation == sourceGeneration else { return }
            // Settings can change while the AX actor is reading. A late result
            // must not re-enable an observer the user just disabled.
            guard model.preferences.values.approvalRecognitionEnabled == true,
                  launcher.runningApplication?.processIdentifier == running.processIdentifier else {
                model.approvalUIIsPending = false
                render()
                return
            }
            switch reading {
            case .pending:
                model.approvalUIIsPending = true
                model.approvalAccessMessage = "发现 Codex 审批按钮"
            case .clear:
                model.approvalUIIsPending = false
                model.approvalAccessMessage = "已开启 · 只识别已显示的 Codex 审批窗口"
            case .permissionRequired:
                model.approvalUIIsPending = false
                model.approvalAccessMessage = "需要在系统设置中授权 Codex Island 的辅助功能"
            case .unavailable:
                model.approvalUIIsPending = false
                model.approvalAccessMessage = "暂时无法读取审批控件，继续同步本机会话"
            }
        }
        render()
    }

    private func resynchronizeStatus() {
        sourceGeneration &+= 1
        let generation = sourceGeneration
        pollTask?.cancel()
        model.localFeedHealth = nil
        model.sourceFailureReason = nil
        model.approvalUIIsPending = false
        model.connection = .connecting
        render()
        Task { [weak self] in
            guard let self else { return }
            await source.reset()
            guard !suspended, generation == sourceGeneration else { return }
            gate = SnapshotGate()
            startPolling()
        }
    }

    private func render() {
        menuBar?.updateStatus()
        guard !suspended else { panel?.hide(); return }
        panel?.update(model: model) { [weak self] in self?.openCodex() }
    }

    private func configureShortcut() {
        shortcut.configure(enabled: model.preferences.values.shortcutEnabled) { [weak self] in
            self?.model.preferences.values.isVisible.toggle()
        }
    }

    private func refreshLanguage() {
        let previous = L10n.shared.language
        L10n.shared.configure(language: model.preferences.values.language)
        guard previous != L10n.shared.language else { return }
        settingsWindow?.refreshLanguage()
        onboardingWindow?.refreshLanguage()
        menuBar?.refreshLanguage()
    }

    private func preferencesDidChange() {
        refreshLanguage()
        configureShortcut()
        if model.preferences.values.approvalRecognitionEnabled != true {
            model.approvalUIIsPending = false
            model.approvalAccessMessage = "审批窗口识别未开启"
        }
        if requestedPetID != model.preferences.values.selectedPetID { synchronizePets(force: false) }
        render()
    }

    private func synchronizePets(force: Bool) {
        petTask?.cancel()
        let selection = model.preferences.values.selectedPetID
        requestedPetID = selection
        let applicationURL = launcher.applicationURL
        model.codexVersion = applicationURL.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        petTask = Task { [weak self] in
            guard let self else { return }
            let success = await model.pets.synchronize(applicationURL: applicationURL, selectedID: selection, force: force)
            guard !Task.isCancelled else { return }
            if !success, model.preferences.values.selectedPetID == selection {
                requestedPetID = model.pets.selectedID
                model.preferences.values.selectedPetID = model.pets.selectedID
            }
            render()
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(model: model, refreshPets: { [weak self] in self?.synchronizePets(force: true) },
                openCodex: { [weak self] in self?.openCodex() },
                refreshStatus: { [weak self] in self?.resynchronizeStatus() },
                reviewOnboarding: { [weak self] in self?.showOnboarding() },
                loginItem: loginItem, shortcut: shortcut)
        }
        settingsWindow?.show()
    }

    private func showOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = OnboardingWindowController(model: model, progress: onboardingProgress,
            refreshStatus: { [weak self] in self?.resynchronizeStatus() },
            openCodex: { [weak self] in self?.openCodex() })
        onboardingWindow?.show()
    }

    private func openCodex() {
        Task { [weak self] in
            guard let self else { return }
            if !(await launcher.open()) {
                model.launchFailed = true
                render()
                try? await Task.sleep(for: .seconds(3))
                model.launchFailed = false
                render()
            }
        }
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        let codexBundleID = CodexLauncher.bundleID
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == codexBundleID else { return }
                Task { @MainActor [weak self] in
                    guard let self, !self.suspended else { return }
                    self.synchronizePets(force: false)
                    await self.refresh()
                }
            })
        }
        let lifecycle: [(Notification.Name, SuspensionState.Reason, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ]
        for (name, reason, active) in lifecycle {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let wasSuspended = self.suspended
                    self.suspension.set(reason, active: active)
                    self.model.animationsPaused = self.suspended
                    if self.suspended {
                        self.sourceGeneration &+= 1
                        self.pollTask?.cancel()
                        self.panel?.hide()
                    } else if wasSuspended {
                        self.startPolling()
                    }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLanguage(); self?.render() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loginItem.refresh(); self?.refreshLanguage() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        })
    }

    private func diagnose() {
        let url = launcher.applicationURL
        let bundle = url.flatMap(Bundle.init(url:))
        let configuration = try? FeedConfiguration()
        let output: [String: Any] = [
            "applicationFound": url != nil,
            "applicationRunning": launcher.runningApplication != nil,
            "applicationVersion": bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "source": options.demo != nil ? "demo" : (options.statusFile != nil ? "explicit-file" : "local-session-history-v1"),
            "supportsUnread": false,
            "petParityVerified": false,
            "screenCount": NSScreen.screens.count,
            "localSourceConfiguration": configuration == nil ? "invalidConfiguration" : "configured",
            "usesHomeOverride": configuration?.usesHomeOverride ?? (ProcessInfo.processInfo.environment["CODEX_HOME"] != nil)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sourceGeneration &+= 1
        pollTask?.cancel()
        petTask?.cancel()
        model.preferences.onChange = nil
        shortcut.close()
        menuBar?.close()
        settingsWindow?.close()
        onboardingWindow?.close()
        panel?.close()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

@main
enum CodexIslandMain {
    @MainActor static func main() {
        let options: Options
        do { options = try Options(arguments: Array(CommandLine.arguments.dropFirst())) }
        catch { print("参数无效。使用 --help 查看用法。"); exit(2) }
        if options.help {
            print("""
            CodexIsland — macOS 状态岛
              --demo running|needsInput|blocked|ready|idle  明确标注的演示状态
              --status-file /absolute/snapshot.json       显式外部状态输入（非 Codex API）
              --diagnose                                 输出只读诊断并退出
              --render-previews /absolute/preview.png     渲染原生视图示意并退出
              --render-gallery /absolute/directory        渲染 4 状态 × 2 屏幕的公开示意图
              --mini                                     本次使用 Mini 模式；与演示/图库组合，不写正式偏好
              --check-resources                          只检查随包四语言与品牌资源，不创建界面或读取 Codex
            默认使用只读本机会话状态；当前不支持完成未读同步，未验证与宠物完全一致。
            """)
            return
        }
        if options.checkResources {
            let languages = ["en", "zh-Hans", "zh-Hant", "ja"]
            let valid = languages.allSatisfy { language in
                guard let bundle = L10n.localizedBundle(language) else { return false }
                let value = bundle.localizedString(forKey: "settings.window.title", value: nil, table: nil)
                return !value.isEmpty && value != "settings.window.title"
            }
            guard valid, AppResources.bundle.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand") != nil else {
                print("Packaged resource check failed")
                exit(1)
            }
            print("Packaged resources verified: 4 languages and brand icon")
            return
        }
        let app = NSApplication.shared
        if let url = options.galleryPath {
            do { try PreviewRenderer.renderGallery(to: url, displayMode: options.mini ? .mini : .full); print("Rendered 8 native previews") }
            catch { print("原生图库渲染失败"); exit(1) }
            return
        }
        if let url = options.renderPath {
            do { try PreviewRenderer.render(to: url); print("Rendered \(url.path)") }
            catch { print("原生视图渲染失败：\(error.localizedDescription)"); exit(1) }
            return
        }
        let delegate = AppDelegate(options: options)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
