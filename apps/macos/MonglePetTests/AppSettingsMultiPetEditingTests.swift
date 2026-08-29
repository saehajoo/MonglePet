import XCTest
@testable import MonglePet

final class AppSettingsMultiPetEditingTests: XCTestCase {
    @MainActor
    func testSessionPersistsInstanceManagementChanges() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = AppSettingsStore(
            settingsURL: directoryURL.appendingPathComponent("settings.json")
        )
        let session = AppSettingsSession(store: store)
        _ = session.load()
        let firstID = session.settings.selectedPetInstanceID

        let secondID = try XCTUnwrap(
            session.addPetInstance(
                for: .builtIn,
                copyingSettingsFrom: firstID
            )
        )
        session.setPetInstanceNickname("두 번째", for: secondID)
        session.setClickThrough(true, for: secondID)
        session.movePetInstance(secondID, to: 0)

        let reloaded = AppSettingsSession(store: store)
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings.selectedPetInstanceID, secondID)
        XCTAssertEqual(
            reloaded.settings.activePetInstances.map(\.instanceID),
            [secondID, firstID]
        )
        XCTAssertEqual(reloaded.settings.selectedPetInstance?.nickname, "두 번째")
        XCTAssertTrue(reloaded.settings.selectedPetInstance?.overlay.clickThrough == true)

        XCTAssertTrue(reloaded.removePetInstance(secondID))
        XCTAssertEqual(store.load().settings.activePetInstances.count, 1)
        XCTAssertEqual(store.load().settings.selectedPetInstanceID, firstID)
    }

    func testAddingSamePetCreatesIndependentProfileAndSelectsIt() throws {
        let original = AppSettings.default
        let source = try XCTUnwrap(original.selectedPetInstance)
        let addedInstanceID = UUID(
            uuidString: "70000000-0000-0000-0000-000000000001"
        )!
        let addedProfileID = UUID(
            uuidString: "71000000-0000-0000-0000-000000000001"
        )!

        let updated = original.addingPetInstance(
            for: source.petKey,
            copyingSettingsFrom: source.instanceID,
            instanceID: addedInstanceID,
            profileID: addedProfileID
        )

        XCTAssertEqual(updated.selectedPetInstanceID, addedInstanceID)
        XCTAssertEqual(updated.activePetInstances.count, 2)
        XCTAssertEqual(updated.petBehaviorProfiles.count, 2)
        let added = try XCTUnwrap(updated.selectedPetInstance)
        XCTAssertEqual(added.behaviorProfileID, addedProfileID)
        XCTAssertNotEqual(added.behaviorProfileID, source.behaviorProfileID)
        XCTAssertEqual(added.displayOrder, 1)
        XCTAssertEqual(added.overlay.originX, source.overlay.originX + 28)
        XCTAssertEqual(added.overlay.originY, source.overlay.originY - 28)
        XCTAssertEqual(
            updated.activeBehaviorProfile,
            original.activeBehaviorProfile
        )

        let changed = updated.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: added.petKey,
                mode: .manual,
                manualSequenceID: nil,
                sequences: [],
                automaticRules: []
            )
        )
        XCTAssertNotEqual(
            changed.activeBehaviorProfile,
            original.activeBehaviorProfile
        )
        XCTAssertEqual(
            changed.runtimeSettings(for: source.instanceID)?
                .activeBehaviorProfile,
            original.activeBehaviorProfile
        )
    }

    func testAddingCopiedPetAcrossKeysClonesIndependentProfileAndOverlay() throws {
        let sourceKey = PetBehaviorKey.builtIn
        let copyKey = PetBehaviorKey.installed(
            UUID(uuidString: "76000000-0000-0000-0000-000000000001")!
        )
        let sourceProfile = BehaviorProfile(
            petKey: sourceKey,
            mode: .random,
            manualSequenceID: "manual",
            randomSequenceIDs: ["happy", "rest"],
            sequences: [
                BehaviorSequence(
                    id: "happy",
                    steps: [BehaviorStep(motionID: "happy", repeatCount: 2)],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: 234,
                cursorDistance: 88,
                stopRadius: 17,
                freeRoamingDwellMilliseconds: 4_500,
                prefersFrontmostWindow: false,
                cursorFollowingMotionID: "walk",
                freeRoamingMotionID: "walk"
            ),
            pettingMotionID: "happy",
            speech: .default
        )
        let source = AppSettings.default
            .replacingActiveBehaviorProfile(sourceProfile)
            .replacingSelectedOverlay(
                OverlaySettings(
                    screenIdentifier: "display-A",
                    originX: 120,
                    originY: 240,
                    width: 321,
                    clickThrough: true,
                    opacity: 0.72,
                    pointerOverlapFadeEnabled: true,
                    pointerOverlapOpacity: 0.18,
                    pixelArtRendering: true,
                    movementBoundary: .default
                )
            )
        let sourceInstance = try XCTUnwrap(source.selectedPetInstance)
        let copyInstanceID = UUID(
            uuidString: "77000000-0000-0000-0000-000000000001"
        )!
        let copyProfileID = UUID(
            uuidString: "78000000-0000-0000-0000-000000000001"
        )!

        let copied = source.addingPetInstance(
            for: copyKey,
            copyingSettingsFrom: sourceInstance.instanceID,
            allowsCopyingAcrossPetKeys: true,
            usesSelectedOverlayFallback: false,
            instanceID: copyInstanceID,
            profileID: copyProfileID
        )

        let copyInstance = try XCTUnwrap(copied.selectedPetInstance)
        let copyProfile = try XCTUnwrap(copied.activeBehaviorProfile)
        XCTAssertEqual(copyInstance.petKey, copyKey)
        XCTAssertNotEqual(copyInstance.behaviorProfileID, sourceInstance.behaviorProfileID)
        XCTAssertEqual(copyProfile.petKey, copyKey)
        XCTAssertEqual(copyProfile.mode, sourceProfile.mode)
        XCTAssertEqual(copyProfile.randomSequenceIDs, sourceProfile.randomSequenceIDs)
        XCTAssertEqual(copyProfile.sequences, sourceProfile.sequences)
        XCTAssertEqual(copyProfile.movement, sourceProfile.movement)
        XCTAssertEqual(copyProfile.pettingMotionID, sourceProfile.pettingMotionID)
        XCTAssertEqual(copyInstance.overlay.width, sourceInstance.overlay.width)
        XCTAssertEqual(copyInstance.overlay.opacity, sourceInstance.overlay.opacity)
        XCTAssertEqual(copyInstance.overlay.originX, sourceInstance.overlay.originX + 28)
        XCTAssertEqual(copyInstance.overlay.originY, sourceInstance.overlay.originY - 28)

        let changedCopy = copied.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: copyKey,
                mode: .manual,
                manualSequenceID: nil,
                sequences: [],
                automaticRules: []
            )
        )
        XCTAssertEqual(
            changedCopy.runtimeSettings(for: sourceInstance.instanceID)?
                .activeBehaviorProfile,
            sourceProfile
        )
    }

    func testNicknameSelectionAndReorderingPreserveInstanceIdentity() throws {
        let first = AppSettings.default
        let firstID = first.selectedPetInstanceID
        let secondID = UUID(
            uuidString: "72000000-0000-0000-0000-000000000001"
        )!
        let settings = first.addingPetInstance(
            for: .builtIn,
            instanceID: secondID,
            profileID: UUID(
                uuidString: "73000000-0000-0000-0000-000000000001"
            )!
        )

        let renamed = settings.replacingPetInstanceNickname(
            "  두 번째 몽글이  ",
            for: secondID
        )
        XCTAssertEqual(renamed.selectedPetInstance?.nickname, "두 번째 몽글이")

        let reordered = renamed.movingPetInstance(secondID, to: 0)
        XCTAssertEqual(
            reordered.activePetInstances.map(\.instanceID),
            [secondID, firstID]
        )
        XCTAssertEqual(
            reordered.activePetInstances.map(\.displayOrder),
            [0, 1]
        )
        XCTAssertEqual(reordered.selectedPetInstanceID, secondID)
        XCTAssertEqual(
            reordered.selectingPetInstance(firstID).selectedPetInstanceID,
            firstID
        )
    }

    func testRemovingSelectedInstanceSelectsNeighborAndKeepsOneMinimum() throws {
        let first = AppSettings.default
        let firstID = first.selectedPetInstanceID
        let secondID = UUID(
            uuidString: "74000000-0000-0000-0000-000000000001"
        )!
        let settings = first.addingPetInstance(
            for: .builtIn,
            copyingSettingsFrom: firstID,
            instanceID: secondID,
            profileID: UUID(
                uuidString: "75000000-0000-0000-0000-000000000001"
            )!
        )

        let removed = settings.removingPetInstance(secondID)
        XCTAssertEqual(removed.selectedPetInstanceID, firstID)
        XCTAssertEqual(removed.activePetInstances.map(\.instanceID), [firstID])
        XCTAssertEqual(removed.petBehaviorProfiles.count, 1)
        XCTAssertEqual(removed.removingPetInstance(firstID), removed)
    }
}
