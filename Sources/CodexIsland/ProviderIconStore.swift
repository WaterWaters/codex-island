import AppKit
import IslandCore
import os

/// Provider glyphs rendered once, in memory, from this machine's installed
/// apps. Nothing vendor-branded is bundled or written to disk. The preferred
/// sources are the bundles' borderless artwork; the app icon (whose squircle
/// plate reads as a border on the dark island) is only a fallback. A missing
/// app or a failed render returns nil and callers keep the stock SF-symbol
/// visuals.
@MainActor
enum ProviderIconStore {
    private enum Resolution: Sendable {
        case ready(CGImage)
        case miss

        var image: CGImage? {
            if case .ready(let value) = self { return value }
            return nil
        }
    }

    private struct CacheKey: Equatable, Hashable {
        let provider: SourceProvider
        let side: Int
        let tint: Int64?
    }

    private static var glyphCache: [CacheKey: Resolution] = [:]
    /// Only a fresh overall miss is retried; installs appearing later in the
    /// session land within one minute.
    private static let retryInterval: TimeInterval = 60
    private static var lastMiss: Date?
    /// Last resolution outcome per provider, for aggregate diagnostics only
    /// (`bundled` / `local` / `app` / `appicon` / `miss`; no paths). Provider
    /// names are not session content; they are the source switch labels.
    private static var diagnosticTrace: [SourceProvider: String] = [:]
    private static let logger = Logger(subsystem: "dev.water.codex-island",
                                       category: "ProviderIcons")

    static var diagnosticSummary: String? {
        let entries = SourceProvider.allCases.compactMap { provider -> String? in
            diagnosticTrace[provider].map { "\(provider.displayName)=\($0)" }
        }
        return entries.isEmpty ? nil : entries.joined(separator: ",")
    }

    private static func record(_ provider: SourceProvider, _ outcome: String) {
        guard diagnosticTrace[provider] != outcome else { return }
        diagnosticTrace[provider] = outcome
        logger.notice("glyph source: \(provider.displayName, privacy: .public) -> \(outcome, privacy: .public)")
        dumpTrace()
    }

    /// Env-gated side channel for local debugging (`/tmp` by design); never
    /// written in normal runs and never packaged content.
    private static func dumpTrace() {
        guard ProcessInfo.processInfo.environment["CODEX_ISLAND_GLYPH_DEBUG"] != nil else { return }
        let object: [String: Any] = ["outcomes": diagnosticTrace.map { "\($0.key.displayName)=\($0.value)" }.sorted(),
                                     "t": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        let url = URL(fileURLWithPath: "/tmp/codexisland-glyph-state.json")
        try? data.write(to: url, options: .atomic)
    }

    private static let bundleIdentifiers: [SourceProvider: String] = [
        .codex: CodexLauncher.bundleID,
        .claude: ClaudeLauncher.bundleID
    ]

    /// `tint` recolors monochrome (template) artwork, e.g. the Claude tray
    /// silhouette; colored art like the Codex cloud passes through as-is.
    static func glyph(_ provider: SourceProvider, side: CGFloat, tint: CGColor?) -> CGImage? {
        let key = CacheKey(provider: provider, side: Int(side.rounded()), tint: tintKey(tint))
        if let cached = glyphCache[key] {
            if let image = cached.image { return image }
            if let previous = lastMiss, Date().timeIntervalSince(previous) < retryInterval {
                return nil
            }
        }
        let resolved = resolve(provider: provider, side: side, tint: tint)
        glyphCache[key] = resolved
        if resolved.image == nil { lastMiss = Date() }
        return resolved.image
    }

    private static func resolve(provider: SourceProvider, side: CGFloat, tint: CGColor?) -> Resolution {
        // Pre-bake the display bitmap at 2x the requested side.
        let pixels = CGFloat(max(1, Int(side * 2)))
        if let resolved = candidate(provider: provider, tint: tint) {
            if let rendered = render(resolved, side: pixels) {
                return .ready(rendered)
            }
            record(provider, "render-miss")
            return .miss
        }
        guard let appURL = appURL(for: provider),
              let image = bundleIcon(of: appURL) ?? workspaceIcon(of: appURL),
              let source = toCGImage(image),
              let rendered = render(source, side: pixels) else {
            record(provider, "miss")
            return .miss
        }
        record(provider, "appicon")
        return .ready(rendered)
    }

    /// Borderless preferred sources per provider. Order: the shipped vector
    /// copies of official artwork (bundled, see ProviderIcons/PROVENANCE.md),
    /// then the user's local (git-ignored) overrides, then the installed
    /// app's own borderless resources, then the plain app icon.
    private static func candidate(provider: SourceProvider, tint: CGColor?) -> CGImage? {
        if let bundled = bundledVector(provider: provider) {
            record(provider, "bundled")
            return bundled
        }
        if let local = localVector(provider: provider) {
            record(provider, "local")
            return local
        }
        switch provider {
        case .claude:
            // The tray template is the bare starburst logo, monochrome by
            // design and tintable.
            let names = ["TrayIconTemplate@3x.png", "TrayIconTemplate@2x.png", "TrayIconTemplate.png"]
            for name in names {
                guard let appURL = appURL(for: .claude),
                      let image = toCGImage(NSImage(contentsOf: appURL.appendingPathComponent(
                          "Contents/Resources/\(name)"))) else { continue }
                switch recolored(image, tint: tint) {
                case .ready(let tinted): return tinted
                case .miss: continue
                }
            }
            return nil
        case .codex:
            return codexCloudMark()
        }
    }

    /// `Brand/ProviderIcons/<asset>.svg` — shipped vector copies of the
    /// official marks, loaded from the packaged resources bundle. The codex
    /// source shows the ChatGPT knot (OpenAI's mark) per user direction
    /// (2026-11-03), not the cloud artwork.
    private static func bundledVector(provider: SourceProvider) -> CGImage? {
        let name: String
        switch provider {
        case .claude: name = "claude"
        case .codex: name = "openai"
        }
        guard let url = AppResources.bundle.url(
            forResource: name, withExtension: "svg", subdirectory: "Brand/ProviderIcons"),
              let vector = NSImage(contentsOf: url) else {
            return nil
        }
        return toCGImage(vector)
    }

    /// `local/provider-logos/<provider>.svg` — user-supplied vector copies of
    /// official artwork (downloaded, never committed), resolved from the
    /// packaged app's location: `<repo-root>/build/<app>.app` sibling `local/`.
    private static func localVector(provider: SourceProvider) -> CGImage? {
        let name: String
        switch provider {
        case .claude: name = "claude.svg"
        case .codex: name = "codex.svg"
        }
        let bundle = Bundle.main.bundleURL
        let repoRoot = bundle.deletingLastPathComponent().deletingLastPathComponent()
        guard let vector = NSImage(contentsOf: repoRoot
            .appendingPathComponent("local/provider-logos/\(name)")) else {
            return nil
        }
        return toCGImage(vector)
    }

    private static func appURL(for provider: SourceProvider) -> URL? {
        let identifier = bundleIdentifiers[provider] ?? ""
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    private static func bundleIcon(of appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        guard let name, !name.isEmpty else { return nil }
        let base = appURL.appendingPathComponent("Contents/Resources")
        for suffix in ["", ".icns"] {
            let url = base.appendingPathComponent(name + suffix, isDirectory: false)
            if let icon = NSImage(contentsOf: url) { return icon }
        }
        return nil
    }

    private static func workspaceIcon(of appURL: URL) -> NSImage? {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    // MARK: - codex cloud extraction

    private static func codexCloudMark() -> CGImage? {
        // Probed fractions of the shipped 1024×1024 asset: the saturated
        // cloud bbox is 208..816 on both dark and light variants; 202px crop
        // margins keep the mark whole.
        let margin = CGFloat(202.0 / 1024.0)
        let cropSize = CGFloat(620.0 / 1024.0)
        guard let appURL = appURL(for: .codex),
              let source = toCGImage(NSImage(contentsOf: appURL.appendingPathComponent(
                  "Contents/Resources/icon-codex-dark-color.png"))) else {
            return nil
        }
        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        let cropRect = CGRect(x: sourceWidth * margin, y: sourceHeight * margin,
                              width: sourceWidth * cropSize, height: sourceHeight * cropSize)
        guard let cropped = source.cropping(to: cropRect) else { return nil }
        return dropNeutralDark(cropped)
    }

    /// Neutral dark pixels are plate remnants sitting in the crop's corners;
    /// the colored cloud and the white terminal marks both stay.
    private static func dropNeutralDark(_ source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        guard let rep = bitmap(width: width, height: height),
              let context = NSGraphicsContext(bitmapImageRep: rep),
              let data = rep.bitmapData else { return nil }
        context.cgContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in 0..<(width * height) {
            let offset = index * 4
            let red = data[offset], green = data[offset + 1], blue = data[offset + 2]
            let brightest = max(red, max(green, blue))
            let spread = brightest - min(red, min(green, blue))
            if spread < 30 && brightest < 90 {
                data[offset + 3] = 0
            }
        }
        return rep.cgImage
    }

    // MARK: - monochrome tint

    private static func recolored(_ source: CGImage, tint: CGColor?) -> Resolution {
        guard let tint, let rep = bitmap(width: source.width, height: source.height),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return .ready(source)
        }
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.cgContext.setFillColor(tint)
        context.cgContext.fill(rect)
        context.cgContext.setBlendMode(.destinationIn)
        context.cgContext.draw(source, in: rect)
        guard let rendered = rep.cgImage else { return .ready(source) }
        return .ready(rendered)
    }

    // MARK: - rendering helpers

    private static func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        // Default premultiplied backing: `.alphaNonpremultiplied` makes
        // NSGraphicsContext(bitmapImageRep:) return nil on this OS, which
        // killed the whole render chain (2026-11-03 probe). Premultiplication
        // leaves fully-opaque and fully-clear pixels byte-identical, so the
        // neutral-dark mask below is unaffected.
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    private static func toCGImage(_ image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        if let direct = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return direct
        }
        // Vector-backed images (SVG) can refuse a direct CGImage; rasterize
        // instead so the caller always receives bitmap pixels.
        let side = max(64, Int(max(image.size.width, image.size.height).rounded()))
        guard let rep = bitmap(width: side, height: side),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero,
                   operation: .sourceOver, fraction: 1, respectFlipped: false,
                   hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// Centers and fits the source into the square target without distortion.
    private static func render(_ image: CGImage, side: CGFloat) -> CGImage? {
        guard let rep = bitmap(width: Int(side), height: Int(side)),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        context.cgContext.interpolationQuality = .high
        let target = drawRect(for: image, side: side)
        context.cgContext.draw(image, in: target)
        return rep.cgImage
    }

    private static func drawRect(for image: CGImage, side: CGFloat) -> NSRect {
        let scale = min(side / CGFloat(image.width), side / CGFloat(image.height))
        let fittedWidth = CGFloat(image.width) * scale
        let fittedHeight = CGFloat(image.height) * scale
        return NSRect(x: (side - fittedWidth) / 2, y: (side - fittedHeight) / 2,
                      width: fittedWidth, height: fittedHeight)
    }

    private static func tintKey(_ color: CGColor?) -> Int64? {
        guard let color, let parts = color.components, parts.count >= 3 else { return nil }
        var value: Int64 = 0
        for index in 0..<3 {
            let scaled = Int64((parts[index] * 255).rounded())
            value = (value << 8) + max(0, min(255, scaled))
        }
        return value
    }
}
