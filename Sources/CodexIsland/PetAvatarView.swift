import SwiftUI
import ImageIO
import IslandCore

// Select the macOS 14-compatible wrapper explicitly. This CLT SDK also exposes
// a same-named State macro whose SwiftUIMacros plugin is not bundled with CLT.
private typealias PlaybackState<Value> = SwiftUI.State<Value>

/// Decode and downsample once; playback never reads or crops files per frame.
@MainActor
final class PetAtlas {
    private let frames: [PetMotion: [CGImage]]

    convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == 1536, height == 1872 || height == 2288,
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              sheet.width == 1536, sheet.height == 1872 || sheet.height == 2288 else { return nil }
        var decoded: [PetMotion: [CGImage]] = [:]
        for motion in PetMotion.allCases {
            var row: [CGImage] = []
            for index in 0..<motion.frameCount {
                let bounds = CGRect(x: index * 192, y: motion.row * 208, width: 192, height: 208)
                guard let cell = sheet.cropping(to: bounds),
                      let context = CGContext(data: nil, width: 96, height: 104, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                context.interpolationQuality = .high
                context.draw(cell, in: CGRect(x: 0, y: 0, width: 96, height: 104))
                guard let image = context.makeImage() else { return nil }
                row.append(image)
            }
            decoded[motion] = row
        }
        frames = decoded
    }

    func frame(motion: PetMotion, index: Int) -> CGImage? {
        guard let row = frames[motion], row.indices.contains(index) else { return nil }
        return row[index]
    }
}

struct PetAvatarView: View {
    let motion: PetMotion
    let paused: Bool
    var stageWidth: CGFloat = 48
    var atlas: PetAtlas?
    var petID = IslandSettings.fallbackPetID
    var timing = PetTimingProfile.compatibility
    @PlaybackState private var pose = PetPose(motion: .idle, index: 0)
    @PlaybackState private var positionX: Double?
    @PlaybackState private var walk: PetWalk?

    private var bounds: PetRoamingBounds { PetRoamingBounds(stageWidth: stageWidth) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || walk == nil)) { context in
            let sample = paused ? nil : walk?.sample(at: context.date)
            let current = paused ? PetPose(motion: motion, index: 0)
                : sample.map { PetPose(motion: $0.motion, index: $0.frameIndex) } ?? pose
            sprite(current)
                .offset(x: paused ? bounds.dockX : bounds.clamped(sample?.positionX ?? positionX ?? bounds.dockX))
                .frame(width: max(48, stageWidth), height: 52, alignment: .leading)
        }
        .frame(width: max(48, stageWidth), height: 52, alignment: .leading)
        .task(id: PetPlaybackRequest(motion: motion, paused: paused, maximumX: bounds.maximumX, petID: petID, timing: timing)) {
            // Freeze a cancelled route at its actual presentation position,
            // then start the next route from that point, never its old target.
            positionX = bounds.clamped(walk?.sample(at: Date()).positionX ?? positionX ?? bounds.dockX)
            walk = nil
            pose = PetPose(motion: .idle, index: 0)
            guard !paused else { positionX = bounds.dockX; return }
            if motion != .idle {
                guard await walkTo(bounds.dockX) else { return }
            }
            var firstIdleWalk = true
            while !Task.isCancelled {
                if motion == .idle && bounds.canRoam && (firstIdleWalk || Bool.random()) {
                    firstIdleWalk = false
                    let leg = PetRoamingLeg(bounds: bounds, startX: positionX ?? bounds.dockX,
                                            destinationFraction: Double.random(in: 0...1))
                    guard await walkTo(leg.destinationX) else { return }
                } else {
                    guard await playOnePass(motion) else { return }
                }
                guard !Task.isCancelled else { return }
                pose = PetPose(motion: .idle, index: 0)
                let rest = PetPlaybackPlan.restDurationMilliseconds(fraction: Double.random(in: 0...1), idleDuration: timing.duration(for: .idle))
                do { try await Task.sleep(for: .milliseconds(rest)) }
                catch { return }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sprite(_ current: PetPose) -> some View {
        Group {
            if let image = atlas?.frame(motion: current.motion, index: current.index) {
                Image(decorative: image, scale: 2, orientation: .up)
                    .resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "cat.fill").font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 48, height: 52)
        .transaction { $0.animation = nil }
    }

    private func walkTo(_ target: Double) async -> Bool {
        guard !Task.isCancelled else { return false }
        let now = Date()
        let start = bounds.clamped(walk?.sample(at: now).positionX ?? positionX ?? bounds.dockX)
        let destination = bounds.clamped(target)
        guard let route = PetWalk(startX: start, destinationX: destination, startedAt: now, timing: timing) else { return true }
        positionX = start
        walk = route
        do { try await Task.sleep(for: .milliseconds(route.durationMilliseconds)) }
        catch { return false }
        guard !Task.isCancelled else { return false }
        positionX = destination
        walk = nil
        pose = PetPose(motion: .idle, index: 0)
        return true
    }

    private func playOnePass(_ action: PetMotion) async -> Bool {
        for (index, duration) in timing.durations(for: action).enumerated() {
            guard !Task.isCancelled else { return false }
            pose = PetPose(motion: action, index: index)
            do { try await Task.sleep(for: .milliseconds(duration)) }
            catch { return false }
        }
        return true
    }
}

private struct PetPose: Equatable {
    let motion: PetMotion
    let index: Int
}

private struct PetPlaybackRequest: Equatable {
    let motion: PetMotion
    let paused: Bool
    let maximumX: Double
    let petID: String
    let timing: PetTimingProfile
}
