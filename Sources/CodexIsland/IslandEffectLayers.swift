import AppKit
import IslandCore
import QuartzCore
import SwiftUI

// GPU-driven island edge effects. One layer tree per animated work state,
// built only when the state, palette or geometry changes; Core Animation
// performs the tweens on the render server, so the main thread stops
// rebuilding SwiftUI paths and strokes every frame.

private func cgColor(_ red: Double, _ green: Double, _ blue: Double, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

private func cgColor(islandHex hex: String) -> CGColor {
    let clean = IslandSettings.validatedHex(hex) ?? "66E6FF"
    func channel(_ offset: Int) -> CGFloat {
        let start = clean.index(clean.startIndex, offsetBy: offset)
        let chunk = String(clean[start..<clean.index(start, offsetBy: 2)])
        return CGFloat(UInt8(chunk, radix: 16) ?? 0) / 255
    }
    return CGColor(srgbRed: channel(0), green: channel(2), blue: channel(4), alpha: 1)
}

/// Edge effects (ring, comet orbit, pulses) for one animated work state.
@MainActor
final class IslandEffectView: NSView {
    private struct Configuration: Equatable {
        var state: WorkState
        var notched: Bool
        var mini: Bool
        var primary: String
        var secondary: String
        var tint: String
    }

    private var configuration: Configuration?
    private var lastSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = nil
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(state: WorkState, notched: Bool, mini: Bool, paused: Bool, settings: IslandSettings) {
        let tint: String
        switch state {
        case .running: tint = settings.neonPrimary
        case .needsInput: tint = settings.inputPulse
        case .blocked: tint = settings.errorPulse
        case .ready, .idle: tint = settings.neonSecondary
        }
        let next = Configuration(state: state, notched: notched, mini: mini,
                                 primary: settings.neonPrimary, secondary: settings.neonSecondary,
                                 tint: tint)
        if next != configuration || lastSize != bounds.size {
            configuration = next
            lastSize = bounds.size
            rebuild()
        }
        layer?.speed = paused ? 0 : 1
    }

    override func layout() {
        super.layout()
        if lastSize != bounds.size {
            lastSize = bounds.size
            rebuild()
        }
    }

    private func rebuild() {
        guard let configuration, layer != nil, !bounds.isEmpty, bounds.width > 1, bounds.height > 1 else { return }
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer?.speed = 1
        guard let path = islandPath() else { return }
        switch configuration.state {
        case .running: installRunning(path: path)
        case .needsInput, .blocked: installPulse(path: path)
        case .ready, .idle: installIdle(path: path)
        }
    }

    private func islandPath() -> CGPath? {
        guard let configuration else { return nil }
        let rect = CGRect(origin: .zero, size: bounds.size)
        return IslandShape(notched: configuration.notched, mini: configuration.mini,
                           outlineOnly: configuration.mini && configuration.notched)
            .path(in: rect)
            .cgPath
    }

    @discardableResult
    private func ring(path: CGPath, color: CGColor, lineWidth: CGFloat, opacity: Float,
                      shadow: CGFloat = 0) -> CAShapeLayer {
        let stroke = CAShapeLayer()
        stroke.path = path
        stroke.fillColor = nil
        stroke.strokeColor = color
        stroke.lineWidth = lineWidth
        stroke.opacity = opacity
        if shadow > 0 {
            stroke.shadowColor = color
            stroke.shadowOpacity = 0.7
            stroke.shadowRadius = shadow
            stroke.shadowOffset = .zero
        }
        layer?.addSublayer(stroke)
        return stroke
    }

    private func installRunning(path: CGPath) {
        guard let configuration else { return }
        let primary = cgColor(islandHex: configuration.primary)
        let secondary = cgColor(islandHex: configuration.secondary)
        let compactEdge = configuration.mini && configuration.notched
        // The rotating conic wash lives inside a silhouette mask, so rotating
        // it can never wobble the island silhouette itself.
        // The wash may only show as the thin ring the original SwiftUI drew;
        // a filled silhouette mask reads as a rotating beam across the island.
        let masked = CALayer()
        masked.frame = bounds
        let mask = CAShapeLayer()
        mask.path = path
        mask.fillColor = nil
        mask.strokeColor = CGColor(gray: 1, alpha: 1)
        mask.lineWidth = compactEdge ? 1.5 : 1.1
        mask.frame = bounds
        masked.mask = mask
        let wheel = CALayer()
        wheel.contents = Self.conicWheel(primary: primary, secondary: secondary, size: bounds.size)
        wheel.bounds = CGRect(origin: .zero, size: bounds.size)
        wheel.position = CGPoint(x: bounds.midX, y: bounds.midY)
        wheel.opacity = 0.65
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 6
        spin.repeatCount = Float.infinity
        wheel.add(spin, forKey: "spin")
        masked.addSublayer(wheel)
        layer?.addSublayer(masked)
        ring(path: path, color: CGColor(gray: 1, alpha: 0.09), lineWidth: 0.8, opacity: 1)
        installComet(path: path, color: primary, length: 0.19, thickness: 4, glow: 4, duration: 3, offset: 0)
        installComet(path: path, color: secondary, length: 0.13, thickness: compactEdge ? 2.2 : 1.4,
                     glow: 0, duration: 3, offset: 0.5)
        installComet(path: path, color: primary, length: 0.12, thickness: compactEdge ? 2.4 : 1.7,
                     glow: 0, duration: 3, offset: 0)
    }

    private func installComet(path: CGPath, color: CGColor, length: CGFloat, thickness: CGFloat,
                              glow: CGFloat, duration: Double, offset: Double) {
        let sprite = CALayer()
        sprite.contents = Self.cometSprite(color: color, glow: glow)
        let perimeter = 2 * (bounds.width + bounds.height)
        sprite.bounds = CGRect(x: 0, y: 0, width: length * perimeter, height: thickness)
        sprite.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let orbit = CAKeyframeAnimation(keyPath: "position")
        orbit.path = path
        orbit.calculationMode = .paced
        orbit.duration = duration
        orbit.rotationMode = .rotateAuto
        orbit.repeatCount = Float.infinity
        orbit.beginTime = CACurrentMediaTime() - offset * duration
        sprite.add(orbit, forKey: "orbit")
        layer?.addSublayer(sprite)
    }

    private func installPulse(path: CGPath) {
        guard let configuration else { return }
        let compactEdge = configuration.mini && configuration.notched
        let tint = cgColor(islandHex: configuration.tint)
        let haze = ring(path: path, color: tint, lineWidth: 5, opacity: 0.2, shadow: 5)
        haze.add(Self.breathing(0.2, 0.65, 1.9635), forKey: "pulse")
        let crisp = ring(path: path, color: tint, lineWidth: compactEdge ? 2.4 : 1.6, opacity: 0.45)
        crisp.add(Self.breathing(0.45, 1, 1.9635), forKey: "pulse")
    }

    private func installIdle(path: CGPath) {
        guard let configuration else { return }
        let compactEdge = configuration.mini && configuration.notched
        if configuration.state == .ready {
            ring(path: path, color: cgColor(0.40, 0.88, 0.65),
                 lineWidth: compactEdge ? 1.5 : 1, opacity: 0.6)
            return
        }
        let tint = cgColor(0.63, 0.73, 0.86)
        let faint = ring(path: path, color: tint, lineWidth: compactEdge ? 1.5 : 1, opacity: 0.13)
        faint.add(Self.breathing(0.13, 0.29, 5.236), forKey: "breath")
        installComet(path: path, color: tint.copy(alpha: 0.35) ?? tint, length: 0.10, thickness: 1.1,
                     glow: 0, duration: 12, offset: 0)
    }
}

extension IslandEffectView {
    /// Approximation of the SwiftUI conic sweep with four even color stops.
    static func conicWheel(primary: CGColor, secondary: CGColor, size: CGSize) -> CGImage? {
        let scale: CGFloat = 2
        let width = max(2, Int(size.width * scale)), height = max(2, Int(size.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let stops = [primary.copy(alpha: 0.5) ?? primary, primary, secondary, primary]
        let segments = 240
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = hypot(size.width, size.height)
        for index in 0..<segments {
            let t = CGFloat(index) / CGFloat(segments)
            let fraction = t * 3
            let low = min(Int(fraction), stops.count - 2)
            let mix = Self.mix(stops[low], stops[low + 1], fraction - CGFloat(low))
            context.setFillColor(mix)
            let begin = CGFloat(index) / CGFloat(segments) * 2 * .pi
            let end = CGFloat(index + 1) / CGFloat(segments) * 2 * .pi
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addLine(to: CGPoint(x: center.x + cos(begin) * radius, y: center.y + sin(begin) * radius))
            wedge.addLine(to: CGPoint(x: center.x + cos(end) * radius, y: center.y + sin(end) * radius))
            wedge.closeSubpath()
            context.addPath(wedge)
            context.fillPath()
        }
        return context.makeImage()
    }

    /// A soft comet segment: hot core plus a wider translucent halo, standing
    /// in for the SwiftUI blur that used to re-run every frame.
    static func cometSprite(color: CGColor, glow: CGFloat) -> CGImage? {
        let length: CGFloat = 160, thickness: CGFloat = 22, pad = glow * 2 + 8
        let scale = 2
        let width = Int((length + 2 * pad) * 2) * scale, height = Int((thickness + 2 * pad) * 2) * scale
        guard width > 2, height > 2,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        let center = (thickness + 2 * pad) / 2
        let core = CGRect(x: pad, y: center - thickness / 2, width: length, height: thickness)
        context.setFillColor(color)
        context.addPath(CGPath(roundedRect: core, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
        context.fillPath()
        if glow > 0 {
            context.setAlpha(0.4)
            let halo = core.insetBy(dx: -glow, dy: -glow)
            context.addPath(CGPath(roundedRect: halo, cornerWidth: thickness / 2 + glow, cornerHeight: thickness / 2 + glow, transform: nil))
            context.fillPath()
        }
        return context.makeImage()
    }

    /// Sine breathing represented by sampled opacity key frames.
    static func breathing(_ minimum: Float, _ maximum: Float, _ period: Double) -> CAAnimation {
        let steps = 8
        var values: [Float] = []
        for index in 0...steps {
            let t = Double(index) / Double(steps) * 2 * .pi
            values.append(minimum + (maximum - minimum) * Float((sin(t) + 1) / 2))
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values
        animation.keyTimes = Array(0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.duration = period
        animation.repeatCount = Float.infinity
        return animation
    }

    private static func mix(_ left: CGColor, _ right: CGColor, _ t: CGFloat) -> CGColor {
        func parts(_ color: CGColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let list = color.components ?? [CGFloat(0), 0, 0, 1]
            return (list[0], list[1], list[2], list.count > 3 ? list[3] : 1)
        }
        let (lr, lg, lb, la) = parts(left)
        let (rr, rg, rb, ra) = parts(right)
        return CGColor(red: lr + (rr - lr) * t, green: lg + (rg - lg) * t, blue: lb + (rb - lb) * t,
                       alpha: la + (ra - la) * t)
    }
}

// MARK: - glyph

/// Animated activity glyph: rotating symbol (running) or breathing dots (idle).
@MainActor
final class IslandGlyphEffectView: NSView {
    private var tint: CGColor?
    private var animated: WorkState?
    private var compact = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        rebuild()
    }

    func update(state: WorkState, compact: Bool, paused: Bool, settings: IslandSettings) {
        let color: CGColor?
        switch state {
        case .running: color = cgColor(islandHex: settings.neonPrimary)
        case .idle: color = cgColor(0.63, 0.73, 0.86)
        default: color = nil
        }
        if color != tint || animated != state || compact != self.compact {
            tint = color
            animated = color == nil ? nil : state
            self.compact = compact
            rebuild()
        }
        layer?.speed = paused ? 0 : 1
    }

    private func rebuild() {
        guard layer != nil, !bounds.isEmpty, let color = tint, let state = animated else { return }
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        let diameter = bounds.size
        let dot = compact ? 2.0 : 3.0
        let spacing = compact ? 2.0 : 3.0
        if state == .idle {
            for index in -1...1 {
                let particle = CALayer()
                particle.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
                particle.cornerRadius = dot / 2
                particle.backgroundColor = color
                particle.position = CGPoint(x: diameter.width / 2 + CGFloat(index) * (dot + spacing),
                                            y: diameter.height / 2)
                let animation = Self.dotBreathing()
                animation.timeOffset = Double(index + 1) * 0.4444
                particle.add(animation, forKey: "pulse")
                layer?.addSublayer(particle)
            }
            return
        }
        let background = CALayer()
        background.bounds = CGRect(origin: .zero, size: diameter)
        background.cornerRadius = diameter.width
        background.backgroundColor = color.copy(alpha: 0.04) ?? color
        layer?.addSublayer(background)
        let symbol = CALayer()
        symbol.contents = Self.symbolImage(state.symbol, color: color,
                                           size: compact ? 12 : 15)
        let size = compact ? 15.0 : 20.0
        symbol.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        symbol.position = CGPoint(x: diameter.width / 2, y: diameter.height / 2)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 3
        spin.repeatCount = Float.infinity
        symbol.add(spin, forKey: "spin")
        layer?.addSublayer(symbol)
    }

    static func dotBreathing() -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let values: [Float] = stride(from: 0, to: 2.0001, by: 0.25).map {
            0.25 + (0.89 - 0.25) * Float((sin($0 * .pi) + 1) / 2)
        }
        animation.values = values
        animation.keyTimes = stride(from: 0.0, to: 1.0001, by: 0.125)
            .map { NSNumber(value: $0) }
        animation.duration = 3.4907
        animation.repeatCount = Float.infinity
        return animation
    }

    static func symbolImage(_ name: String, color: CGColor, size: CGFloat) -> CGImage? {
        let parts = color.components ?? [CGFloat(0.63), 0.73, 0.86, 1]
        let nsColor = NSColor(red: parts[0], green: parts[1], blue: parts[2], alpha: 1)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) else { return nil }
        // Tinting runs through a preview NSImageView; template symbols only
        // adopt a foreground color from AppKit views, not plain image draws.
        let holder = NSImageView(image: symbol)
        holder.contentTintColor = nsColor
        let side = max(24.0, size + 10)
        holder.frame = NSRect(x: 0, y: 0, width: side, height: side)
        guard let rep = holder.bitmapImageRepForCachingDisplay(in: holder.bounds) else { return nil }
        rep.size = holder.bounds.size
        holder.cacheDisplay(in: holder.bounds, to: rep)
        return rep.cgImage
    }
}

struct IslandEdgeEffect: NSViewRepresentable {
    let state: WorkState
    let notched: Bool
    let mini: Bool
    let settings: IslandSettings

    func makeNSView(context: Context) -> IslandEffectView {
        IslandEffectView(frame: .zero)
    }

    func updateNSView(_ view: IslandEffectView, context: Context) {
        view.update(state: state, notched: notched, mini: mini, paused: false, settings: settings)
    }
}

struct IslandGlyphEffect: NSViewRepresentable {
    let state: WorkState
    let compact: Bool
    let settings: IslandSettings

    func makeNSView(context: Context) -> IslandGlyphEffectView {
        IslandGlyphEffectView(frame: .zero)
    }

    func updateNSView(_ view: IslandGlyphEffectView, context: Context) {
        view.update(state: state, compact: compact, paused: false, settings: settings)
    }
}
