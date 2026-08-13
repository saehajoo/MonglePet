import AppKit
import XCTest
@testable import MonglePet

@MainActor
final class PetInstanceManagerTests: XCTestCase {
    func testSynchronizeCreatesAllContextsInDisplayOrder() throws {
        let settings = try twoInstanceSettings()
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }

        let result = try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .initialLoad(shouldRestorePosition: true)
        )

        XCTAssertTrue(result.restoredAllInstances)
        XCTAssertEqual(
            manager.activeInstanceIDs,
            settings.activePetInstances.map(\.instanceID)
        )
        XCTAssertEqual(
            manager.runtimeStatuses.map(\.instanceID),
            settings.activePetInstances.map(\.instanceID)
        )
        XCTAssertEqual(
            manager.selectedInstanceID,
            settings.selectedPetInstanceID
        )
        for instance in settings.activePetInstances {
            let context = try XCTUnwrap(contexts[instance.instanceID])
            XCTAssertTrue(manager.context(for: instance.instanceID) === context)
            XCTAssertEqual(context.replacePetCallCount, 1)
            XCTAssertEqual(context.appliedSettings.count, 1)
            XCTAssertEqual(
                context.appliedSettings[0].settings.selectedPetInstanceID,
                instance.instanceID
            )
            XCTAssertEqual(
                context.appliedSettings[0].settings.overlay,
                instance.overlay
            )
            XCTAssertEqual(
                context.appliedSettings[0].reason,
                .initialLoad(shouldRestorePosition: true)
            )
        }
    }

    func testSynchronizeRestoresFrontToBackDisplayOrder() throws {
        let settings = try twoInstanceSettings()
        var orderedFrontCalls: [UUID] = []
        let manager = PetInstanceManager { instanceID in
            FakePetRuntimeContext(
                instanceID: instanceID,
                onOrderFront: { orderedFrontCalls.append(instanceID) }
            )
        }

        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        XCTAssertEqual(
            orderedFrontCalls,
            settings.activePetInstances.reversed().map(\.instanceID)
        )
    }

    func testSynchronizeReusesUnchangedContextsWithoutReapplying() throws {
        let settings = try twoInstanceSettings()
        var createdContexts: [FakePetRuntimeContext] = []
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            createdContexts.append(context)
            return context
        }

        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )
        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        XCTAssertEqual(createdContexts.count, 2)
        for context in createdContexts {
            XCTAssertEqual(context.replacePetCallCount, 1)
            XCTAssertEqual(context.appliedSettings.count, 1)
            XCTAssertEqual(context.stopCallCount, 0)
        }
    }

    func testChangingSelectionKeepsEveryRuntime() throws {
        let firstSettings = try twoInstanceSettings()
        let secondID = try XCTUnwrap(
            firstSettings.activePetInstances.last?.instanceID
        )
        let secondSettings = AppSettings(
            selectedPetInstanceID: secondID,
            activePetInstances: firstSettings.activePetInstances,
            petBehaviorProfiles: firstSettings.petBehaviorProfiles
        )
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }

        try manager.synchronizeActiveRuntimes(
            settings: firstSettings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )
        try manager.synchronizeActiveRuntimes(
            settings: secondSettings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        XCTAssertEqual(manager.selectedInstanceID, secondID)
        XCTAssertEqual(
            manager.activeInstanceIDs,
            firstSettings.activePetInstances.map(\.instanceID)
        )
        for context in contexts.values {
            XCTAssertEqual(context.stopCallCount, 0)
            XCTAssertEqual(context.appliedSettings.count, 1)
        }
    }

    func testDesktopEnvironmentChangeIsBroadcastToEveryRuntime() throws {
        let settings = try twoInstanceSettings()
        var contexts: [FakePetRuntimeContext] = []
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts.append(context)
            return context
        }
        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        manager.desktopEnvironmentDidChange()

        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(
            contexts.map(\.desktopEnvironmentChangeCount),
            [1, 1]
        )
    }

    func testChangingOnePresentationOnlyReappliesMatchingRuntime() throws {
        let settings = try twoInstanceSettings()
        let secondID = try XCTUnwrap(
            settings.activePetInstances.last?.instanceID
        )
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }
        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        let updatedSettings = settings.replacingPresentation(
            .awake,
            for: secondID
        )
        try manager.synchronizeActiveRuntimes(
            settings: updatedSettings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        let firstContext = try XCTUnwrap(
            contexts[settings.selectedPetInstanceID]
        )
        let secondContext = try XCTUnwrap(contexts[secondID])
        XCTAssertEqual(firstContext.appliedSettings.count, 1)
        XCTAssertEqual(secondContext.appliedSettings.count, 2)
        XCTAssertTrue(firstContext.isAwake)
        XCTAssertTrue(secondContext.isAwake)
    }

    func testRemovingInstanceStopsOnlyItsRuntime() throws {
        let settings = try twoInstanceSettings()
        let removedID = try XCTUnwrap(
            settings.activePetInstances.last?.instanceID
        )
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }
        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )
        let remainingSettings = AppSettings(
            selectedPetInstanceID: settings.selectedPetInstanceID,
            activePetInstances: [settings.activePetInstances[0]],
            petBehaviorProfiles: settings.petBehaviorProfiles
        )

        try manager.synchronizeActiveRuntimes(
            settings: remainingSettings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        XCTAssertEqual(
            manager.activeInstanceIDs,
            [settings.selectedPetInstanceID]
        )
        XCTAssertEqual(contexts[removedID]?.stopCallCount, 1)
        XCTAssertEqual(
            contexts[settings.selectedPetInstanceID]?.stopCallCount,
            0
        )
    }

    func testUnavailablePetDoesNotBlockOtherRuntime() throws {
        let missingInstallationID = UUID()
        let settings = try twoInstanceSettings(
            secondPetKey: .installed(missingInstallationID)
        )
        let missingInstanceID = try XCTUnwrap(
            settings.activePetInstances.last?.instanceID
        )
        let manager = PetInstanceManager { instanceID in
            FakePetRuntimeContext(instanceID: instanceID)
        }

        let result = try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { petKey in
                petKey == .builtIn ? self.builtInItem() : nil
            },
            reason: .initialLoad(shouldRestorePosition: true)
        )

        XCTAssertEqual(result.unavailableInstanceIDs, [missingInstanceID])
        XCTAssertEqual(
            manager.activeInstanceIDs,
            [settings.selectedPetInstanceID]
        )
        XCTAssertNotNil(
            manager.context(for: settings.selectedPetInstanceID)
        )
        XCTAssertNil(manager.context(for: missingInstanceID))
    }

    func testSharedStateIsAppliedToEveryContext() throws {
        let settings = try twoInstanceSettings()
        let clock = ContinuousClock()
        let firstSnapshot = ActivitySnapshot(
            capturedAt: clock.now,
            idleDuration: .seconds(2),
            frontmostApplicationID: "com.example.Editor",
            isScreenLocked: false,
            isSystemSleeping: false
        )
        let secondSnapshot = ActivitySnapshot(
            capturedAt: clock.now,
            idleDuration: .seconds(3),
            frontmostApplicationID: nil,
            isScreenLocked: true,
            isSystemSleeping: false
        )
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }

        manager.setReduceMotion(true)
        manager.updateActivitySnapshot(firstSnapshot)
        try manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in self.builtInItem() },
            reason: .settingsChange
        )

        for context in contexts.values {
            XCTAssertEqual(context.reduceMotionValues, [true])
            XCTAssertEqual(context.activitySnapshots, [firstSnapshot])
        }

        manager.setReduceMotion(false)
        manager.updateActivitySnapshot(secondSnapshot)

        for context in contexts.values {
            XCTAssertEqual(context.reduceMotionValues, [true, false])
            XCTAssertEqual(
                context.activitySnapshots,
                [firstSnapshot, secondSnapshot]
            )
        }
    }

    func testMissingSelectedInstanceDoesNotCreateContext() throws {
        let validSettings = try twoInstanceSettings()
        let missingID = UUID()
        let invalidSettings = AppSettings(
            selectedPetInstanceID: missingID,
            activePetInstances: validSettings.activePetInstances,
            petBehaviorProfiles: validSettings.petBehaviorProfiles
        )
        var createdIDs: [UUID] = []
        let manager = PetInstanceManager { instanceID in
            createdIDs.append(instanceID)
            return FakePetRuntimeContext(instanceID: instanceID)
        }

        XCTAssertThrowsError(
            try manager.synchronizeActiveRuntimes(
                settings: invalidSettings,
                itemProvider: { _ in self.builtInItem() },
                reason: .settingsChange
            )
        ) { error in
            XCTAssertEqual(
                error as? PetInstanceManagerError,
                .missingSelectedInstance(missingID)
            )
        }
        XCTAssertTrue(createdIDs.isEmpty)
        XCTAssertTrue(manager.activeInstanceIDs.isEmpty)
    }

    private func twoInstanceSettings(
        secondPetKey: PetBehaviorKey = .builtIn
    ) throws -> AppSettings {
        let defaults = AppSettings.default
        let firstInstance = try XCTUnwrap(
            defaults.activePetInstances.first
        )
        let firstProfile = try XCTUnwrap(
            defaults.petBehaviorProfiles.first
        )
        let secondInstanceID = UUID(
            uuidString: "88888888-8888-8888-8888-888888888888"
        )!
        let secondProfileID = UUID(
            uuidString: "99999999-9999-9999-9999-999999999999"
        )!
        let secondProfile = BehaviorProfile(
            petKey: secondPetKey,
            mode: firstProfile.profile.mode,
            manualSequenceID: firstProfile.profile.manualSequenceID,
            sequences: firstProfile.profile.sequences,
            automaticRules: firstProfile.profile.automaticRules,
            movement: firstProfile.profile.movement,
            pettingMotionID: firstProfile.profile.pettingMotionID,
            speech: firstProfile.profile.speech
        )
        return AppSettings(
            selectedPetInstanceID: firstInstance.instanceID,
            activePetInstances: [
                firstInstance,
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: secondPetKey,
                    nickname: "두 번째",
                    presentation: .tuckedAway,
                    overlay: OverlaySettings(
                        screenIdentifier: "secondary-display",
                        originX: 640,
                        originY: 120,
                        width: 256,
                        clickThrough: true
                    ),
                    behaviorProfileID: secondProfileID,
                    displayOrder: 1
                )
            ],
            petBehaviorProfiles: [
                firstProfile,
                PetBehaviorProfileSettings(
                    profileID: secondProfileID,
                    profile: secondProfile
                )
            ]
        )
    }

    private func builtInItem() -> PetLibraryItem {
        let definition = BuiltInPet.mongleDefinition(
            atlasPixelSize: PixelSize(width: 1_024, height: 1_024)
        )
        return PetLibraryItem(
            selection: .builtIn,
            metadata: PetPackageMetadata(
                id: definition.id,
                displayName: definition.displayName,
                version: "내장",
                author: "MonglePet",
                description: nil
            ),
            previewURL: nil,
            definition: definition,
            installedPackage: nil
        )
    }
}

@MainActor
private final class FakePetRuntimeContext: PetRuntimeContextType {
    let instanceID: UUID
    private let onOrderFront: () -> Void
    private(set) var activeInstallationID: UUID?
    private(set) var isAwake = false
    private(set) var currentMotionID: String?
    private(set) var isMovementAllowed = false
    private(set) var latestMovementActivity = PetMovementActivity.stationary
    private(set) var currentSettings: AppSettings?
    private(set) var replacePetCallCount = 0
    private(set) var appliedSettings: [(
        settings: AppSettings,
        reason: PetOverlayApplicationReason
    )] = []
    private(set) var activitySnapshots: [ActivitySnapshot] = []
    private(set) var reduceMotionValues: [Bool] = []
    private(set) var stopCallCount = 0
    private(set) var desktopEnvironmentChangeCount = 0

    var runtimeStatus: PetRuntimeStatus {
        PetRuntimeStatus(
            instanceID: instanceID,
            isAwake: isAwake,
            currentBehaviorSequenceID: nil,
            currentPlaybackSequenceID: nil,
            currentSpeechText: nil,
            movementMode: currentSettings?.movementSettings.mode ?? .fixed,
            movementState: .inactive,
            movementActivity: latestMovementActivity,
            isPettingInteractionActive: false
        )
    }

    init(
        instanceID: UUID,
        onOrderFront: @escaping () -> Void = {}
    ) {
        self.instanceID = instanceID
        self.onOrderFront = onOrderFront
    }

    func replacePet(_ item: PetLibraryItem) throws {
        replacePetCallCount += 1
        activeInstallationID = item.selection.installationID
    }

    func apply(
        settings: AppSettings,
        reason: PetOverlayApplicationReason
    ) {
        currentSettings = settings
        isAwake = settings.lastUserPresentation == .awake
        appliedSettings.append((settings, reason))
    }

    func updateActivitySnapshot(_ snapshot: ActivitySnapshot) {
        activitySnapshots.append(snapshot)
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        reduceMotionValues.append(shouldReduceMotion)
    }

    func desktopEnvironmentDidChange() {
        desktopEnvironmentChangeCount += 1
    }

    func requestPettingInteraction() -> Bool {
        false
    }

    func orderFront() {
        onOrderFront()
    }

    func moveToVisibleFrame(_ visibleFrame: NSRect) {}

    func stop() {
        stopCallCount += 1
        isAwake = false
    }
}
