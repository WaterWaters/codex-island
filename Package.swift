// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexIsland",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexIsland", targets: ["CodexIsland"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "IslandCore"),
        .target(name: "DesktopFeed", dependencies: ["IslandCore", "CSQLite"]),
        .target(name: "CodexAssets", dependencies: ["IslandCore"]),
        .executableTarget(name: "CodexIsland", dependencies: ["IslandCore", "DesktopFeed", "CodexAssets"],
                          resources: [.copy("Resources/Brand"), .process("Resources/Localization")]),
        .executableTarget(name: "CodexIslandProbe", dependencies: ["DesktopFeed"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
        .testTarget(name: "DesktopFeedTests", dependencies: ["DesktopFeed", "CSQLite"]),
        .testTarget(name: "CodexAssetsTests", dependencies: ["CodexAssets", "IslandCore"]),
        .testTarget(name: "IslandUITests", dependencies: ["CodexIsland"])
    ]
)
