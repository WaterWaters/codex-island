import DesktopFeed
import Foundation

@main
enum FeedProbe {
    static func main() async {
        let feed = LocalSessionFeed()
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.isEmpty || (args.count == 2 && args[0] == "--watch" && Int(args[1]).map({ 1...600 ~= $0 }) == true) else {
            print("Usage: CodexIslandProbe [--watch 1...600]")
            exit(2)
        }
        let count = args.isEmpty ? 1 : Int(args[1])!
        for _ in 0..<count {
            do {
                let observation = try await feed.read()
                let states = observation.snapshot.activities.reduce(into: [String: Int]()) { $0[$1.rawValue, default: 0] += 1 }
                let output: [String: Any] = ["source": observation.snapshot.source, "trackedThreads": observation.trackedThreads,
                    "activeThreads": observation.activeThreads, "caughtUp": observation.caughtUp,
                    "supportsUnread": observation.supportsUnread, "petParityVerified": false, "states": states,
                    "activity": observation.snapshot.activity?.rawValue ?? "unknown",
                    "hasSessionTitle": observation.snapshot.displaySessionTitle != nil]
                let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch {
                print("{\"error\":\"\((error as? FeedError)?.rawValue ?? "unavailable")\",\"petParityVerified\":false}")
                exit(1)
            }
            if count > 1 { try? await Task.sleep(for: .seconds(1)) }
        }
    }
}
