import AppKit
import IslandCore
import SwiftUI

private typealias ConnectionViewState<Value> = SwiftUI.State<Value>

struct ConnectionStatusView: View {
    let model: IslandModel
    let provider: SourceProvider
    let refreshStatus: @MainActor () -> Void
    let openApplication: @MainActor (SourceProvider) -> Void

    var body: some View {
        let presentation = model.connectionPresentation(for: provider)
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(presentation.title).font(.headline) } icon: {
                Image(systemName: presentation.symbol).accessibilityHidden(true)
            }
            Text(presentation.nextStep).fixedSize(horizontal: false, vertical: true)
            if model.status(for: provider).failureReason == .invalidConfiguration {
                Text(provider == .codex
                     ? SetupText.resource("connection.invalid_configuration.next", "CODEX_HOME 配置无效。请使用存在的绝对目录，修正应用的启动环境后重新打开 Codex Island；不会静默改用其他目录。")
                     : SetupText.resource("connection.claude.invalid_configuration.next", "CLAUDE_CONFIG_DIR 配置无效。请使用存在的绝对目录，修正应用的启动环境后重新打开 Codex Island；不会静默改用其他目录。"))
                    .foregroundStyle(.secondary)
            }
            if provider == .codex, model.launchFailed {
                Text(SetupText.resource("connection.open_failed", "未能打开 Codex，请从应用程序中手动打开后重试。"))
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions(presentation) }
                VStack(alignment: .leading) { actions(presentation) }
            }
            if model.isLocalFeed {
                Text(provider == .codex ? SetupText.scope : SetupText.claudeScope)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ presentation: ConnectionPresentation) -> some View {
        if presentation.offersOpenApplication {
            Button { openApplication(provider) } label: { Text(presentation.openLabel) }
        }
        Button(action: refreshStatus) { Text(SetupText.resynchronize) }
    }
}

struct ConnectionSettingsView: View {
    let model: IslandModel
    let refreshStatus: @MainActor () -> Void
    let openApplication: @MainActor (SourceProvider) -> Void
    @ConnectionViewState private var copySucceeded: Bool?

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section(L10n.value("settings.source_section")) {
                Picker(L10n.value("settings.source"), selection: $preferences.values.sourceMode) {
                    Text(L10n.value("settings.source_codex")).tag(StatusSourceMode.codex)
                    Text(L10n.value("settings.source_claude")).tag(StatusSourceMode.claude)
                    Text(L10n.value("settings.source_rotate")).tag(StatusSourceMode.rotate)
                }
                Text(L10n.value("settings.source_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ConnectionStatusView(model: model, provider: .codex,
                                     refreshStatus: refreshStatus, openApplication: openApplication)
            }
            Section {
                ConnectionStatusView(model: model, provider: .claude,
                                     refreshStatus: refreshStatus, openApplication: openApplication)
            }
            Section {
                Button {
                    guard let output = model.privacyDiagnostics.json() else { copySucceeded = false; return }
                    NSPasteboard.general.clearContents()
                    copySucceeded = NSPasteboard.general.setString(output, forType: .string)
                } label: { Text(SetupText.copyDiagnostics) }
                if let copySucceeded {
                    Text(copySucceeded ? SetupText.copied : SetupText.copyFailed).font(.caption)
                }
                Text(SetupText.diagnosticPrivacy).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
