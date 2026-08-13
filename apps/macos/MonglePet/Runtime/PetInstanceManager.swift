import Foundation

nonisolated enum PetInstanceManagerError: Error, Equatable, Sendable {
    case missingSelectedInstance(UUID)
}

@MainActor
final class PetInstanceManager {
    typealias ContextFactory = (UUID) -> any PetRuntimeContextType

    private let contextFactory: ContextFactory
    private var contextsByID: [UUID: any PetRuntimeContextType] = [:]
    private var latestActivitySnapshot: ActivitySnapshot?
    private var shouldReduceMotion = false
    private(set) var selectedInstanceID: UUID?

    init(contextFactory: @escaping ContextFactory) {
        self.contextFactory = contextFactory
    }

    var selectedContext: (any PetRuntimeContextType)? {
        selectedInstanceID.flatMap { contextsByID[$0] }
    }

    var activeInstanceIDs: [UUID] {
        Array(contextsByID.keys)
    }

    func context(
        for instanceID: UUID
    ) -> (any PetRuntimeContextType)? {
        contextsByID[instanceID]
    }

    /// Phase 3 keeps the existing single-overlay product behavior while moving
    /// ownership behind an instance-keyed manager. Phase 4 will synchronize all
    /// active instances instead of retiring non-selected contexts here.
    func synchronizeSelectedRuntime(
        settings: AppSettings,
        item: PetLibraryItem,
        reason: PetOverlayApplicationReason,
        reloadPet: Bool
    ) throws {
        let instanceID = settings.selectedPetInstanceID
        guard let runtimeSettings = settings.runtimeSettings(
            for: instanceID
        ) else {
            throw PetInstanceManagerError.missingSelectedInstance(instanceID)
        }

        let existingContext = contextsByID[instanceID]
        let context = existingContext ?? contextFactory(instanceID)
        context.setReduceMotion(shouldReduceMotion)

        do {
            if reloadPet
                || context.activeInstallationID
                    != item.selection.installationID {
                try context.replacePet(item)
            }
            context.apply(settings: runtimeSettings, reason: reason)
            if existingContext == nil, let latestActivitySnapshot {
                context.updateActivitySnapshot(latestActivitySnapshot)
            }
        } catch {
            if existingContext == nil {
                context.stop()
            }
            throw error
        }

        contextsByID[instanceID] = context
        selectedInstanceID = instanceID
        retireContexts(except: instanceID)
    }

    func updateActivitySnapshot(_ snapshot: ActivitySnapshot) {
        latestActivitySnapshot = snapshot
        for context in contextsByID.values {
            context.updateActivitySnapshot(snapshot)
        }
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        self.shouldReduceMotion = shouldReduceMotion
        for context in contextsByID.values {
            context.setReduceMotion(shouldReduceMotion)
        }
    }

    func stopAll() {
        for context in contextsByID.values {
            context.stop()
        }
        contextsByID.removeAll()
        selectedInstanceID = nil
        latestActivitySnapshot = nil
    }

    private func retireContexts(except retainedInstanceID: UUID) {
        let retiredIDs = contextsByID.keys.filter {
            $0 != retainedInstanceID
        }
        for instanceID in retiredIDs {
            contextsByID.removeValue(forKey: instanceID)?.stop()
        }
    }
}
