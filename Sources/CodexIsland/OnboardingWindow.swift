import AppKit
import Foundation
import SwiftUI

private typealias OnboardingViewState<Value> = SwiftUI.State<Value>

@MainActor
final class OnboardingProgress {
    enum Outcome: String { case completed, skipped }
    static let storageKey = "island.onboarding.v1"
    private let defaults: UserDefaults?
    private var outcome: Outcome?
    let permitsAutomaticPresentation: Bool

    init(defaults: UserDefaults? = nil, permitsAutomaticPresentation: Bool = false) {
        self.defaults = defaults
        self.permitsAutomaticPresentation = permitsAutomaticPresentation
        outcome = defaults?.string(forKey: Self.storageKey).flatMap(Outcome.init(rawValue:))
    }

    var shouldPresentAutomatically: Bool { permitsAutomaticPresentation && outcome == nil }
    func finish(_ result: Outcome) {
        outcome = result
        defaults?.set(result.rawValue, forKey: Self.storageKey)
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let progress: OnboardingProgress
    private var explicitlyFinished = false

    init(model: IslandModel, progress: OnboardingProgress, refreshStatus: @escaping @MainActor () -> Void,
         openCodex: @escaping @MainActor () -> Void) {
        self.progress = progress
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 530),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = String(localized: SetupText.guideTitle)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model,
            refreshStatus: refreshStatus, openCodex: openCodex, finish: { [weak self] result in
                self?.explicitlyFinished = true
                self?.progress.finish(result)
                self?.window.close()
            }))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func refreshLanguage() { window.title = String(localized: SetupText.guideTitle) }
    func close() { window.close() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !explicitlyFinished { progress.finish(.skipped) }
        return true
    }
}

private struct OnboardingView: View {
    let model: IslandModel
    let refreshStatus: @MainActor () -> Void
    let openCodex: @MainActor () -> Void
    let finish: @MainActor (OnboardingProgress.Outcome) -> Void
    @OnboardingViewState private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let icon = BrandAssets.colorIcon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 44, height: 44).accessibilityHidden(true)
                }
                Text(SetupText.guideTitle).font(.title2.weight(.semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0:
                        Text(SetupText.guideWelcome).font(.headline)
                        Text(SetupText.guideMenu)
                        Text(SetupText.guideStates).foregroundStyle(.secondary)
                    case 1:
                        Text(SetupText.guideConnection).font(.headline)
                        ConnectionStatusView(model: model, refreshStatus: refreshStatus, openCodex: openCodex)
                    default:
                        Text(SetupText.guidePrivacy).font(.headline)
                        Text(SetupText.guidePrivacyBody)
                        Text(SetupText.guideReturn).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button { finish(.skipped) } label: { Text(SetupText.skip) }
                Spacer()
                if step > 0 {
                    Button { step -= 1 } label: { Text(SetupText.back) }
                }
                Button {
                    if step == 2 { finish(.completed) } else { step += 1 }
                } label: { Text(step == 2 ? SetupText.finish : SetupText.next) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 530)
    }
}
