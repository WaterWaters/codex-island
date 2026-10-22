import Foundation

public struct PetTimingProfile: Codable, Equatable, Sendable {
    public let sourceVersion: String
    public let frames: [String: [Int]]
    public static let compatibility = try! Self(sourceVersion: PetMotion.timingSourceVersion,
        frames: Dictionary(uniqueKeysWithValues: PetMotion.allCases.map { ($0.rawValue, $0.frameDurationsMilliseconds) }))

    public init(sourceVersion: String, frames: [String: [Int]]) throws {
        guard !sourceVersion.isEmpty, PetMotion.allCases.allSatisfy({ motion in
            guard let values = frames[motion.rawValue] else { return false }
            return values.count == motion.frameCount && values.allSatisfy { (1...60_000).contains($0) }
        }) else { throw TimingError.incompatible }
        self.sourceVersion = sourceVersion
        self.frames = frames
    }

    public func durations(for motion: PetMotion) -> [Int] { frames[motion.rawValue] ?? motion.frameDurationsMilliseconds }
    public func duration(for motion: PetMotion) -> Int { durations(for: motion).reduce(0, +) }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sourceVersion: container.decode(String.self, forKey: .sourceVersion),
                      frames: container.decode([String: [Int]].self, forKey: .frames))
    }
    public enum TimingError: Error { case incompatible }
}
