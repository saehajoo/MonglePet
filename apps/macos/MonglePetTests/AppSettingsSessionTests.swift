import Foundation
import XCTest
@testable import MonglePet

final class AppSettingsSessionTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var settingsURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        settingsURL = temporaryDirectoryURL.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL,
           FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        settingsURL = nil
    }

    @MainActor
    func testChangesApplyImmediatelyAndPersistAcrossSessions() throws {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        var changedSettings: [AppSettings] = []
        session.onChange = { changedSettings.append($0) }
        XCTAssertEqual(session.load().source, .defaults)

        session.setUserPresentation(.tuckedAway)
        session.setBehaviorMode(.manual)
        session.setOverlayWidth(280)
        session.setClickThrough(true)
        session.setOverlayGeometry(
            OverlaySettings(
                screenIdentifier: "display-42",
                originX: 123,
                originY: 456,
                width: 280,
                clickThrough: true
            )
        )

        XCTAssertEqual(changedSettings.count, 5)
        XCTAssertEqual(session.settings.lastUserPresentation, .tuckedAway)
        XCTAssertEqual(session.settings.behaviorMode, .manual)
        XCTAssertNil(session.saveErrorMessage)

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings, session.settings)
    }

    @MainActor
    func testNewInstallationTransactionPersistsIndependentCopyBeforePublishing() throws {
        let store = AppSettingsStore(settingsURL: settingsURL)
        let session = AppSettingsSession(store: store)
        _ = session.load()
        let sourceID = session.settings.selectedPetInstanceID
        var published: [AppSettings] = []
        session.onChange = { published.append($0) }
        let installationID = UUID(
            uuidString: "79000000-0000-0000-0000-000000000001"
        )!

        let newInstanceID = try session.addNewlyInstalledPetInstance(
            for: .installed(installationID),
            copyingSettingsFrom: sourceID
        )

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(session.settings.selectedPetInstanceID, newInstanceID)
        XCTAssertEqual(session.settings.activePetInstances.count, 2)
        XCTAssertEqual(session.settings.petBehaviorProfiles.count, 2)
        let reloaded = AppSettingsSession(store: store)
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings, session.settings)

        reloaded.setBehaviorMode(.manual)
        XCTAssertEqual(
            reloaded.settings.runtimeSettings(for: sourceID)?.behaviorMode,
            .automatic
        )
        XCTAssertEqual(reloaded.settings.behaviorMode, .manual)
        let reloadedAgain = AppSettingsSession(store: store)
        XCTAssertEqual(reloadedAgain.load().source, .file)
        XCTAssertEqual(
            reloadedAgain.settings.runtimeSettings(for: sourceID)?.behaviorMode,
            .automatic
        )
        XCTAssertEqual(reloadedAgain.settings.behaviorMode, .manual)
    }

    @MainActor
    func testNewInstallationTransactionDoesNotPublishWhenSaveFails() throws {
        let blockedParentURL = temporaryDirectoryURL.appendingPathComponent(
            "not-a-directory"
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: blockedParentURL.path,
                contents: Data("blocked".utf8)
            )
        )
        let session = AppSettingsSession(
            store: AppSettingsStore(
                settingsURL: blockedParentURL.appendingPathComponent(
                    "settings.json"
                )
            )
        )
        let original = session.settings
        var publishCount = 0
        session.onChange = { _ in publishCount += 1 }

        XCTAssertThrowsError(
            try session.addNewlyInstalledPetInstance(
                for: .installed(UUID()),
                copyingSettingsFrom: nil
            )
        )
        XCTAssertEqual(session.settings, original)
        XCTAssertEqual(publishCount, 0)
        XCTAssertNotNil(session.saveErrorMessage)
    }

    @MainActor
    func testOverlayOpacitySettingsClampApplyAndPersist() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setOverlayOpacity(0, persist: false)
        session.setClickThrough(true)
        session.setPointerOverlapFadeEnabled(true)
        session.setPointerOverlapOpacity(2, persist: false)
        session.setPixelArtRendering(true)
        session.setOverlayWidth(240, persist: false)

        XCTAssertEqual(
            session.settings.overlay.opacity,
            AppSettingsLimits.minimumOverlayOpacity
        )
        XCTAssertTrue(session.settings.overlay.clickThrough)
        XCTAssertTrue(session.settings.overlay.pointerOverlapFadeEnabled)
        XCTAssertEqual(
            session.settings.overlay.pointerOverlapOpacity,
            AppSettingsLimits.maximumPointerOverlapOpacity
        )
        XCTAssertTrue(session.settings.overlay.pixelArtRendering)

        session.persistCurrentSettings()
        let reloaded = AppSettingsStore(settingsURL: settingsURL)
            .load()
            .settings
        XCTAssertEqual(reloaded.overlay, session.settings.overlay)
    }

    @MainActor
    func testSelectedPetInstallationPersistsAndCanReturnToBuiltInPet() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!

        session.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.selectedPetInstallationID,
            installationID
        )

        session.setSelectedPetInstallationID(nil)
        XCTAssertNil(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.selectedPetInstallationID
        )
    }

    @MainActor
    func testRecommendedProfileReplacesNewInstallationDefaultAndPersists() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111113"
        )!
        let sequence = BehaviorSequence(
            id: "creator-default",
            steps: [
                BehaviorStep(motionID: "idle", repeatCount: 3)
            ],
            repeats: true
        )
        let profile = RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: 220,
                cursorDistance: 84,
                stopRadius: 18,
                freeRoamingDwellMilliseconds: 7_500,
                prefersFrontmostWindow: false,
                cursorFollowingMotionID: nil,
                freeRoamingMotionID: "idle"
            ),
            pettingMotionID: "idle",
            display: PortablePetDisplaySettings(
                scalePercent: 150,
                clickThrough: true,
                opacity: 0.65,
                pointerOverlapFadeEnabled: true,
                pointerOverlapOpacity: 0.15,
                pixelArtRendering: true
            )
        )
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        let deviceBoundary = MovementBoundarySettings(
            mode: .selectedDisplay,
            screenIdentifier: "display-A",
            normalizedRect: nil
        )
        session.setOverlayGeometry(
            OverlaySettings(
                screenIdentifier: "display-A",
                originX: 321,
                originY: 123,
                width: 192,
                clickThrough: false,
                movementBoundary: deviceBoundary
            )
        )

        XCTAssertTrue(
            session.applyRecommendedProfile(profile, to: installationID)
        )
        XCTAssertEqual(
            session.settings.activeBehaviorProfile,
            profile.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertNil(session.saveErrorMessage)
        XCTAssertEqual(session.settings.overlay.width, 288)
        XCTAssertTrue(session.settings.overlay.clickThrough)
        XCTAssertEqual(session.settings.overlay.opacity, 0.65)
        XCTAssertEqual(session.settings.overlay.screenIdentifier, "display-A")
        XCTAssertEqual(session.settings.overlay.originX, 321)
        XCTAssertEqual(session.settings.overlay.originY, 123)
        XCTAssertEqual(session.settings.overlay.movementBoundary, deviceBoundary)

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(
            reloaded.settings.activeBehaviorProfile,
            profile.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertEqual(reloaded.settings.overlay, session.settings.overlay)
    }

    @MainActor
    func testLegacyRecommendedProfileDoesNotReplaceAbsentDisplaySettings() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111119"
        )!
        let profile = RecommendedPetProfile(
            mode: .automatic,
            manualSequenceID: nil,
            sequences: [],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil,
            includesDisplaySettings: false
        )
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        session.setOverlayGeometry(
            OverlaySettings(
                screenIdentifier: "legacy-display",
                originX: 41,
                originY: 73,
                width: 268,
                clickThrough: true,
                opacity: 0.72,
                pointerOverlapFadeEnabled: true,
                pointerOverlapOpacity: 0.12,
                pixelArtRendering: true,
                movementBoundary: .default
            )
        )
        let originalOverlay = session.settings.overlay

        XCTAssertTrue(
            session.applyRecommendedProfile(profile, to: installationID)
        )
        XCTAssertEqual(session.settings.overlay, originalOverlay)
    }

    @MainActor
    func testRecommendedProfileReplacementChangesOnlyTargetInstallation() {
        let firstID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111114"
        )!
        let secondID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222224"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(firstID)
        XCTAssertTrue(session.addBehaviorSequence(named: "첫 번째 로컬 설정"))
        let originalFirstProfile = session.settings.activeBehaviorProfile

        session.setSelectedPetInstallationID(secondID)
        XCTAssertTrue(session.addBehaviorSequence(named: "두 번째 로컬 설정"))
        let secondProfile = session.settings.activeBehaviorProfile

        session.setSelectedPetInstallationID(firstID)
        let recommended = RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "shared",
            sequences: [
                BehaviorSequence(
                    id: "shared",
                    steps: [
                        BehaviorStep(motionID: "idle", repeatCount: 4)
                    ],
                    repeats: false
                )
            ],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .cursorFollowing,
                speed: 260,
                cursorDistance: 72,
                stopRadius: 12,
                freeRoamingDwellMilliseconds: 8_000,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: "idle",
                freeRoamingMotionID: nil
            ),
            pettingMotionID: "idle"
        )

        XCTAssertTrue(
            session.applyRecommendedProfile(recommended, to: firstID)
        )
        XCTAssertNotEqual(session.settings.activeBehaviorProfile, originalFirstProfile)
        XCTAssertEqual(
            session.settings.activeBehaviorProfile,
            recommended.behaviorProfile(for: .installed(firstID))
        )
        XCTAssertEqual(
            session.settings.behaviorProfile(for: .installed(secondID)),
            secondProfile
        )
    }

    @MainActor
    func testBehaviorProfilesStayIndependentAcrossPetSwitchesAndRelaunch() throws {
        let installedID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111112"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()

        XCTAssertTrue(session.addBehaviorSequence(named: "built-in-custom"))
        let builtInCustomID = session.settings.sequences.last!.id
        session.setManualSequenceID(builtInCustomID)
        session.setBehaviorMode(.manual)
        XCTAssertTrue(
            session.addApplicationRule(
                bundleIdentifier: "com.example.BuiltIn",
                sequenceID: builtInCustomID
            )
        )

        session.setSelectedPetInstallationID(installedID)
        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID]
        )
        XCTAssertEqual(session.settings.behaviorMode, .automatic)
        XCTAssertTrue(session.settings.automaticRules.isEmpty)
        XCTAssertTrue(session.addBehaviorSequence(named: "installed-custom"))
        let installedCustomID = session.settings.sequences.last!.id
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: installedCustomID,
                index: 0,
                motionID: "coding",
                repeatCount: 5
            )
        )
        XCTAssertTrue(
            session.addIdleRule(
                seconds: 300,
                sequenceID: installedCustomID
            )
        )

        session.setSelectedPetInstallationID(nil)
        XCTAssertEqual(session.settings.behaviorMode, .manual)
        XCTAssertEqual(session.settings.manualSequenceID, builtInCustomID)
        XCTAssertTrue(session.settings.sequences.contains { $0.id == builtInCustomID })
        XCTAssertFalse(session.settings.sequences.contains { $0.id == installedCustomID })
        XCTAssertEqual(session.settings.automaticRules.count, 2)
        XCTAssertEqual(
            session.settings.automaticRules.last?.condition,
            .application(bundleIdentifier: "com.example.BuiltIn")
        )

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings.behaviorProfiles.count, 2)
        reloaded.setSelectedPetInstallationID(installedID)

        XCTAssertEqual(reloaded.settings.behaviorMode, .automatic)
        XCTAssertFalse(reloaded.settings.sequences.contains { $0.id == builtInCustomID })
        let installedStep = try XCTUnwrap(
            reloaded.settings.sequences.first { $0.id == installedCustomID }?.steps.first
        )
        XCTAssertEqual(installedStep.motionID, "coding")
        XCTAssertEqual(installedStep.repeatCount, 5)
        XCTAssertEqual(reloaded.settings.automaticRules.count, 1)
        XCTAssertEqual(
            reloaded.settings.automaticRules.first?.condition,
            .idleAtLeast(milliseconds: 300_000)
        )
    }

    @MainActor
    func testMovementSettingsStayIndependentAcrossPetSwitchesAndRelaunch() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111117"
        )!
        let builtInMovement = PetMovementSettings(
            mode: .cursorFollowing,
            speed: 220,
            cursorDistance: 100,
            stopRadius: 18,
            freeRoamingDwellMilliseconds: 7_000,
            prefersFrontmostWindow: false
        )
        let installedMovement = PetMovementSettings(
            mode: .freeRoaming,
            speed: 300,
            cursorDistance: 140,
            stopRadius: 24,
            freeRoamingDwellMilliseconds: 10_000,
            prefersFrontmostWindow: true
        )
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        session.setMovementSettings(builtInMovement)
        session.setPettingMotionID("built-in-petting")
        session.setBehaviorMode(.manual)
        XCTAssertTrue(session.addBehaviorSequence(named: "movement-preserved"))
        XCTAssertEqual(session.settings.movementSettings, builtInMovement)

        session.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(session.settings.movementSettings, .default)
        session.setMovementSettings(installedMovement)
        session.setPettingMotionID("installed-petting")

        session.setSelectedPetInstallationID(nil)
        XCTAssertEqual(session.settings.movementSettings, builtInMovement)
        XCTAssertEqual(session.settings.pettingMotionID, "built-in-petting")

        let reloaded = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        XCTAssertEqual(reloaded.load().source, .file)
        XCTAssertEqual(reloaded.settings.movementSettings, builtInMovement)
        XCTAssertEqual(reloaded.settings.pettingMotionID, "built-in-petting")
        reloaded.setSelectedPetInstallationID(installationID)
        XCTAssertEqual(reloaded.settings.movementSettings, installedMovement)
        XCTAssertEqual(reloaded.settings.pettingMotionID, "installed-petting")
    }

    @MainActor
    func testSeparateInstalledPetsReceiveIndependentDefaultProfiles() {
        let firstInstallationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111113"
        )!
        let secondInstallationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111114"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setSelectedPetInstallationID(firstInstallationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "first-custom"))
        let firstCustomID = session.settings.sequences.last!.id

        session.setSelectedPetInstallationID(secondInstallationID)
        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID]
        )
        XCTAssertFalse(
            session.settings.sequences.contains { $0.id == firstCustomID }
        )

        session.setSelectedPetInstallationID(firstInstallationID)
        XCTAssertTrue(
            session.settings.sequences.contains { $0.id == firstCustomID }
        )
        XCTAssertEqual(session.settings.behaviorProfiles.count, 3)
    }

    @MainActor
    func testReselectingSameInstallationRetainsCustomizedProfile() throws {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111115"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "kept-after-edit"))
        let profileBeforeReselection = try XCTUnwrap(
            session.settings.behaviorProfile(for: .installed(installationID))
        )

        session.setSelectedPetInstallationID(installationID)

        XCTAssertEqual(
            session.settings.behaviorProfile(for: .installed(installationID)),
            profileBeforeReselection
        )
    }

    @MainActor
    func testRemovingSelectedInstallationProfileSelectsBuiltInAndPersists() {
        let installationID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111116"
        )!
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.setSelectedPetInstallationID(installationID)
        XCTAssertTrue(session.addBehaviorSequence(named: "removed-with-pet"))

        XCTAssertTrue(
            session.removeBehaviorProfile(forInstallationID: installationID)
        )

        XCTAssertNil(session.settings.selectedPetInstallationID)
        XCTAssertNil(
            session.settings.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertNotNil(session.settings.behaviorProfile(for: .builtIn))
        let persistedSettings = AppSettingsStore(settingsURL: settingsURL)
            .load().settings
        XCTAssertNil(persistedSettings.selectedPetInstallationID)
        XCTAssertNil(
            persistedSettings.behaviorProfile(for: .installed(installationID))
        )
        XCTAssertNotNil(persistedSettings.behaviorProfile(for: .builtIn))
    }

    @MainActor
    func testOverlayWidthPreviewWaitsForExplicitPersistence() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setOverlayWidth(320, persist: false)

        XCTAssertEqual(session.settings.overlay.width, 320)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.persistCurrentSettings()
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().settings.overlay.width,
            320
        )
    }

    @MainActor
    func testOverlayWidthAllowsTenPercentAndClampsSmallerValues() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.setOverlayWidth(1)

        XCTAssertEqual(
            session.settings.overlay.width,
            AppSettingsLimits.defaultOverlayWidth * 0.1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.overlay.width,
            AppSettingsLimits.minimumOverlayWidth,
            accuracy: 0.000_1
        )
    }

    @MainActor
    func testMovementPreviewWaitsForExplicitPersistence() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let movement = PetMovementSettings(
            mode: .cursorFollowing,
            speed: 280,
            cursorDistance: 144,
            stopRadius: 24,
            freeRoamingDwellMilliseconds: 8_000,
            prefersFrontmostWindow: false,
            cursorFollowingMotionID: "run"
        )

        session.setMovementSettings(movement, persist: false)

        XCTAssertEqual(session.settings.movementSettings, movement)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.persistCurrentSettings()
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.movementSettings,
            movement
        )
    }

    @MainActor
    func testMovementBoundaryPersistsWithoutChangingPetMovementProfile() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let originalMovement = session.settings.movementSettings
        let boundary = MovementBoundarySettings(
            mode: .customArea,
            screenIdentifier: "display-personal",
            normalizedRect: NormalizedMovementRect(
                x: 0.1,
                y: 0.2,
                width: 0.7,
                height: 0.6
            )
        )

        session.setMovementBoundary(boundary)

        XCTAssertEqual(
            session.settings.overlay.movementBoundary,
            boundary
        )
        XCTAssertEqual(session.settings.movementSettings, originalMovement)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.overlay.movementBoundary,
            boundary
        )
    }

    @MainActor
    func testPettingMotionSelectionPersistsWithActivePetProfile() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()

        session.setPettingMotionID("petting")

        XCTAssertEqual(session.settings.pettingMotionID, "petting")
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load()
                .settings.pettingMotionID,
            "petting"
        )

        session.setPettingMotionID(nil)

        XCTAssertNil(session.settings.pettingMotionID)
    }

    @MainActor
    func testSynchronizedRuntimeGeometryIsIncludedInNextSavedChange() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        let runtimeOverlay = OverlaySettings(
            screenIdentifier: "display-7",
            originX: 700,
            originY: 80,
            width: 192,
            clickThrough: false
        )

        session.synchronizeOverlayGeometry(runtimeOverlay)
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        session.setBehaviorMode(.manual)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load()
        XCTAssertEqual(reloaded.settings.overlay, runtimeOverlay)
        XCTAssertEqual(reloaded.settings.behaviorMode, .manual)
    }

    @MainActor
    func testRuntimeGeometryUpdatesOnlyMatchingPetInstance() throws {
        let defaults = AppSettings.default
        let firstInstance = try XCTUnwrap(
            defaults.activePetInstances.first
        )
        let firstProfile = try XCTUnwrap(
            defaults.petBehaviorProfiles.first
        )
        let secondInstanceID = UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!
        let secondProfileID = UUID(
            uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )!
        let initialSettings = AppSettings(
            selectedPetInstanceID: firstInstance.instanceID,
            activePetInstances: [
                firstInstance,
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: .builtIn,
                    nickname: "두 번째",
                    presentation: .awake,
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
        let store = AppSettingsStore(settingsURL: settingsURL)
        try store.save(initialSettings)
        let session = AppSettingsSession(store: store)
        XCTAssertEqual(session.load().source, .file)
        let firstOverlay = firstInstance.overlay
        let secondOverlay = OverlaySettings(
            screenIdentifier: "display-secondary",
            originX: -640,
            originY: 120,
            width: 256,
            clickThrough: true,
            opacity: 0.7,
            pointerOverlapFadeEnabled: true,
            pointerOverlapOpacity: 0.2,
            pixelArtRendering: true,
            movementBoundary: .default
        )

        session.setOverlayGeometry(
            secondOverlay,
            for: secondInstanceID
        )

        XCTAssertEqual(session.settings.selectedPetInstanceID, firstInstance.instanceID)
        XCTAssertEqual(
            session.settings.activePetInstances[0].overlay,
            firstOverlay
        )
        XCTAssertEqual(
            session.settings.activePetInstances[1].overlay,
            secondOverlay
        )
        let reloaded = store.load().settings
        XCTAssertEqual(reloaded.activePetInstances[0].overlay, firstOverlay)
        XCTAssertEqual(reloaded.activePetInstances[1].overlay, secondOverlay)
    }

    @MainActor
    func testPresentationUpdatesOnlyMatchingPetInstance() throws {
        let defaults = AppSettings.default
        let firstInstance = try XCTUnwrap(defaults.activePetInstances.first)
        let firstProfile = try XCTUnwrap(defaults.petBehaviorProfiles.first)
        let secondInstanceID = UUID(
            uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )!
        let secondProfileID = UUID(
            uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        )!
        let initialSettings = AppSettings(
            selectedPetInstanceID: firstInstance.instanceID,
            activePetInstances: [
                firstInstance,
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: .builtIn,
                    nickname: nil,
                    presentation: .awake,
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
        let store = AppSettingsStore(settingsURL: settingsURL)
        try store.save(initialSettings)
        let session = AppSettingsSession(store: store)
        XCTAssertEqual(session.load().source, .file)

        session.setUserPresentation(
            .tuckedAway,
            for: secondInstanceID
        )

        XCTAssertEqual(
            session.settings.activePetInstances[0].presentation,
            .awake
        )
        XCTAssertEqual(
            session.settings.activePetInstances[1].presentation,
            .tuckedAway
        )
        XCTAssertEqual(
            store.load().settings.activePetInstances.map(\.presentation),
            [.awake, .tuckedAway]
        )
    }

    @MainActor
    func testRemovingInstallationReplacesEveryReferencingInstanceIndependently() throws {
        let installationID = UUID(
            uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        )!
        let defaults = AppSettings.default
        let builtInProfile = try XCTUnwrap(defaults.petBehaviorProfiles.first)
        let firstInstanceID = UUID(
            uuidString: "11111111-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!
        let secondInstanceID = UUID(
            uuidString: "22222222-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )!
        let firstProfileID = UUID(
            uuidString: "33333333-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )!
        let secondProfileID = UUID(
            uuidString: "44444444-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        )!
        let installedProfile = BehaviorProfile(
            petKey: .installed(installationID),
            mode: builtInProfile.profile.mode,
            manualSequenceID: builtInProfile.profile.manualSequenceID,
            sequences: builtInProfile.profile.sequences,
            automaticRules: builtInProfile.profile.automaticRules,
            movement: builtInProfile.profile.movement,
            pettingMotionID: builtInProfile.profile.pettingMotionID,
            speech: builtInProfile.profile.speech
        )
        let firstOverlay = OverlaySettings(
            screenIdentifier: "first-display",
            originX: 120,
            originY: 80,
            width: 192,
            clickThrough: false
        )
        let secondOverlay = OverlaySettings(
            screenIdentifier: "second-display",
            originX: 720,
            originY: 160,
            width: 256,
            clickThrough: true
        )
        let initialSettings = AppSettings(
            selectedPetInstanceID: firstInstanceID,
            activePetInstances: [
                PetInstanceSettings(
                    instanceID: firstInstanceID,
                    petKey: .installed(installationID),
                    nickname: "첫 번째",
                    presentation: .awake,
                    overlay: firstOverlay,
                    behaviorProfileID: firstProfileID,
                    displayOrder: 0
                ),
                PetInstanceSettings(
                    instanceID: secondInstanceID,
                    petKey: .installed(installationID),
                    nickname: "두 번째",
                    presentation: .tuckedAway,
                    overlay: secondOverlay,
                    behaviorProfileID: secondProfileID,
                    displayOrder: 1
                )
            ],
            petBehaviorProfiles: [
                builtInProfile,
                PetBehaviorProfileSettings(
                    profileID: firstProfileID,
                    profile: installedProfile
                ),
                PetBehaviorProfileSettings(
                    profileID: secondProfileID,
                    profile: installedProfile
                )
            ]
        )
        let store = AppSettingsStore(settingsURL: settingsURL)
        try store.save(initialSettings)
        let session = AppSettingsSession(store: store)
        XCTAssertEqual(session.load().source, .file)

        XCTAssertTrue(
            session.removeBehaviorProfile(
                forInstallationID: installationID
            )
        )

        let instances = session.settings.activePetInstances
        XCTAssertEqual(instances.map(\.instanceID), [firstInstanceID, secondInstanceID])
        XCTAssertEqual(instances.map(\.petKey), [.builtIn, .builtIn])
        XCTAssertEqual(Set(instances.map(\.behaviorProfileID)).count, 2)
        XCTAssertEqual(instances.map(\.presentation), [.awake, .tuckedAway])
        XCTAssertEqual(
            instances.map(\.overlay),
            [
                BuiltInBehaviorPresets.mongleDisplay.applying(
                    to: firstOverlay
                ),
                secondOverlay
            ]
        )
        XCTAssertNil(
            session.settings.behaviorProfile(
                for: .installed(installationID)
            )
        )
        XCTAssertEqual(
            store.load().settings.activePetInstances.map(\.petKey),
            [.builtIn, .builtIn]
        )
    }

    @MainActor
    func testSystemDefaultBehaviorInstallsInMemoryAndCustomSelectionPersists() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()

        session.ensureSystemDefaultBehavior()

        XCTAssertEqual(
            session.settings.sequences.map(\.id),
            BuiltInBehaviorPresets.mongleSequences.map(\.id)
        )
        XCTAssertEqual(
            session.settings.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertEqual(
            session.settings.automaticRules,
            BuiltInBehaviorPresets.mongleAutomaticRules
        )
        XCTAssertEqual(
            AppSettingsStore(settingsURL: settingsURL).load().source,
            .defaults
        )

        XCTAssertTrue(session.addBehaviorSequence(named: "coding"))
        let codingID = session.settings.sequences.last!.id
        session.setManualSequenceID(codingID)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load()
        XCTAssertEqual(reloaded.settings.manualSequenceID, codingID)
        XCTAssertEqual(
            reloaded.settings.sequences.map(\.id),
            BuiltInBehaviorPresets.mongleSequences.map(\.id) + [codingID]
        )
        XCTAssertEqual(
            reloaded.settings.automaticRules,
            BuiltInBehaviorPresets.mongleAutomaticRules
        )
    }

    @MainActor
    func testBehaviorEditingReportsErrorsAndPersistsValidChanges() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()

        XCTAssertTrue(session.addBehaviorSequence(named: "coding"))
        let codingID = session.settings.sequences.last!.id
        XCTAssertNil(session.behaviorEditErrorMessage)
        XCTAssertTrue(session.addBehaviorStep(to: codingID, motionID: "wave"))
        XCTAssertEqual(
            session.settings.sequences.last?.steps.last?.motionID,
            "wave"
        )
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: codingID,
                index: 1,
                motionID: "focus",
                repeatCount: 12
            )
        )
        XCTAssertFalse(session.addBehaviorSequence(named: "coding"))
        XCTAssertNotNil(session.behaviorEditErrorMessage)

        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        let coding = reloaded.sequences.first { $0.id == codingID }
        XCTAssertEqual(coding?.steps.count, 2)
        XCTAssertEqual(coding?.steps[1].motionID, "focus")
        XCTAssertEqual(coding?.steps[1].repeatCount, 12)
    }

    @MainActor
    func testBehaviorStepEditingRejectsInvalidRepeatCountWithoutChangingSettings() {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        let originalSettings = session.settings

        XCTAssertFalse(
            session.updateBehaviorStep(
                sequenceID: BuiltInBehaviorPresets.defaultSequenceID,
                index: 0,
                motionID: PetMotionReference.currentPetDefault,
                repeatCount: 0
            )
        )
        XCTAssertEqual(session.settings, originalSettings)
        XCTAssertNotNil(session.behaviorEditErrorMessage)
    }

    @MainActor
    func testRenamingAndRemovingMotionReferencesUpdatesBehaviorMovementAndPetting() throws {
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )
        _ = session.load()
        session.ensureSystemDefaultBehavior()
        XCTAssertTrue(session.addBehaviorSequence(named: "custom"))
        let customID = session.settings.sequences.last!.id
        XCTAssertTrue(
            session.updateBehaviorStep(
                sequenceID: customID,
                index: 0,
                motionID: "wave",
                repeatCount: 4
            )
        )
        session.setMovementSettings(
            PetMovementSettings(
                mode: .cursorFollowing,
                speed: AppSettingsLimits.defaultMovementSpeed,
                cursorDistance: AppSettingsLimits.defaultCursorDistance,
                stopRadius: AppSettingsLimits.defaultMovementStopRadius,
                freeRoamingDwellMilliseconds:
                    AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: customID,
                freeRoamingMotionID: customID
            )
        )
        session.setPettingMotionID(customID)
        var changes: [AppSettings] = []
        session.onChange = { changes.append($0) }

        XCTAssertTrue(
            session.renameMotionReferences(
                from: "wave",
                to: "hello"
            )
        )

        let currentStep = try XCTUnwrap(
            session.settings.sequences.first { $0.id == customID }?.steps.first
        )
        XCTAssertEqual(currentStep.motionID, "hello")
        XCTAssertEqual(session.settings.movementSettings.cursorFollowingMotionID, customID)
        XCTAssertEqual(session.settings.movementSettings.freeRoamingMotionID, customID)
        XCTAssertEqual(session.settings.pettingMotionID, customID)

        XCTAssertTrue(session.removeMotionReferences("hello"))
        let removedStep = try XCTUnwrap(
            session.settings.sequences.first { $0.id == customID }?.steps.first
        )
        XCTAssertEqual(removedStep.motionID, PetMotionReference.currentPetDefault)
        XCTAssertEqual(session.settings.movementSettings.cursorFollowingMotionID, customID)
        XCTAssertEqual(session.settings.movementSettings.freeRoamingMotionID, customID)
        XCTAssertEqual(session.settings.pettingMotionID, customID)
        XCTAssertEqual(changes.last, session.settings)
        let reloaded = AppSettingsStore(settingsURL: settingsURL).load().settings
        XCTAssertEqual(
            reloaded.sequences.first { $0.id == customID }?.steps.first?.motionID,
            PetMotionReference.currentPetDefault
        )
        XCTAssertEqual(reloaded.movementSettings.cursorFollowingMotionID, customID)
        XCTAssertEqual(reloaded.movementSettings.freeRoamingMotionID, customID)
        XCTAssertEqual(reloaded.pettingMotionID, customID)
    }

    @MainActor
    func testUnmodifiedLegacyDefaultsMigrateToSingleSystemDefault() throws {
        let legacySettings = StoredAppSettings(
            schemaVersion: 1,
            selectedPetInstallationID: nil,
            lastUserPresentation: "awake",
            behaviorMode: "automatic",
            overlay: StoredOverlaySettings(
                screenIdentifier: nil,
                originX: 0,
                originY: 0,
                width: 192,
                clickThrough: false
            ),
            manualSequenceID: "idle",
            sequences: BuiltInBehaviorPresets.legacySequences.map { sequence in
                StoredBehaviorSequence(
                    id: sequence.id,
                    steps: sequence.steps.map { step in
                        StoredBehaviorStep(
                            motionID: step.motionID,
                            durationMilliseconds: 3_000,
                            playbackSpeed: 1
                        )
                    },
                    repeats: sequence.repeats
                )
            },
            automaticRules: BuiltInBehaviorPresets.legacyAutomaticRules.map { rule in
                StoredAutomaticRule(
                    id: rule.id.uuidString,
                    isEnabled: rule.isEnabled,
                    priority: rule.priority,
                    condition: {
                        switch rule.condition {
                        case let .idleAtLeast(milliseconds):
                            return .idleAtLeast(milliseconds: milliseconds)
                        case let .application(bundleIdentifier):
                            return .application(bundleIdentifier: bundleIdentifier)
                        case let .unsupported(type):
                            return .unsupported(type: type)
                        }
                    }(),
                    sequenceID: rule.sequenceID
                )
            }
        )
        try JSONEncoder().encode(legacySettings).write(to: settingsURL)
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )

        _ = session.load { _ in self.migrationPetDefinition }
        session.ensureSystemDefaultBehavior()

        XCTAssertEqual(
            session.settings.sequences,
            BuiltInBehaviorPresets.mongleSequences
        )
        XCTAssertEqual(
            session.settings.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertEqual(
            session.settings.automaticRules,
            BuiltInBehaviorPresets.mongleAutomaticRules
        )
        XCTAssertEqual(
            session.settings.movementSettings,
            BuiltInBehaviorPresets.mongleMovement
        )
        XCTAssertEqual(
            session.settings.pettingMotionID,
            BuiltInBehaviorPresets.monglePettingMotionID
        )
    }

    func testFreshBuiltInProfileUsesPublishedRecommendedOptions() {
        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: .default)

        XCTAssertEqual(normalized.selectedPetKey, .builtIn)
        XCTAssertEqual(normalized.behaviorMode, .automatic)
        XCTAssertEqual(
            normalized.manualSequenceID,
            BuiltInBehaviorPresets.defaultSequenceID
        )
        XCTAssertEqual(
            normalized.sequences,
            BuiltInBehaviorPresets.mongleSequences
        )
        XCTAssertEqual(
            normalized.automaticRules,
            BuiltInBehaviorPresets.mongleAutomaticRules
        )
        XCTAssertEqual(
            normalized.movementSettings,
            BuiltInBehaviorPresets.mongleMovement
        )
        XCTAssertEqual(
            normalized.pettingMotionID,
            "__monglepet_motion_behavior__7ZW07ZS8"
        )
        XCTAssertEqual(normalized.speechSettings, .default)
        XCTAssertEqual(
            PortablePetDisplaySettings(overlay: normalized.overlay),
            BuiltInBehaviorPresets.mongleDisplay
        )
        XCTAssertEqual(
            normalized.sequences.map(\.displayName),
            [
                "기본",
                "수면 중",
                "일하는 중",
                "왼쪽 보글보글",
                "오른쪽",
                "위",
                "정면",
                "행복",
                "왼쪽",
                "아래",
                "찾는 중",
                "오른쪽 보글보글"
            ]
        )
        XCTAssertEqual(
            normalized.sequences.map { $0.steps[0].motionID },
            [
                PetMotionReference.currentPetDefault,
                "자는 중",
                "일하는 중",
                "왼쪽 보글보글",
                "오른쪽",
                "위",
                "정면",
                "행복",
                "왼쪽",
                "아래",
                "찾는 중",
                "오른쪽 보글보글"
            ]
        )
        XCTAssertEqual(
            normalized.automaticRulePriorityOrder,
            [.idle, .application, .movement]
        )
        XCTAssertEqual(normalized.automaticRules.count, 1)
        XCTAssertEqual(
            normalized.automaticRules.first?.condition,
            .idleAtLeast(milliseconds: 60_000)
        )
        XCTAssertEqual(normalized.movementSettings.mode, .cursorAvoiding)
        XCTAssertEqual(normalized.movementSettings.cursorDistance, 256)
        XCTAssertEqual(
            normalized.movementSettings.cursorAvoidingIdleBehavior,
            .freeRoaming
        )
        XCTAssertTrue(
            normalized.movementSettings.randomizesFreeRoamingDwell
        )
        XCTAssertEqual(
            normalized.movementSettings.freeRoamingDwellMinimumMilliseconds,
            2_000
        )
        XCTAssertEqual(
            normalized.movementSettings.freeRoamingDwellMilliseconds,
            6_000
        )
    }

    func testUntouchedVersionOnePointZeroPointTwoProfileMigratesWithDisplay() {
        let original = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [
                BuiltInBehaviorPresets.publishedMongleProfileV102
            ]
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: original)

        XCTAssertEqual(
            normalized.activeBehaviorProfile,
            BuiltInBehaviorPresets.defaultProfile(for: .builtIn)
        )
        XCTAssertEqual(
            PortablePetDisplaySettings(overlay: normalized.overlay),
            BuiltInBehaviorPresets.mongleDisplay
        )
    }

    func testVersionOnePointZeroPointTwoMigrationPreservesCustomDisplay() {
        let customOverlay = OverlaySettings(
            screenIdentifier: "screen-1",
            originX: 80,
            originY: 120,
            width: 240,
            clickThrough: false,
            opacity: 0.8,
            pointerOverlapFadeEnabled: false,
            pointerOverlapOpacity: 0.3,
            pixelArtRendering: true,
            movementBoundary: .default
        )
        let original = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: customOverlay,
            behaviorProfiles: [
                BuiltInBehaviorPresets.publishedMongleProfileV102
            ]
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: original)

        XCTAssertEqual(
            normalized.activeBehaviorProfile,
            BuiltInBehaviorPresets.defaultProfile(for: .builtIn)
        )
        XCTAssertEqual(normalized.overlay, customOverlay)
    }

    func testModifiedVersionOnePointZeroPointTwoProfileIsNotOverwritten() {
        let published = BuiltInBehaviorPresets.publishedMongleProfileV102
        let modified = BehaviorProfile(
            petKey: published.petKey,
            mode: .manual,
            manualSequenceID: published.manualSequenceID,
            randomSequenceIDs: published.randomSequenceIDs,
            sequences: published.sequences,
            automaticRules: published.automaticRules,
            automaticRulePriorityOrder:
                published.automaticRulePriorityOrder,
            movement: published.movement,
            pettingMotionID: published.pettingMotionID,
            speech: published.speech
        )
        let original = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            overlay: .default,
            behaviorProfiles: [modified]
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: original)

        XCTAssertEqual(normalized.activeBehaviorProfile, modified)
        XCTAssertEqual(normalized.overlay, .default)
    }

    func testUnmodifiedPublishedMongleProfileMigratesToCurrentDefaults() {
        let previousSequences = [
            BehaviorSequence(
                id: BuiltInBehaviorPresets.defaultSequenceID,
                displayName: "기본",
                steps: [
                    BehaviorStep(
                        motionID: PetMotionReference.currentPetDefault,
                        repeatCount: 1
                    ),
                    BehaviorStep(motionID: "물뿜기", repeatCount: 1),
                    BehaviorStep(motionID: "정면", repeatCount: 1)
                ],
                repeats: true
            ),
            BehaviorSequence(
                id: "수면 중",
                steps: [BehaviorStep(motionID: "자는중", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "일해라",
                steps: [BehaviorStep(motionID: "일하는 중", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "보글보글",
                steps: [BehaviorStep(motionID: "보글보글", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "오른쪽",
                steps: [BehaviorStep(motionID: "오른쪽", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "위로",
                steps: [BehaviorStep(motionID: "위로", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "정면",
                steps: [BehaviorStep(motionID: "정면", repeatCount: 1)],
                repeats: true
            ),
            BehaviorSequence(
                id: "해피",
                steps: [BehaviorStep(motionID: "해피", repeatCount: 1)],
                repeats: true
            )
        ]
        let previousRules = [
            AutomaticRule(
                id: UUID(
                    uuidString: "5C8B76B6-3C4F-4D22-86CA-8EFF77CE35F1"
                )!,
                isEnabled: true,
                priority: 0,
                condition: .application(bundleIdentifier: "com.openai.codex"),
                sequenceID: "일해라"
            ),
            AutomaticRule(
                id: UUID(
                    uuidString: "308C8E4B-EDEA-4C71-B354-CC67532AF99C"
                )!,
                isEnabled: true,
                priority: 1,
                condition: .idleAtLeast(milliseconds: 60_000),
                sequenceID: "수면 중"
            )
        ]
        let previousMovement = PetMovementSettings(
            mode: .cursorAvoiding,
            speed: 160,
            cursorDistance: 96,
            stopRadius: 16,
            freeRoamingDwellMilliseconds: 6_000,
            prefersFrontmostWindow: true,
            cursorFollowingAnimation: .default,
            freeRoamingAnimation: .default,
            cursorAvoidingIdleBehavior: .stationary,
            cursorAvoidingDetectionDistance: 160,
            cursorAvoidingSpeed: 320,
            cursorAvoidingAnimation: MovementAnimationSettings(
                fallbackMotionID: "보글보글",
                usesDirectionalMotions: true,
                usesDiagonalMotions: false,
                directionMotionIDs: DirectionalMotionIDs(
                    left: "보글보글",
                    right: "오른쪽",
                    up: "위로",
                    down: "정면"
                )
            )
        )
        let previous = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            movement: previousMovement,
            pettingMotionID: "해피",
            manualSequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            sequences: previousSequences,
            automaticRules: previousRules,
            automaticRulePriorityOrder: [.movement, .idle, .application]
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: previous)

        XCTAssertEqual(
            normalized.activeBehaviorProfile,
            BuiltInBehaviorPresets.defaultProfile(for: .builtIn)
        )
        XCTAssertEqual(
            normalized.overlay,
            BuiltInBehaviorPresets.mongleDisplay.applying(
                to: previous.overlay
            )
        )
    }

    func testModifiedBuiltInProfileKeepsBehaviorIDsWhileRenamingRemovedMotions() {
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            manualSequenceID: "custom-sleep",
            sequences: [
                BehaviorSequence(
                    id: "custom-sleep",
                    displayName: "자는중",
                    steps: [
                        BehaviorStep(motionID: "자는중", repeatCount: 2)
                    ],
                    repeats: false
                ),
                BehaviorSequence(
                    id: "custom-happy",
                    displayName: "내 행복",
                    steps: [
                        BehaviorStep(motionID: "해피", repeatCount: 3)
                    ],
                    repeats: true
                )
            ],
            automaticRules: []
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: settings)

        XCTAssertEqual(normalized.behaviorMode, .manual)
        XCTAssertEqual(normalized.manualSequenceID, "custom-sleep")
        XCTAssertEqual(
            normalized.sequences.map(\.id),
            [BuiltInBehaviorPresets.defaultSequenceID, "custom-sleep", "custom-happy"]
        )
        XCTAssertEqual(normalized.sequences.map(\.displayName), ["기본", "자는 중", "내 행복"])
        XCTAssertEqual(
            normalized.sequences.map { $0.steps[0].motionID },
            [PetMotionReference.currentPetDefault, "자는 중", "행복"]
        )
        XCTAssertEqual(normalized.sequences.map { $0.steps[0].repeatCount }, [1, 2, 3])
        XCTAssertEqual(normalized.sequences.map(\.repeats), [true, false, true])
    }

    func testModifiedPreviousBuiltInProfileIsPreserved() {
        let movement = PetMovementSettings(
            mode: .freeRoaming,
            speed: 210,
            cursorDistance: 96,
            stopRadius: 16,
            freeRoamingDwellMilliseconds: 6_000,
            prefersFrontmostWindow: false
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            movement: movement,
            manualSequenceID: BuiltInBehaviorPresets.defaultSequenceID,
            sequences: BuiltInBehaviorPresets.sequences,
            automaticRules: []
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: settings)

        XCTAssertEqual(normalized.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertTrue(normalized.automaticRules.isEmpty)
        XCTAssertEqual(normalized.movementSettings, movement)
        XCTAssertNil(normalized.pettingMotionID)
    }

    func testInstalledPetKeepsGenericDefaultProfile() {
        let installationID = UUID(
            uuidString: "A1000000-0000-0000-0000-000000000001"
        )!
        let settings = AppSettings.default.addingPetInstance(
            for: .installed(installationID)
        )

        XCTAssertEqual(settings.selectedPetKey, .installed(installationID))
        XCTAssertEqual(settings.sequences, BuiltInBehaviorPresets.sequences)
        XCTAssertTrue(settings.automaticRules.isEmpty)
        XCTAssertEqual(settings.movementSettings, .default)
        XCTAssertNil(settings.pettingMotionID)
    }

    private var migrationPetDefinition: PetDefinition {
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
            duration: .seconds(1)
        )
        return PetDefinition(
            id: "migration.pet",
            displayName: "Migration Pet",
            defaultMotionID: "idle",
            motions: ["idle", "focus", "rest", "sleep"].map {
                PetMotion(id: $0, loops: true, frames: [frame])
            }
        )
    }

    func testModifiedLegacyBehaviorIsPreservedWhileSystemDefaultIsAdded() throws {
        var modifiedSequences = BuiltInBehaviorPresets.legacySequences
        let idle = try XCTUnwrap(modifiedSequences.first)
        modifiedSequences[0] = BehaviorSequence(
            id: idle.id,
            steps: [
                BehaviorStep(
                    motionID: "idle",
                    duration: .seconds(4),
                    playbackSpeed: 1
                )
            ],
            repeats: true
        )
        let settings = AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .automatic,
            overlay: .default,
            manualSequenceID: "idle",
            sequences: modifiedSequences,
            automaticRules: BuiltInBehaviorPresets.legacyAutomaticRules
        )

        let normalized = BuiltInBehaviorPresets.normalizedDefaults(in: settings)

        XCTAssertEqual(normalized.sequences.first, BuiltInBehaviorPresets.sequences[0])
        XCTAssertEqual(Array(normalized.sequences.dropFirst()), modifiedSequences)
        XCTAssertEqual(normalized.manualSequenceID, "idle")
        XCTAssertEqual(
            normalized.automaticRules,
            BuiltInBehaviorPresets.legacyAutomaticRules
        )
    }

    @MainActor
    func testNewerSchemaPreservesFileWhileAllowingRuntimePresentationChange() throws {
        let originalData = Data(#"{"schemaVersion":15,"future":true}"#.utf8)
        try originalData.write(to: settingsURL)
        let session = AppSettingsSession(
            store: AppSettingsStore(settingsURL: settingsURL)
        )

        let result = session.load()
        session.setUserPresentation(.tuckedAway)

        XCTAssertEqual(result.source, .newerSchema(15))
        XCTAssertFalse(session.isWritingEnabled)
        XCTAssertNotNil(session.loadNotice)
        XCTAssertEqual(session.settings.lastUserPresentation, .tuckedAway)
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalData)
    }

    @MainActor
    func testRestorePositionPolicyDistinguishesDefaultsCorruptAndPartialRecovery() {
        let defaults = AppSettingsLoadResult(
            settings: .default,
            issues: [],
            source: .defaults,
            isWritingEnabled: true
        )
        let corrupt = AppSettingsLoadResult(
            settings: .default,
            issues: [.corruptFileQuarantined("settings.corrupt-test.json")],
            source: .recovered,
            isWritingEnabled: true
        )
        let partial = AppSettingsLoadResult(
            settings: .default,
            issues: [.invalidField("behaviorMode")],
            source: .recovered,
            isWritingEnabled: true
        )

        XCTAssertFalse(defaults.shouldRestoreOverlayPosition)
        XCTAssertFalse(corrupt.shouldRestoreOverlayPosition)
        XCTAssertTrue(partial.shouldRestoreOverlayPosition)
    }
}
