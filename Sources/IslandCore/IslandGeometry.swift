import Foundation

public struct IslandGeometry: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let notchWidth: Double
    public let notchHeight: Double
    public let hasNotch: Bool

    public static func layout(screenWidth: Double, notchWidth: Double, notchHeight: Double,
                              expanded: Bool, contentHeight: Double? = nil) -> Self {
        let notched = notchWidth > 0 && notchHeight > 0
        let available = max(0, screenWidth - 32)
        let width = min(available, notched ? max(notchWidth + 112, expanded ? 368 : 0) : (expanded ? 360 : 288))
        let configured = contentHeight.map { $0.isFinite ? min(140, max(60, $0)) : 72 }
        let height = notched ? notchHeight + (expanded ? configured ?? 68 : 8) : (expanded ? configured ?? 72 : 44)
        return Self(width: width, height: height, notchWidth: notched ? notchWidth : 0,
                    notchHeight: notched ? notchHeight : 0, hasNotch: notched)
    }
}
