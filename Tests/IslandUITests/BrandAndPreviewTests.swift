import AppKit
import Foundation
import ImageIO
import IslandCore
import Metal
import Testing
@testable import CodexIsland

@MainActor @Test func brandIconsHaveColorAndAWhiteTransparentMenuMark() throws {
    let color = try #require(BrandAssets.colorIcon)
    let original = try #require(color.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bitmap = NSBitmapImageRep(cgImage: original)
    let hasColor = stride(from: 0, to: bitmap.pixelsWide, by: 32).contains { x in
        stride(from: 0, to: bitmap.pixelsHigh, by: 32).contains { y in
            guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return pixel.alphaComponent > 0.9 && pixel.blueComponent - pixel.redComponent > 0.3
        }
    }
    #expect(hasColor)
    #expect(!color.isTemplate)

    let menu = try #require(BrandAssets.menuBarIcon)
    #expect(menu.size == NSSize(width: 18, height: 18))
    #expect(!menu.isTemplate)
    let pixels = NSBitmapImageRep(cgImage: try #require(menu.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    var opaque = 0
    var transparent = 0
    for y in 0..<pixels.pixelsHigh {
        for x in 0..<pixels.pixelsWide {
            let pixel = try #require(pixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            if pixel.alphaComponent < 0.01 { transparent += 1 }
            if pixel.alphaComponent > 0.9 {
                opaque += 1
                #expect(pixel.redComponent > 0.99 && pixel.greenComponent > 0.99 && pixel.blueComponent > 0.99)
            }
        }
    }
    let area = pixels.pixelsWide * pixels.pixelsHigh
    #expect(opaque > area / 5)
    #expect(transparent > area / 4) // No opaque app-icon tile in the menu.
}

// SwiftUI blur/shadow rasterization needs Metal. Headless Intel runners can
// compile the app but have no GPU; keep model coverage independent below.
@MainActor @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil,
                         "Native preview rendering requires a Metal device"))
func galleryRendersEightDistinctSyntheticNativeViews() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-gallery-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try PreviewRenderer.renderGallery(to: directory)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(files.count == 8)
    var images = Set<Data>()
    for file in files {
        let data = try Data(contentsOf: file)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width >= 1200 && image.height >= 550)
        images.insert(data)
    }
    #expect(images.count == 8)
}

@MainActor @Test func galleryModelsUseOnlySyntheticPausedStates() {
    for state in [WorkState.running, .needsInput, .blocked, .idle] {
        let model = PreviewRenderer.sampleModel(state: state)
        #expect(model.isDemo && model.animationsPaused)
        #expect(model.sessionTitle == "构建 Codex Island")
        #expect(model.pets.atlas == nil)
        #expect(model.state == state)
    }
}
