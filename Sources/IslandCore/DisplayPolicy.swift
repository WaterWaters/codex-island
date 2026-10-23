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
                             backingScale: Double) -> CGRect {
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        func aligned(_ value: Double) -> Double { (value * scale).rounded() / scale }
        return CGRect(x: aligned(screenFrame.midX - geometry.width / 2),
                      y: aligned((geometry.hasNotch ? screenFrame.maxY : visibleFrame.maxY - 8) - geometry.height),
                      width: aligned(geometry.width), height: aligned(geometry.height))
    }
}
