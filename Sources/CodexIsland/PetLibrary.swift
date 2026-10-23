import Foundation
import Observation
import CodexAssets
import DesktopFeed
import IslandCore

@MainActor @Observable
final class PetLibrary {
    var pets: [PetDescriptor] = []
    var selectedID = IslandSettings.defaultPetID
    var displayName = "未同步"
    var atlas: PetAtlas?
    var timing = PetTimingProfile.compatibility
    var isLoading = false
    var timingIsSynced = false
    var statusMessage = "使用内置兼容时长"
    @ObservationIgnored private let reader: CodexPetReader
    @ObservationIgnored private let home: URL?
    @ObservationIgnored private let cacheDirectory: URL

    init(home: URL? = nil, cacheDirectory: URL? = nil, reader: CodexPetReader = CodexPetReader()) {
        self.home = home ?? (try? FeedConfiguration().home)
        self.cacheDirectory = cacheDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Codex/Default/Cache/Cache_Data", isDirectory: true)
        self.reader = reader
    }

    func synchronize(applicationURL: URL?, selectedID requested: String, force: Bool) async -> Bool {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        let builtin: CodexPetCatalog?
        if let applicationURL { builtin = try? await reader.catalog(applicationURL: applicationURL, force: force) }
        else { builtin = nil }
        let custom: CustomPetCatalog?
        if let home { custom = await reader.customCatalog(home: home, cacheDirectory: cacheDirectory) }
        else { custom = nil }
        guard !Task.isCancelled else { return false }
        pets = (custom?.pets ?? []) + (builtin?.pets ?? [])
        if atlas != nil, requested == selectedID, !pets.contains(where: { $0.id == requested }) {
            statusMessage = "本次同步失败，保留上次宠物；请在 Codex 中查看后重新同步"
            return false
        }
        guard let chosen = pets.first(where: { $0.id == requested })
                ?? pets.first(where: { $0.id == custom?.preferredID })
                ?? pets.first(where: { $0.id == IslandSettings.defaultPetID }) ?? pets.first else {
            statusMessage = atlas == nil ? "未找到可用宠物，请在 Codex 中查看后重新同步" : "本次同步失败，保留上次宠物"
            return false
        }
        do {
            let nextAtlas = try await load(chosen)
            guard !Task.isCancelled else { return false }
            atlas = nextAtlas
            selectedID = chosen.id
            displayName = chosen.name
            if let builtin { timing = builtin.timing; timingIsSynced = true }
            let message = builtin.map { "动画时长已同步 · Codex \($0.version)" } ?? "使用兼容动画时长"
            statusMessage = message + (custom?.sourceUnavailable == true ? " · 部分自定义宠物缓存暂不可用" : "")
            return chosen.id == requested
        } catch {
            guard !Task.isCancelled else { return false }
            // Keep an already decoded pet on transient cache failures. On a
            // first launch, try the real built-in Codex pet instead of adding
            // a selectable placeholder to the catalog.
            if atlas == nil, chosen.id != IslandSettings.defaultPetID,
               let fallback = pets.first(where: { $0.id == IslandSettings.defaultPetID }),
               let decoded = try? await load(fallback), !Task.isCancelled {
                atlas = decoded; selectedID = fallback.id; displayName = fallback.name
                if let builtin { timing = builtin.timing; timingIsSynced = true }
            }
            statusMessage = atlas == nil ? "宠物素材暂不可用，请在 Codex 中查看后重新同步" : "本次同步失败，保留可用宠物与时长"
            return false
        }
    }

    private func load(_ pet: PetDescriptor) async throws -> PetAtlas {
        let data = try await reader.sprite(for: pet)
        try Task.checkCancellation()
        guard let decoded = PetAtlas(data: data) else { throw AssetError.incompatibleRenderer }
        return decoded
    }
}
