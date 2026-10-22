import Foundation
import Observation
import IslandCore

@MainActor @Observable
final class IslandPreferences {
    static let storageKey = "island.settings.v1"
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    private var storedValues: IslandSettings
    var values: IslandSettings {
        get { storedValues }
        set {
            let clean = newValue.sanitized()
            guard clean != storedValues else { return }
            storedValues = clean
            if let data = try? JSONEncoder().encode(clean) { defaults?.set(data, forKey: Self.storageKey) }
            onChange?()
        }
    }

    // Tests and offscreen renderers use an isolated in-memory configuration.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey), let decoded = try? JSONDecoder().decode(IslandSettings.self, from: data) {
            storedValues = decoded.sanitized()
        } else { storedValues = IslandSettings() }
    }
    func reset() { values = IslandSettings() }
}
