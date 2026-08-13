import AppKit
import XCTest
@testable import MonglePet

@MainActor
final class PetInstanceManagerTests: XCTestCase {
    func testSynchronizeCreatesContextKeyedBySelectedInstance() throws {
        let settings = try twoInstanceSettings()
        var contexts: [UUID: FakePetRuntimeContext] = [:]
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            contexts[instanceID] = context
            return context
        }

        try manager.synchronizeSelectedRuntime(
            settings: settings,
            item: builtInItem(),
            reason: .initialLoad(shouldRestorePosition: true),
            reloadPet: true
        )

        let selectedID = settings.selectedPetInstanceID
        let context = try XCTUnwrap(contexts[selectedID])
        XCTAssertEqual(manager.selectedInstanceID, selectedID)
        XCTAssertEqual(Set(manager.activeInstanceIDs), [selectedID])
        XCTAssertTrue(manager.context(for: selectedID) === context)
        XCTAssertEqual(context.replacePetCallCount, 1)
        XCTAssertEqual(context.appliedSettings.count, 1)
        XCTAssertEqual(
            context.appliedSettings[0].settings.selectedPetInstanceID,
            selectedID
        )
        XCTAssertEqual(
            context.appliedSettings[0].reason,
            .initialLoad(shouldRestorePosition: true)
        )
    }

    func testSynchronizeReusesContextWithoutReloadingUnchangedPet() throws {
        let settings = try twoInstanceSettings()
        var createdContexts: [FakePetRuntimeContext] = []
        let manager = PetInstanceManager { instanceID in
            let context = FakePetRuntimeContext(instanceID: instanceID)
            createdContexts.append(context)
            return context
        }

        try manager.synchronizeSelectedRuntime(
            settings: settings,
            item: builtInItem(),
            reason: .settingsChange,
            reloadPet: true
        )
        try manager.synchronizeSelectedRuntime(
            settings: settings,
            item: builtInItem(),
            reason: .settingsChange,
            reloadPet: false
        )

        let context = try XCTUnwrap(createdContexts.first)
        XCTAssertEqual(createdContexts.count, 1)
        XCTAssertEqual(context.replacePetCallCount, 1)
        XCTAssertEqual(context.appliedSettings.count, 2)
        XCTAssertEqual(context.stopCallCount, 0)
    }

    func testChangingSelectionRetiresPreviousSingleRuntime() throws {
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

        try manager.synchronizeSelectedRuntime(
            settings: firstSettings,
            item: builtInItem(),
            reason: .settingsChange,
            reloadPet: true
        )
        let firstContext = try XCTUnwrap(
            contexts[firstSettings.selectedPetInstanceID]
        )
        try manager.synchronizeSelectedRuntime(
            settings: secondSettings,
            item: builtInItem(),
            reason: .settingsChange,
            reloadPet: true
        )

        XCTAssertEqual(firstContext.stopCallCount, 1)
        XCTAssertNil(manager.context(for: firstSettings.selectedPetInstanceID))
        XCTAssertNotNil(manager.context(for: secondID))
        XCTAssertEqual(manager.selectedInstanceID, secondID)
    }

    func testSharedStateIsAppliedToExistingAndNewContexts() throws {
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
        try manager.synchronizeSelectedRuntime(
            settings: settings,
            item: builtInItem(),
            reason: .settingsChange,
            reloadPet: true
        )
        let context = try XCTUnwrap(
            contexts[settings.selectedPetInstanceID]
        )

        XCTAssertEqual(context.reduceMotionValues, [true])
        XCTAssertEqual(context.activitySnapshots, [firstSnapshot])

        manager.setReduceMotion(false)
        manager.updateActivitySnapshot(secondSnapshot)

        XCTAssertEqual(context.reduceMotionValues, [true, false])
        XCTAssertEqual(
            context.activitySnapshots,
            [firstSnapshot, secondSnapshot]
        )
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
            try manager.synchronizeSelectedRuntime(
                settings: invalidSettings,
                item: builtInItem(),
                reason: .settingsChange,
                reloadPet: true
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

    private func twoInstanceSettings() throws -> AppSettings {
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
        return AppSettings(
            selectedPetInstanceID: firstInstance.instanceID,
            activePetInstances: [
                firstInstance,
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: .builtIn,
                    nickname: "두 번째",
                    presentation: .tuckedAway,
                    overlay: .default,
                    behaviorProfileID: secondProfileID,
                    displayOrder: 1
                )
            ],
            petBehaviorProfiles: [
                firstProfile,
                PetBehaviorProfileSettings(
                    profileID: secondProfileID,
                    profile: firstProfile.profile
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

    init(instanceID: UUID) {
        self.instanceID = instanceID
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

    func moveToVisibleFrame(_ visibleFrame: NSRect) {}

    func stop() {
        stopCallCount += 1
        isAwake = false
    }
}
