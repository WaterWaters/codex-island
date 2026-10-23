import AppKit
import SwiftUI

private typealias ConnectionViewState<Value> = SwiftUI.State<Value>

struct ConnectionStatusView: View {
    let model: IslandModel
    let refreshStatus: @MainActor () -> Void
    let openCodex: @MainActor () -> Void

    var body: some View {
        let presentation = model.connectionPresentation
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(presentation.title).font(.headline) } icon: {
                Image(systemName: presentation.symbol).accessibilityHidden(true)
            }
            Text(presentation.nextStep).fixedSize(horizontal: false, vertical: true)
            if model.sourceFailureReason == .invalidConfiguration {
                Text(SetupText.resource("connection.invalid_configuration.next", "CODEX_HOME 配置无效。请使用存在的绝对目录，修正应用的启动环境后重新打开 Codex Island；不会静默改用其他目录。"))
                    .foregroundStyle(.secondary)
            }
            if model.launchFailed {
                Text(SetupText.resource("connection.open_failed", "未能打开 Codex，请从应用程序中手动打开后重试。"))
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading) { actions }
            }
            if model.isLocalFeed {
                Text(SetupText.scope).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        if model.connectionPresentation.offersOpenCodex {
            Button(action: openCodex) { Text(SetupText.openCodex) }
        }
        Button(action: refreshStatus) { Text(SetupText.resynchronize) }
    }
}

struct ConnectionSettingsView: View {
    let model: IslandModel
    let refreshStatus: @MainActor () -> Void
    let openCodex: @MainActor () -> Void
    @ConnectionViewState private var copySucceeded: Bool?

    var body: some View {
        Form {
            Section {
                ConnectionStatusView(model: model, refreshStatus: refreshStatus, openCodex: openCodex)
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
