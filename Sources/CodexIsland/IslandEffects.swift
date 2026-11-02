import SwiftUI
import IslandCore

enum IslandPalette {
    static func tint(for state: WorkState, settings: IslandSettings = IslandSettings()) -> Color {
        switch state {
        case .running: Color(islandHex: settings.neonPrimary)
        case .needsInput: Color(islandHex: settings.inputPulse)
        case .blocked: Color(islandHex: settings.errorPulse)
        case .ready: Color(red: 0.40, green: 0.88, blue: 0.65)
        case .idle: Color(red: 0.63, green: 0.73, blue: 0.86)
        }
    }
}

/// A trimmed path moves along the island itself, rather than rotating a
/// rectangular layer around the screen. Static appearances render the fixed
/// `t = 2.4` composition without any timeline; animated states hand the
/// tweens to Core Animation layers (see `IslandEffectView`).
struct IslandOutline: View {
    let state: WorkState
    let notched: Bool
    let paused: Bool
    var settings = IslandSettings()
    var mini = false

    private var staticOutline: Bool {
        paused || !settings.animationsEnabled
            || settings.appearancePreset == .quiet || settings.appearancePreset == .highContrast
            || state == .ready
    }

    var body: some View {
        if staticOutline {
            IslandStaticOutline(state: state, notched: notched, mini: mini, settings: settings)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            IslandEdgeEffect(state: state, notched: notched, mini: mini, settings: settings)
                .padding(mini && notched ? 1 : 2)
                .clipShape(IslandShape(notched: notched, mini: mini, outlineOnly: mini && notched))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The historical static outline pixels, guarded branch for branch.
private struct IslandStaticOutline: View {
    let state: WorkState
    let notched: Bool
    let mini: Bool
    let settings: IslandSettings

    var body: some View {
        let time: Double = 2.4
        let shape = IslandShape(notched: notched, mini: mini, outlineOnly: mini && notched)
        let tint = IslandPalette.tint(for: state, settings: settings)
        let primary = Color(islandHex: settings.neonPrimary)
        let secondary = Color(islandHex: settings.neonSecondary)
        let pulse = (sin(time * (state == .idle ? 1.2 : 3.2)) + 1) / 2
        ZStack {
            if settings.appearancePreset == .highContrast {
                // A continuous, unblurred outline remains legible against
                // both dark and light desktops. Status also has a glyph.
                shape.stroke(.white, lineWidth: mini && notched ? 2.4 : 2)
                shape.stroke(tint, lineWidth: 1)
            } else if settings.appearancePreset == .quiet {
                shape.stroke(tint.opacity(state == .idle ? 0.35 : 0.75), lineWidth: mini && notched ? 1.6 : 1.1)
            } else if state == .running {
                shape.stroke(.white.opacity(0.09), lineWidth: 0.8)
                shape.stroke(AngularGradient(colors: [primary.opacity(0.5), primary, secondary, primary.opacity(0.5)],
                                             center: .center, angle: .degrees(time.truncatingRemainder(dividingBy: 6) * 60)),
                             lineWidth: mini && notched ? 1.5 : 1.1).opacity(0.65)
                OrbitSegment(notched: notched, mini: mini, phase: time / 3.0, length: 0.19)
                    .stroke(primary, style: StrokeStyle(lineWidth: 4, lineCap: .round)).blur(radius: 4).opacity(0.7)
                OrbitSegment(notched: notched, mini: mini, phase: time / 3.0, length: 0.12)
                    .stroke(primary, style: StrokeStyle(lineWidth: mini && notched ? 2.4 : 1.7, lineCap: .round))
                OrbitSegment(notched: notched, mini: mini, phase: time / 3.0 + 0.5, length: 0.13)
                    .stroke(secondary.opacity(0.85), style: StrokeStyle(lineWidth: mini && notched ? 2.2 : 1.4, lineCap: .round))
            } else if state == .needsInput || state == .blocked {
                shape.stroke(tint, lineWidth: 5).blur(radius: 5).opacity(0.2 + pulse * 0.45)
                shape.stroke(tint.opacity(0.45 + pulse * 0.55), lineWidth: mini && notched ? 2.4 : 1.6)
            } else {
                shape.stroke(tint.opacity(state == .idle ? 0.13 + pulse * 0.16 : 0.6), lineWidth: mini && notched ? 1.5 : 1)
                if state == .idle {
                    OrbitSegment(notched: notched, mini: mini, phase: time / 12, length: 0.10)
                        .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                }
            }
        }
        .padding(mini && notched ? 1 : 2)
        .clipShape(shape)
    }
}

private struct OrbitSegment: Shape {
    let notched: Bool
    let mini: Bool
    let phase: Double
    let length: Double

    func path(in rect: CGRect) -> Path {
        let path = IslandShape(notched: notched, mini: mini, outlineOnly: mini && notched).path(in: rect)
        let start = phase.truncatingRemainder(dividingBy: 1)
        let end = start + length
        var segment = path.trimmedPath(from: start, to: min(1, end))
        if end > 1 { segment.addPath(path.trimmedPath(from: 0, to: end - 1)) }
        return segment
    }
}

struct IslandActivityGlyph: View {
    let state: WorkState
    let paused: Bool
    var settings = IslandSettings()
    var compact = false

    private var diameter: CGFloat { compact ? 20 : 28 }

    private var animatedGlyph: Bool {
        !paused && settings.animationsEnabled
            && settings.appearancePreset != .quiet && settings.appearancePreset != .highContrast
            && (state == .idle || state == .running)
    }

    var body: some View {
        Group {
            if animatedGlyph {
                IslandGlyphEffect(state: state, compact: compact, settings: settings)
                    .allowsHitTesting(false)
            } else {
                IslandStaticGlyph(state: state, settings: settings, compact: compact)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The historical static glyph pixels, one fixed composition.
private struct IslandStaticGlyph: View {
    let state: WorkState
    let settings: IslandSettings
    let compact: Bool

    private var diameter: CGFloat { compact ? 20 : 28 }

    var body: some View {
        let tint = IslandPalette.tint(for: state, settings: settings)
        Group {
            if state == .idle {
                HStack(spacing: compact ? 2 : 3) {
                    ForEach(0..<3) { index in
                        // The historical tick ran at t = 2.4 in this branch.
                        Circle().fill(tint).frame(width: compact ? 2 : 3, height: compact ? 2 : 3)
                            .opacity(0.25 + (sin(2.4 * 1.8 - Double(index) * 0.8) + 1) * 0.32)
                    }
                }
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .frame(width: diameter, height: diameter)
        .background(tint.opacity(state == .running ? 0.04 : 0.07), in: .circle)
    }
}
