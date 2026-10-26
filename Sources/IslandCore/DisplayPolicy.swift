import Foundation
import CoreGraphics

/// Display identity is independent of the order supplied by AppKit.
public enum DisplaySelectionPolicy {
    public static func selectedID(preferredID: String?, availableIDs: [String], mainID: String?) -> String? {
        if let preferredID, availableIDs.contains(preferredID) { return preferredID }
        if let mainID, availableIDs.contains(mainID) { return mainID }
        return availableIDs.sorted().first
    }
}

public enum DisplayPlacementPolicy {
    /// AppKit's global coordinate system can include negative origins. Sizes are
    /// already in points; backing scale is used only to align to device pixels.
    public static func frame(screenFrame: CGRect, visibleFrame: CGRect, geometry: IslandGeometry,
                             backingScale: Double, notchCenterX: Double? = nil) -> CGRect {
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        func aligned(_ value: Double) -> Double { (value * scale).rounded() / scale }
        let center = geometry.hasNotch ? notchCenterX.flatMap { $0.isFinite ? $0 : nil } ?? screenFrame.midX : screenFrame.midX
        let top = geometry.hasNotch || geometry.displayMode == .mini ? screenFrame.maxY : visibleFrame.maxY - 8
        return CGRect(x: aligned(center - geometry.width / 2),
                      y: aligned(top - geometry.height),
                      width: aligned(geometry.width), height: aligned(geometry.height))
    }
}

/// NSScreen reports the two auxiliary areas in global screen coordinates.
/// Derive the housing gap rather than guessing a Mac model or pixel size.
public struct DisplayCutout: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let centerX: Double

    public static func resolve(screenFrame: CGRect, safeAreaTop: Double,
                               leftArea: CGRect?, rightArea: CGRect?) -> Self? {
        guard let leftArea, let rightArea,
              screenFrame.width.isFinite, screenFrame.height.isFinite,
              safeAreaTop.isFinite, safeAreaTop > 0, safeAreaTop < screenFrame.height / 2,
              leftArea.maxX.isFinite, rightArea.minX.isFinite,
              leftArea.width > 0, rightArea.width > 0,
              leftArea.minX >= screenFrame.minX, rightArea.maxX <= screenFrame.maxX,
              leftArea.maxY == screenFrame.maxY, rightArea.maxY == screenFrame.maxY else { return nil }
        let width = rightArea.minX - leftArea.maxX
        guard width > 0, width < screenFrame.width / 2 else { return nil }
        return Self(width: width, height: safeAreaTop, centerX: (leftArea.maxX + rightArea.minX) / 2)
    }
}
