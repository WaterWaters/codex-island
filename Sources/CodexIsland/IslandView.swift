import SwiftUI
import IslandCore

struct IslandShape: Shape {
    var notched: Bool

    func path(in rect: CGRect) -> Path {
        if !notched { return Path(roundedRect: rect, cornerRadius: rect.height / 2) }
        let top: CGFloat = 10
        let bottom = min(CGFloat(22), rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width - top, y: top), control: CGPoint(x: rect.width - top, y: 0))
        p.addLine(to: CGPoint(x: rect.width - top, y: rect.height - bottom))
        p.addQuadCurve(to: CGPoint(x: rect.width - top - bottom, y: rect.height), control: CGPoint(x: rect.width - top, y: rect.height))
        p.addLine(to: CGPoint(x: top + bottom, y: rect.height))
        p.addQuadCurve(to: CGPoint(x: top, y: rect.height - bottom), control: CGPoint(x: top, y: rect.height))
        p.addLine(to: CGPoint(x: top, y: top))
        p.addQuadCurve(to: .zero, control: CGPoint(x: top, y: 0))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    let model: IslandModel
    let geometry: IslandGeometry
    let openCodex: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        IslandPalette.tint(for: model.effectState, settings: model.preferences.values)
    }
    private var highContrast: Bool { model.preferences.values.appearancePreset == .highContrast }

    var body: some View {
        Button(action: openCodex) {
            ZStack {
                (model.isHovered ? Color(white: 0.035) : .black)
                    .zIndex(0)
                IslandOutline(state: model.effectState, notched: geometry.hasNotch,
                              paused: reduceMotion || model.motionPaused, settings: model.preferences.values)
                    .zIndex(0)
                PetAvatarView(motion: model.petMotion,
                              paused: reduceMotion || model.motionPaused || (model.connection != .connected && !model.approvalUIIsPending),
                              stageWidth: geometry.width - (geometry.hasNotch ? 56 : 44),
                              atlas: model.pets.atlas, petID: model.pets.selectedID, timing: model.pets.timing)
                    .padding(.top, geometry.hasNotch ? geometry.notchHeight : 0)
                    .zIndex(1)
                statusRow
                    .padding(.horizontal, geometry.hasNotch ? 28 : 22)
                    .padding(.top, geometry.hasNotch ? geometry.notchHeight : 0)
                    .shadow(color: .black, radius: 2)
                    .shadow(color: .black, radius: 1)
                    .zIndex(2)
            }
            .frame(width: geometry.width, height: geometry.height)
            .clipShape(IslandShape(notched: geometry.hasNotch))
            .contentShape(IslandShape(notched: geometry.hasNotch))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(model.accessibilityDescription)
        .accessibilityHint(L10n.text("切换到 Codex 应用"))
        .help(L10n.text(model.isLocalFeed ? "打开 Codex · 本机会话状态，完整宠物同步仍未验收" : "打开 Codex"))
        .onHover { model.isHovered = $0 }
        .animation(reduceMotion || model.motionPaused ? nil : .easeInOut(duration: 0.16), value: model.isHovered)
    }

    private var statusRow: some View {
        HStack(spacing: 13) {
            IslandActivityGlyph(state: model.effectState, paused: reduceMotion || model.motionPaused, settings: model.preferences.values)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: model.title).font(.system(size: 13, weight: .semibold))
                    .truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(verbatim: model.displayDetail).font(.system(size: 11))
                        .foregroundStyle(highContrast ? .white : model.effectState == .needsInput || model.effectState == .blocked ? tint : .white.opacity(0.55))
                    Spacer(minLength: 0)
                    if model.connection == .connected && !model.approvalUIIsPending && model.summary.runningCount > 1 {
                        Text(verbatim: L10n.count("island.running", model.summary.runningCount)).font(.system(size: 9))
                            .foregroundStyle(.white.opacity(highContrast ? 1 : 0.32))
                    }
                }
            }
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
    }

}
