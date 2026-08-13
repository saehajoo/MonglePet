import AppKit
import XCTest
@testable import MonglePet

@MainActor
final class PetRuntimeContextIsolationTests: XCTestCase {
    func testBehaviorSpeechAndPettingStayIndependentPerInstance() throws {
        let firstID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
        let secondID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000002"
        )!
        let firstProfileID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
        let secondProfileID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000002"
        )!
        let settings = makeSettings(
            specifications: [
                RuntimeSpecification(
                    instanceID: firstID,
                    profileID: firstProfileID,
                    sequenceID: "first-behavior",
                    speechText: "첫 번째 펫",
                    movementMode: .fixed
                ),
                RuntimeSpecification(
                    instanceID: secondID,
                    profileID: secondProfileID,
                    sequenceID: "second-behavior",
                    speechText: "두 번째 펫",
                    movementMode: .fixed
                )
            ]
        )
        let harness = makeHarness()
        defer { harness.manager.stopAll() }

        try synchronize(
            harness: harness,
            settings: settings,
            reason: .initialLoad(shouldRestorePosition: true)
        )
        harness.manager.updateActivitySnapshot(activeSnapshot())

        XCTAssertEqual(
            statusMap(harness.manager)[firstID]?.currentBehaviorSequenceID,
            "first-behavior"
        )
        XCTAssertEqual(
            statusMap(harness.manager)[firstID]?.currentSpeechText,
            "첫 번째 펫"
        )
        XCTAssertEqual(
            statusMap(harness.manager)[secondID]?.currentBehaviorSequenceID,
            "second-behavior"
        )
        XCTAssertEqual(
            statusMap(harness.manager)[secondID]?.currentSpeechText,
            "두 번째 펫"
        )

        let updatedSettings = replacingProfile(
            firstProfileID,
            in: settings,
            with: profile(
                sequenceID: "first-updated",
                speechText: "첫 번째만 변경",
                movementMode: .fixed
            )
        )
        try synchronize(
            harness: harness,
            settings: updatedSettings,
            reason: .settingsChange
        )

        let updatedStatuses = statusMap(harness.manager)
        XCTAssertEqual(
            updatedStatuses[firstID]?.currentBehaviorSequenceID,
            "first-updated"
        )
        XCTAssertEqual(
            updatedStatuses[firstID]?.currentSpeechText,
            "첫 번째만 변경"
        )
        XCTAssertEqual(
            updatedStatuses[secondID]?.currentBehaviorSequenceID,
            "second-behavior"
        )
        XCTAssertEqual(
            updatedStatuses[secondID]?.currentSpeechText,
            "두 번째 펫"
        )

        let firstContext = try XCTUnwrap(harness.registry.contexts[firstID])
        XCTAssertTrue(firstContext.requestPettingInteraction())
        XCTAssertTrue(
            statusMap(harness.manager)[firstID]?
                .isPettingInteractionActive == true
        )
        XCTAssertFalse(
            statusMap(harness.manager)[secondID]?
                .isPettingInteractionActive == true
        )
        XCTAssertEqual(
            statusMap(harness.manager)[secondID]?.currentSpeechText,
            "두 번째 펫"
        )

        let tuckedFirstSettings = updatedSettings.replacingPresentation(
            .tuckedAway,
            for: firstID
        )
        try synchronize(
            harness: harness,
            settings: tuckedFirstSettings,
            reason: .settingsChange
        )
        XCTAssertFalse(statusMap(harness.manager)[firstID]?.isAwake == true)
        XCTAssertNil(statusMap(harness.manager)[firstID]?.currentSpeechText)
        XCTAssertTrue(statusMap(harness.manager)[secondID]?.isAwake == true)
        XCTAssertEqual(
            statusMap(harness.manager)[secondID]?.currentSpeechText,
            "두 번째 펫"
        )
    }

    func testSharedActivitySnapshotResolvesDifferentAutomaticRules() throws {
        let firstID = UUID(
            uuidString: "50000000-0000-0000-0000-000000000001"
        )!
        let secondID = UUID(
            uuidString: "50000000-0000-0000-0000-000000000002"
        )!
        let firstProfileID = UUID(
            uuidString: "60000000-0000-0000-0000-000000000001"
        )!
        let secondProfileID = UUID(
            uuidString: "60000000-0000-0000-0000-000000000002"
        )!
        let specifications = [
            RuntimeSpecification(
                instanceID: firstID,
                profileID: firstProfileID,
                sequenceID: "editor-rule",
                speechText: nil,
                movementMode: .fixed
            ),
            RuntimeSpecification(
                instanceID: secondID,
                profileID: secondProfileID,
                sequenceID: "idle-rule",
                speechText: nil,
                movementMode: .fixed
            )
        ]
        let baseSettings = makeSettings(specifications: specifications)
        let settings = AppSettings(
            selectedPetInstanceID: firstID,
            activePetInstances: baseSettings.activePetInstances,
            petBehaviorProfiles: [
                PetBehaviorProfileSettings(
                    profileID: firstProfileID,
                    profile: automaticProfile(
                        sequenceID: "editor-rule",
                        condition: .application(
                            bundleIdentifier: "com.example.Editor"
                        )
                    )
                ),
                PetBehaviorProfileSettings(
                    profileID: secondProfileID,
                    profile: automaticProfile(
                        sequenceID: "idle-rule",
                        condition: .idleAtLeast(milliseconds: 5_000)
                    )
                )
            ]
        )
        let harness = makeHarness()
        defer { harness.manager.stopAll() }
        try synchronize(
            harness: harness,
            settings: settings,
            reason: .initialLoad(shouldRestorePosition: true)
        )

        harness.manager.updateActivitySnapshot(
            ActivitySnapshot(
                capturedAt: ContinuousClock().now,
                idleDuration: .seconds(10),
                frontmostApplicationID: "com.example.Editor",
                isScreenLocked: false,
                isSystemSleeping: false
            )
        )

        let statuses = statusMap(harness.manager)
        XCTAssertEqual(
            statuses[firstID]?.currentBehaviorSequenceID,
            "editor-rule"
        )
        XCTAssertEqual(
            statuses[secondID]?.currentBehaviorSequenceID,
            "idle-rule"
        )
    }

    func testFourMovementModesKeepIndependentRuntimeStates() throws {
        let specifications = PetMovementMode.allTestModes.enumerated().map {
            index, mode in
            RuntimeSpecification(
                instanceID: UUID(
                    uuidString: String(
                        format: "30000000-0000-0000-0000-%012d",
                        index + 1
                    )
                )!,
                profileID: UUID(
                    uuidString: String(
                        format: "40000000-0000-0000-0000-%012d",
                        index + 1
                    )
                )!,
                sequenceID: "behavior-\(index)",
                speechText: nil,
                movementMode: mode
            )
        }
        let settings = makeSettings(specifications: specifications)
        let harness = makeHarness()
        defer { harness.manager.stopAll() }

        try synchronize(
            harness: harness,
            settings: settings,
            reason: .initialLoad(shouldRestorePosition: true)
        )
        harness.manager.updateActivitySnapshot(activeSnapshot())

        let statuses = statusMap(harness.manager)
        XCTAssertEqual(
            statuses[specifications[0].instanceID]?.movementState,
            .inactive
        )
        XCTAssertEqual(
            statuses[specifications[1].instanceID]?.movementState,
            .cursorFollowing
        )
        XCTAssertEqual(
            statuses[specifications[2].instanceID]?.movementState,
            .freeRoamingMoving
        )
        XCTAssertEqual(
            statuses[specifications[3].instanceID]?.movementState,
            .cursorAvoidingIdle
        )

        let followingContext = try XCTUnwrap(
            harness.registry.contexts[specifications[1].instanceID]
        )
        let avoidingContext = try XCTUnwrap(
            harness.registry.contexts[specifications[3].instanceID]
        )
        XCTAssertTrue(followingContext.requestPettingInteraction())
        XCTAssertFalse(avoidingContext.requestPettingInteraction())

        let freeRoamingProfileID = specifications[2].profileID
        let updatedSettings = replacingProfile(
            freeRoamingProfileID,
            in: settings,
            with: profile(
                sequenceID: specifications[2].sequenceID,
                speechText: nil,
                movementMode: .fixed
            )
        )
        try synchronize(
            harness: harness,
            settings: updatedSettings,
            reason: .settingsChange
        )

        let updatedStatuses = statusMap(harness.manager)
        XCTAssertEqual(
            updatedStatuses[specifications[1].instanceID]?.movementState,
            .cursorFollowing
        )
        XCTAssertEqual(
            updatedStatuses[specifications[2].instanceID]?.movementMode,
            .fixed
        )
        XCTAssertEqual(
            updatedStatuses[specifications[2].instanceID]?.movementState,
            .inactive
        )
        XCTAssertEqual(
            updatedStatuses[specifications[3].instanceID]?.movementState,
            .cursorAvoidingIdle
        )
    }

    private struct RuntimeSpecification {
        let instanceID: UUID
        let profileID: UUID
        let sequenceID: String
        let speechText: String?
        let movementMode: PetMovementMode
    }

    private struct RuntimeHarness {
        let manager: PetInstanceManager
        let registry: ContextRegistry
        let item: PetLibraryItem
    }

    private final class ContextRegistry {
        var contexts: [UUID: PetRuntimeContext] = [:]
    }

    private func makeHarness() -> RuntimeHarness {
        let environment = StaticPetDesktopEnvironmentProvider(
            snapshot: PetDesktopEnvironmentSnapshot(
                pointerLocation: PetMovementPoint(x: 1_000, y: 600),
                displays: [
                    PetDesktopDisplaySnapshot(
                        id: "test-display",
                        name: "테스트 화면",
                        frame: PetMovementRect(
                            x: 0,
                            y: 0,
                            width: 2_000,
                            height: 1_200
                        ),
                        visibleFrame: PetMovementRect(
                            x: 0,
                            y: 0,
                            width: 2_000,
                            height: 1_160
                        )
                    )
                ]
            )
        )
        let cache = PetPresentationResourceCache()
        let bootstrap = PetWindowController(
            environmentProvider: environment,
            resourceCache: cache
        )
        let item = builtInItem(definition: bootstrap.petDefinition)
        let registry = ContextRegistry()
        var availableBootstrap: PetWindowController? = bootstrap
        let frontmostWindowProvider = FrontmostWindowProvider(
            frontmostPIDProvider: { nil },
            displayLayoutProvider: {
                environment.currentSnapshot.displayLayout
            }
        )
        let manager = PetInstanceManager { instanceID in
            let windowController = availableBootstrap ?? PetWindowController(
                environmentProvider: environment,
                resourceCache: cache
            )
            availableBootstrap = nil
            let context = PetRuntimeContext(
                instanceID: instanceID,
                petWindowController: windowController,
                environmentProvider: environment,
                frontmostWindowProvider: frontmostWindowProvider
            )
            registry.contexts[instanceID] = context
            return context
        }
        return RuntimeHarness(
            manager: manager,
            registry: registry,
            item: item
        )
    }

    private func synchronize(
        harness: RuntimeHarness,
        settings: AppSettings,
        reason: PetOverlayApplicationReason
    ) throws {
        try harness.manager.synchronizeActiveRuntimes(
            settings: settings,
            itemProvider: { _ in harness.item },
            reason: reason
        )
    }

    private func statusMap(
        _ manager: PetInstanceManager
    ) -> [UUID: PetRuntimeStatus] {
        Dictionary(
            uniqueKeysWithValues: manager.runtimeStatuses.map {
                ($0.instanceID, $0)
            }
        )
    }

    private func makeSettings(
        specifications: [RuntimeSpecification]
    ) -> AppSettings {
        AppSettings(
            selectedPetInstanceID: specifications[0].instanceID,
            activePetInstances: specifications.enumerated().map {
                index, specification in
                PetInstanceSettings(
                    instanceID: specification.instanceID,
                    petKey: .builtIn,
                    nickname: "테스트 펫 \(index + 1)",
                    presentation: .awake,
                    overlay: OverlaySettings(
                        screenIdentifier: "test-display",
                        originX: Double(80 + (index * 240)),
                        originY: 80,
                        width: 192,
                        clickThrough: false
                    ),
                    behaviorProfileID: specification.profileID,
                    displayOrder: index
                )
            },
            petBehaviorProfiles: specifications.map { specification in
                PetBehaviorProfileSettings(
                    profileID: specification.profileID,
                    profile: profile(
                        sequenceID: specification.sequenceID,
                        speechText: specification.speechText,
                        movementMode: specification.movementMode
                    )
                )
            }
        )
    }

    private func profile(
        sequenceID: String,
        speechText: String?,
        movementMode: PetMovementMode
    ) -> BehaviorProfile {
        let speech = PetSpeechSettings(
            isEnabled: speechText != nil,
            periodicIsEnabled: false,
            phrases: speechText.map {
                [
                    PetSpeechPhrase(
                        text: $0,
                        trigger: .sequence(sequenceID),
                        displayMode: .untilNextPhrase
                    )
                ]
            } ?? []
        )
        return BehaviorProfile(
            petKey: .builtIn,
            mode: .manual,
            manualSequenceID: sequenceID,
            sequences: [
                BehaviorSequence(
                    id: sequenceID,
                    steps: [
                        BehaviorStep(
                            motionID: PetMotionReference.currentPetDefault,
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: movementSettings(mode: movementMode),
            pettingMotionID: "idle",
            speech: speech
        )
    }

    private func movementSettings(
        mode: PetMovementMode
    ) -> PetMovementSettings {
        PetMovementSettings(
            mode: mode,
            speed: 160,
            cursorDistance: 96,
            stopRadius: 16,
            freeRoamingDwellMilliseconds: 6_000,
            prefersFrontmostWindow: false,
            cursorAvoidingIdleBehavior: .stationary,
            cursorAvoidingDetectionDistance: 160,
            cursorAvoidingSpeed: 240
        )
    }

    private func automaticProfile(
        sequenceID: String,
        condition: RuleCondition
    ) -> BehaviorProfile {
        BehaviorProfile(
            petKey: .builtIn,
            mode: .automatic,
            manualSequenceID: nil,
            sequences: [
                BehaviorSequence(
                    id: sequenceID,
                    steps: [
                        BehaviorStep(
                            motionID: PetMotionReference.currentPetDefault,
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            ],
            automaticRules: [
                AutomaticRule(
                    id: UUID(),
                    isEnabled: true,
                    priority: 10,
                    condition: condition,
                    sequenceID: sequenceID
                )
            ],
            movement: .default,
            pettingMotionID: "idle",
            speech: .default
        )
    }

    private func replacingProfile(
        _ profileID: UUID,
        in settings: AppSettings,
        with profile: BehaviorProfile
    ) -> AppSettings {
        AppSettings(
            selectedPetInstanceID: settings.selectedPetInstanceID,
            activePetInstances: settings.activePetInstances,
            petBehaviorProfiles: settings.petBehaviorProfiles.map { record in
                record.profileID == profileID
                    ? PetBehaviorProfileSettings(
                        profileID: profileID,
                        profile: profile
                    )
                    : record
            }
        )
    }

    private func activeSnapshot() -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: ContinuousClock().now,
            idleDuration: .zero,
            frontmostApplicationID: "com.example.Editor",
            isScreenLocked: false,
            isSystemSleeping: false
        )
    }

    private func builtInItem(
        definition: PetDefinition
    ) -> PetLibraryItem {
        PetLibraryItem(
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

private extension PetMovementMode {
    static let allTestModes: [PetMovementMode] = [
        .fixed,
        .cursorFollowing,
        .freeRoaming,
        .cursorAvoiding
    ]
}
