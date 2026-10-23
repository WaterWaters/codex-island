import AppKit
import CoreGraphics
import IslandCore

struct DisplayOption: Identifiable, Equatable {
    let id: String
    let name: String
    let isMain: Bool
}

@MainActor
enum DisplayCatalog {
    static var current: [DisplayOption] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let displayID = number(for: screen), let id = stableID(for: displayID) else { return nil }
            return DisplayOption(id: id, name: screen.localizedName, isMain: displayID == mainID)
        }.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.id < rhs.id
        }
    }

    static func screen(preferredID: String?) -> NSScreen? {
        let screens = NSScreen.screens
        let mainNumber = CGMainDisplayID()
        let identified = screens.compactMap { screen -> (String, NSScreen)? in
            guard let number = number(for: screen), let id = stableID(for: number) else { return nil }
            return (id, screen)
        }
        if let preferredID, let screen = identified.first(where: { $0.0 == preferredID })?.1 { return screen }
        // A system display without a UUID remains usable as the default, but
        // cannot accidentally become a persisted, index-based user selection.
        if let main = screens.first(where: { number(for: $0) == mainNumber }) { return main }
        if let selection = DisplaySelectionPolicy.selectedID(preferredID: nil,
                                                              availableIDs: identified.map(\.0), mainID: nil) {
            return identified.first(where: { $0.0 == selection })?.1
        }
        return nil
    }

    private static func number(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func stableID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
