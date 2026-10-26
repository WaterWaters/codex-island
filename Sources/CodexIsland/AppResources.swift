import Foundation

/// A packaged app keeps its reviewed resources in Contents/Resources. Older
/// SwiftPM accessors search beside the app or in the original build directory.
@MainActor
enum AppResources {
    static let bundle = resolve(in: .main) { .module }

    static func resolve(in application: Bundle, development: () -> Bundle) -> Bundle {
        if let resources = application.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("CodexIsland_CodexIsland.bundle")) {
            return packaged
        }
        return development()
    }
}
