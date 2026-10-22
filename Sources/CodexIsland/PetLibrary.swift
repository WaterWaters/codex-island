import Foundation
import Observation
import CodexAssets
import IslandCore

@MainActor @Observable
final class PetLibrary {
    var pets: [PetDescriptor] = [.systemIcon]
    var selectedID = IslandSettings.fallbackPetID
    var displayName = "系统图标"
    var atlas: PetAtlas?
    var timing = PetTimingProfile.compatibility
    var isLoading = false
    var timingIsSynced = false
    var statusMessage = "使用内置兼容时长"
    @ObservationIgnored private let reader = CodexPetReader()

    func synchronize(applicationURL: URL?, selectedID requested: String, force: Bool) async -> Bool {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        if requested == IslandSettings.fallbackPetID {
            atlas = nil
            selectedID = requested
            displayName = "系统图标"
        }
        do {
            guard let applicationURL else { throw AssetError.missingMember }
            let catalog = try await reader.catalog(applicationURL: applicationURL, force: force)
            guard !Task.isCancelled else { return false }
            pets = [.systemIcon] + catalog.pets
            guard let pet = pets.first(where: { $0.id == requested }) else { throw AssetError.missingMember }
            let nextAtlas: PetAtlas?
            if pet.id == IslandSettings.fallbackPetID { nextAtlas = nil }
            else {
                let data = try await reader.sprite(for: pet)
                guard !Task.isCancelled else { return false }
                guard let decoded = PetAtlas(data: data) else { throw AssetError.incompatibleRenderer }
                nextAtlas = decoded
            }
            guard !Task.isCancelled else { return false }
            atlas = nextAtlas
            selectedID = pet.id
            displayName = pet.name
            timing = catalog.timing
            timingIsSynced = true
            statusMessage = "动画时长已同步 · Codex \(catalog.version)"
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            statusMessage = timingIsSynced ? "本次同步失败，保留上次宠物与时长" : "未能同步，使用系统图标与兼容时长"
            return requested == IslandSettings.fallbackPetID
        }
    }
}
