import Foundation
import Observation
import CodexAssets
import DesktopFeed
import IslandCore

@MainActor @Observable
final class PetLibrary {
    var pets: [PetDescriptor] = []
    var selectedID = IslandSettings.defaultPetID
    private var selectedDisplayName: String?
    var displayName: String { selectedDisplayName ?? L10n.text("未同步") }
    var atlas: PetAtlas?
    var timing = PetTimingProfile.compatibility
    var isLoading = false
    var timingIsSynced = false
    private enum StatusMessage {
        case source(String), synchronized(String, partial: Bool), compatibility(partial: Bool)
    }
    private var status: StatusMessage = .source("使用内置兼容时长")
    var statusMessage: String {
        switch status {
        case .source(let source): L10n.text(source)
        case .synchronized(let version, let partial): L10n.format(partial ? "pet.synced_partial" : "pet.synced", version)
        case .compatibility(let partial): L10n.value(partial ? "pet.compatibility_partial" : "pet.compatibility_animation")
        }
    }
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
            status = .source("本次同步失败，保留上次宠物；请在 Codex 中查看后重新同步")
            return false
        }
        guard let chosen = pets.first(where: { $0.id == requested })
                ?? pets.first(where: { $0.id == custom?.preferredID })
                ?? pets.first(where: { $0.id == IslandSettings.defaultPetID }) ?? pets.first else {
            status = .source(atlas == nil ? "未找到可用宠物，请在 Codex 中查看后重新同步" : "本次同步失败，保留上次宠物")
            return false
        }
        do {
            let nextAtlas = try await load(chosen)
            guard !Task.isCancelled else { return false }
            atlas = nextAtlas
            selectedID = chosen.id
            selectedDisplayName = chosen.name
            if let builtin { timing = builtin.timing; timingIsSynced = true }
            let partial = custom?.sourceUnavailable == true
            status = builtin.map { .synchronized($0.version, partial: partial) } ?? .compatibility(partial: partial)
            return chosen.id == requested
        } catch {
            guard !Task.isCancelled else { return false }
            // Keep an already decoded pet on transient cache failures. On a
            // first launch, try the real built-in Codex pet instead of adding
            // a selectable placeholder to the catalog.
            if atlas == nil, chosen.id != IslandSettings.defaultPetID,
               let fallback = pets.first(where: { $0.id == IslandSettings.defaultPetID }),
               let decoded = try? await load(fallback), !Task.isCancelled {
                atlas = decoded; selectedID = fallback.id; selectedDisplayName = fallback.name
                if let builtin { timing = builtin.timing; timingIsSynced = true }
            }
            status = .source(atlas == nil ? "宠物素材暂不可用，请在 Codex 中查看后重新同步" : "本次同步失败，保留可用宠物与时长")
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
