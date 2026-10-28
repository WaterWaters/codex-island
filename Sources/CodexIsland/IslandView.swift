import SwiftUI
import IslandCore

struct IslandShape: Shape {
    var notched: Bool
    var mini = false
    var outlineOnly = false

    func path(in rect: CGRect) -> Path {
        if !notched { return Path(roundedRect: rect, cornerRadius: rect.height / 2) }
        if mini {
            let radius = min(CGFloat(10), rect.height / 2)
            var p = Path()
            if outlineOnly { p.move(to: CGPoint(x: rect.maxX, y: rect.minY)) }
            else {
                p.move(to: rect.origin)
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: rect.origin)
            if !outlineOnly { p.closeSubpath() }
            return p
        }
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
    private var mini: Bool { geometry.displayMode == .mini }
    private var shape: IslandShape { IslandShape(notched: geometry.hasNotch, mini: mini) }

    var body: some View {
        Button(action: openCodex) {
            ZStack {
                (model.isHovered ? Color(white: 0.035) : .black)
                    .zIndex(0)
                IslandOutline(state: model.effectState, notched: geometry.hasNotch,
                              paused: reduceMotion || model.motionPaused, settings: model.preferences.values, mini: mini)
                    .zIndex(0)
                if mini {
                    if !geometry.hasNotch {
                        IslandActivityGlyph(state: model.effectState, paused: reduceMotion || model.motionPaused,
                                            settings: model.preferences.values, compact: true)
                    }
                } else {
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
            }
            .frame(width: geometry.width, height: geometry.height)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(model.accessibilityDescription)
        .accessibilityHint(L10n.format("island.switch_hint_provider", model.providerName))
        .help(mini ? model.accessibilityDescription : L10n.format("island.local_help_provider", model.providerName))
        .onHover { model.setHovered($0) }
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

/// The same silhouette drives rendering and WindowServer hit testing.
enum IslandHitRegion {
    static func contains(_ point: CGPoint, geometry: IslandGeometry) -> Bool {
        let rect = CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height)
        guard IslandShape(notched: geometry.hasNotch, mini: geometry.displayMode == .mini)
            .path(in: rect).contains(point) else { return false }
        return !(geometry.hasNotch && abs(point.x - rect.midX) < geometry.notchWidth / 2
                 && point.y < geometry.notchHeight)
    }
}
