import AppKit

/// The settings icon keeps its full-color artwork. The menu icon has its own
/// optical design and is drawn at the destination's native backing scale.
@MainActor
enum BrandAssets {
    static let colorIcon: NSImage? = {
        guard let url = AppResources.bundle.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }()

    static let menuBarIcon: NSImage? = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            BrandMenuMark.draw(in: rect)
        }
        // Do not let a cached bitmap from one display get resampled on another.
        image.cacheMode = .never
        // The requested white variant must retain its color, including on a
        // light desktop. A system template would recolor it automatically.
        image.isTemplate = false
        image.accessibilityDescription = "Codex Island"
        return image
    }()
}

/// Designed in points at its actual 18pt size: a generous terminal cutout,
/// clear cat ears and one wave. No miniature body, tail or layered ripples.
private enum BrandMenuMark {
    static func draw(in rect: CGRect) -> Bool {
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 18, y: -rect.height / 18)
        context.setFillColor(CGColor(gray: 1, alpha: 1))

        let face = CGMutablePath()
        face.move(to: CGPoint(x: 1.5, y: 2))
        face.addQuadCurve(to: CGPoint(x: 2.6, y: 1.5), control: CGPoint(x: 1.5, y: 1))
        face.addLine(to: CGPoint(x: 6, y: 4))
        face.addQuadCurve(to: CGPoint(x: 12, y: 4), control: CGPoint(x: 9, y: 3))
        face.addLine(to: CGPoint(x: 15.4, y: 1.5))
        face.addQuadCurve(to: CGPoint(x: 16.5, y: 2), control: CGPoint(x: 16.5, y: 1))
        face.addLine(to: CGPoint(x: 16.5, y: 8.5))
        face.addCurve(to: CGPoint(x: 12, y: 13), control1: CGPoint(x: 16.5, y: 11.5), control2: CGPoint(x: 15, y: 13))
        face.addLine(to: CGPoint(x: 6, y: 13))
        face.addCurve(to: CGPoint(x: 1.5, y: 8.5), control1: CGPoint(x: 3, y: 13), control2: CGPoint(x: 1.5, y: 11.5))
        face.closeSubpath()

        face.move(to: CGPoint(x: 4.3, y: 5.5))
        face.addLines(between: [CGPoint(x: 7.6, y: 8), CGPoint(x: 4.3, y: 10.5),
                               CGPoint(x: 3.4, y: 9.3), CGPoint(x: 5.2, y: 8), CGPoint(x: 3.4, y: 6.7)])
        face.closeSubpath()
        face.addRoundedRect(in: CGRect(x: 9, y: 9, width: 4, height: 1.5), cornerWidth: 0.3, cornerHeight: 0.3)
        context.addPath(face)
        context.drawPath(using: .eoFill)

        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 2, y: 16))
        wave.addCurve(to: CGPoint(x: 5.5, y: 15.8), control1: CGPoint(x: 3.2, y: 15), control2: CGPoint(x: 4.3, y: 15))
        wave.addCurve(to: CGPoint(x: 9, y: 16), control1: CGPoint(x: 6.7, y: 16.6), control2: CGPoint(x: 7.8, y: 16.8))
        wave.addCurve(to: CGPoint(x: 12.5, y: 15.8), control1: CGPoint(x: 10.2, y: 15.2), control2: CGPoint(x: 11.3, y: 15))
        wave.addCurve(to: CGPoint(x: 16, y: 16), control1: CGPoint(x: 13.7, y: 16.6), control2: CGPoint(x: 14.8, y: 16.8))
        context.addPath(wave)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.strokePath()
        return true
    }
}
