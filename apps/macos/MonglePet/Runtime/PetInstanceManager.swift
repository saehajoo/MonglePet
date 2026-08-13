import Foundation

nonisolated enum PetInstanceManagerError: Error, Equatable, Sendable {
    case missingSelectedInstance(UUID)
}

nonisolated struct PetInstanceSynchronizationResult: Equatable, Sendable {
    let unavailableInstanceIDs: [UUID]

    var restoredAllInstances: Bool {
        unavailableInstanceIDs.isEmpty
    }
}

@MainActor
final class PetInstanceManager {
    typealias ContextFactory = (UUID) -> any PetRuntimeContextType

    private let contextFactory: ContextFactory
    private var contextsByID: [UUID: any PetRuntimeContextType] = [:]
    private var orderedInstanceIDs: [UUID] = []
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
        orderedInstanceIDs
    }

    var runtimeStatuses: [PetRuntimeStatus] {
        orderedInstanceIDs.compactMap {
            contextsByID[$0]?.runtimeStatus
        }
    }

    func context(
        for instanceID: UUID
    ) -> (any PetRuntimeContextType)? {
        contextsByID[instanceID]
    }

    @discardableResult
    func synchronizeActiveRuntimes(
        settings: AppSettings,
        itemProvider: (PetBehaviorKey) -> PetLibraryItem?,
        reason: PetOverlayApplicationReason,
        reloadPetInstanceIDs: Set<UUID> = []
    ) throws -> PetInstanceSynchronizationResult {
        guard settings.selectedPetInstance != nil else {
            throw PetInstanceManagerError.missingSelectedInstance(
                settings.selectedPetInstanceID
            )
        }

        let orderedInstances = settings.activePetInstances.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
            return $0.displayOrder < $1.displayOrder
        }
        var synchronizedInstanceIDs: [UUID] = []
        var unavailableInstanceIDs: [UUID] = []

        for instance in orderedInstances {
            let instanceID = instance.instanceID
            guard
                let runtimeSettings = settings.runtimeSettings(for: instanceID),
                let item = itemProvider(instance.petKey)
            else {
                unavailableInstanceIDs.append(instanceID)
                contextsByID.removeValue(forKey: instanceID)?.stop()
                continue
            }

            let existingContext = contextsByID[instanceID]
            let context = existingContext ?? contextFactory(instanceID)
            if existingContext == nil {
                context.setReduceMotion(shouldReduceMotion)
            }

            let shouldReloadPet = existingContext == nil
                || reloadPetInstanceIDs.contains(instanceID)
                || context.activeInstallationID
                    != item.selection.installationID
            do {
                if shouldReloadPet {
                    try context.replacePet(item)
                }
                if existingContext == nil
                    || shouldReloadPet
                    || !Self.runtimeSettingsAreEquivalent(
                        context.currentSettings,
                        runtimeSettings
                    )
                    || reason.isInitialLoad {
                    let applicationReason: PetOverlayApplicationReason =
                        existingContext == nil && !reason.isInitialLoad
                            ? .initialLoad(shouldRestorePosition: true)
                            : reason
                    context.apply(
                        settings: runtimeSettings,
                        reason: applicationReason
                    )
                }
                if existingContext == nil, let latestActivitySnapshot {
                    context.updateActivitySnapshot(latestActivitySnapshot)
                }
            } catch {
                context.stop()
                contextsByID.removeValue(forKey: instanceID)
                unavailableInstanceIDs.append(instanceID)
                continue
            }

            contextsByID[instanceID] = context
            synchronizedInstanceIDs.append(instanceID)
        }

        let synchronizedIDSet = Set(synchronizedInstanceIDs)
        let retiredIDs = contextsByID.keys.filter {
            !synchronizedIDSet.contains($0)
        }
        for instanceID in retiredIDs {
            contextsByID.removeValue(forKey: instanceID)?.stop()
        }

        orderedInstanceIDs = synchronizedInstanceIDs
        if synchronizedIDSet.contains(settings.selectedPetInstanceID) {
            selectedInstanceID = settings.selectedPetInstanceID
        } else {
            selectedInstanceID = synchronizedInstanceIDs.first
        }
        restoreDisplayOrder()
        return PetInstanceSynchronizationResult(
            unavailableInstanceIDs: unavailableInstanceIDs
        )
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

    func desktopEnvironmentDidChange() {
        for context in contextsByID.values {
            context.desktopEnvironmentDidChange()
        }
    }

    func restoreDisplayOrder() {
        for instanceID in orderedInstanceIDs.reversed() {
            contextsByID[instanceID]?.orderFront()
        }
    }

    func stopAll() {
        for context in contextsByID.values {
            context.stop()
        }
        contextsByID.removeAll()
        orderedInstanceIDs.removeAll()
        selectedInstanceID = nil
        latestActivitySnapshot = nil
    }

    private static func runtimeSettingsAreEquivalent(
        _ currentSettings: AppSettings?,
        _ newSettings: AppSettings
    ) -> Bool {
        guard let currentSettings else {
            return false
        }
        return currentSettings.selectedPetInstanceID
                == newSettings.selectedPetInstanceID
            && currentSettings.selectedPetKey == newSettings.selectedPetKey
            && currentSettings.lastUserPresentation
                == newSettings.lastUserPresentation
            && currentSettings.overlay == newSettings.overlay
            && currentSettings.activeBehaviorProfile
                == newSettings.activeBehaviorProfile
    }
}
