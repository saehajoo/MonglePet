import XCTest
@testable import MonglePet

@MainActor
final class PetSpeechRuntimeTests: XCTestCase {
    func testPeriodicSpeechUsesOneShotTimerAndReschedules() throws {
        let periodicScheduler = ManualPetSpeechScheduler()
        let dismissalScheduler = ManualPetSpeechScheduler()
        var presentations: [PetSpeechPresentation?] = []
        let phrase = PetSpeechPhrase(
            id: UUID(
                uuidString: "10000000-0000-0000-0000-000000000001"
            )!,
            text: "잠깐 쉬어 갈까요?",
            displayDurationMilliseconds: 4_000,
            trigger: .periodic
        )
        let theme = PetSpeechBubbleTheme(
            colorStyle: .midnight,
            fontSize: 16,
            showsTail: true,
            tailAlignment: .leading
        )
        let placement = PetSpeechBubblePlacementSettings(
            preferredPosition: .below,
            horizontalOffset: 32,
            gap: 14
        )
        let runtime = PetSpeechRuntime(
            scheduler: periodicScheduler,
            dismissalScheduler: dismissalScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            presentations.append($0)
        }

        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 15_000,
                phrases: [phrase],
                theme: theme,
                placement: placement
            )
        )
        XCTAssertNil(periodicScheduler.scheduledDelay)

        runtime.setAwake(true)
        XCTAssertEqual(periodicScheduler.scheduledDelay, .seconds(15))

        periodicScheduler.fire()

        XCTAssertEqual(
            presentations.compactMap { $0 }.last,
            PetSpeechPresentation(
                phraseID: phrase.id,
                text: phrase.text,
                displayDurationMilliseconds: 4_000,
                theme: theme,
                placement: placement
            )
        )
        XCTAssertNil(periodicScheduler.scheduledDelay)
        XCTAssertEqual(dismissalScheduler.scheduledDelay, .seconds(4))

        dismissalScheduler.fire()

        XCTAssertNil(presentations.last!)
        XCTAssertEqual(periodicScheduler.scheduledDelay, .seconds(15))
    }

    func testSequenceSpeechAppearsOnlyWhenSequenceChanges() {
        let scheduler = ManualPetSpeechScheduler()
        var receivedTexts: [String] = []
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            if let text = $0?.text {
                receivedTexts.append(text)
            }
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                phrases: [
                    PetSpeechPhrase(
                        text: "집중 시작!",
                        trigger: .sequence("focus")
                    ),
                    PetSpeechPhrase(
                        text: "쉬는 시간이에요.",
                        trigger: .sequence("rest")
                    )
                ]
            )
        )
        runtime.setAwake(true)

        runtime.behaviorSequenceDidChange("focus")
        runtime.behaviorSequenceDidChange("focus")
        runtime.behaviorSequenceDidChange("rest")

        XCTAssertEqual(receivedTexts, ["집중 시작!", "쉬는 시간이에요."])
        XCTAssertNil(scheduler.scheduledDelay)
    }

    func testPeriodicSpeechAvoidsImmediatelyRepeatingPhraseWhenPossible() {
        let scheduler = ManualPetSpeechScheduler()
        let first = PetSpeechPhrase(
            text: "첫 번째",
            trigger: .periodic,
            displayMode: .untilNextPhrase
        )
        let second = PetSpeechPhrase(
            text: "두 번째",
            trigger: .periodic,
            displayMode: .untilNextPhrase
        )
        var excludedIDs: [UUID?] = []
        var receivedTexts: [String] = []
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            phrasePicker: { phrases, excludedID in
                excludedIDs.append(excludedID)
                return phrases.first { $0.id != excludedID }
            }
        ) {
            if let text = $0?.text {
                receivedTexts.append(text)
            }
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 10_000,
                phrases: [first, second]
            )
        )
        runtime.setAwake(true)

        scheduler.fire()
        scheduler.fire()

        XCTAssertEqual(receivedTexts, ["첫 번째", "두 번째"])
        XCTAssertEqual(excludedIDs.count, 2)
        XCTAssertNil(excludedIDs[0])
        XCTAssertEqual(excludedIDs[1], first.id)
    }

    func testSleepAndSystemSuspensionCancelAndHideSpeech() {
        let scheduler = ManualPetSpeechScheduler()
        let dismissalScheduler = ManualPetSpeechScheduler()
        var presentations: [PetSpeechPresentation?] = []
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            dismissalScheduler: dismissalScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            presentations.append($0)
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 10_000,
                phrases: [
                    PetSpeechPhrase(text: "안녕하세요!", trigger: .periodic)
                ]
            )
        )
        runtime.setAwake(true)
        XCTAssertEqual(scheduler.scheduledDelay, .seconds(10))
        scheduler.fire()
        XCTAssertNotNil(presentations.last!)
        XCTAssertEqual(dismissalScheduler.scheduledDelay, .seconds(3))

        runtime.setSystemSuspended(true)
        XCTAssertNil(scheduler.scheduledDelay)
        XCTAssertNil(dismissalScheduler.scheduledDelay)
        XCTAssertNil(presentations.last!)

        runtime.setSystemSuspended(false)
        XCTAssertEqual(scheduler.scheduledDelay, .seconds(10))

        runtime.setAwake(false)
        XCTAssertNil(scheduler.scheduledDelay)
        XCTAssertNil(dismissalScheduler.scheduledDelay)
    }

    func testDisabledSpeechDoesNotScheduleOrPresent() {
        let scheduler = ManualPetSpeechScheduler()
        var presentations: [PetSpeechPresentation?] = []
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            presentations.append($0)
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: false,
                phrases: [
                    PetSpeechPhrase(
                        text: "보이면 안 돼요.",
                        trigger: .sequence("focus")
                    )
                ]
            )
        )
        runtime.setAwake(true)
        runtime.behaviorSequenceDidChange("focus")

        XCTAssertNil(scheduler.scheduledDelay)
        XCTAssertTrue(presentations.compactMap { $0 }.isEmpty)
    }

    func testPetChangeDismissesSpeechEvenWhenNextSettingsAreEqual() {
        let periodicScheduler = ManualPetSpeechScheduler()
        let dismissalScheduler = ManualPetSpeechScheduler()
        var presentations: [PetSpeechPresentation?] = []
        let settings = PetSpeechSettings(
            isEnabled: true,
            periodicIsEnabled: true,
            periodicIntervalMilliseconds: 5_000,
            phrases: [
                PetSpeechPhrase(
                    text: "첫 번째 펫의 대사",
                    trigger: .periodic,
                    displayMode: .untilNextPhrase
                )
            ]
        )
        let runtime = PetSpeechRuntime(
            scheduler: periodicScheduler,
            dismissalScheduler: dismissalScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            presentations.append($0)
        }
        runtime.update(settings: settings)
        runtime.setAwake(true)
        periodicScheduler.fire()
        XCTAssertNotNil(presentations.last!)

        runtime.prepareForPetChange()

        XCTAssertNil(presentations.last!)
        XCTAssertNil(periodicScheduler.scheduledDelay)
        XCTAssertNil(dismissalScheduler.scheduledDelay)

        runtime.update(settings: settings)
        runtime.setAwake(true)

        XCTAssertEqual(periodicScheduler.scheduledDelay, .seconds(5))
    }

    func testBehaviorSpeechImmediatelyReplacesPeriodicAndHasPriority() {
        let periodicScheduler = ManualPetSpeechScheduler()
        let dismissalScheduler = ManualPetSpeechScheduler()
        var receivedTexts: [String?] = []
        let runtime = PetSpeechRuntime(
            scheduler: periodicScheduler,
            dismissalScheduler: dismissalScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            receivedTexts.append($0?.text)
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: true,
                periodicIntervalMilliseconds: 10_000,
                phrases: [
                    PetSpeechPhrase(
                        text: "주기 대사",
                        trigger: .periodic,
                        displayMode: .untilNextPhrase
                    ),
                    PetSpeechPhrase(
                        text: "집중 시작",
                        trigger: .sequence("focus"),
                        displayMode: .untilNextPhrase
                    )
                ]
            )
        )
        runtime.setAwake(true)
        periodicScheduler.fire()
        XCTAssertEqual(receivedTexts.last!, "주기 대사")

        runtime.behaviorSequenceDidChange("focus")

        XCTAssertEqual(receivedTexts.last!, "집중 시작")
        XCTAssertNil(periodicScheduler.scheduledDelay)
        periodicScheduler.fire()
        XCTAssertEqual(receivedTexts.last!, "집중 시작")
    }

    func testBehaviorChangeWithoutPhraseUsesDismissPolicy() {
        let periodicScheduler = ManualPetSpeechScheduler()
        var receivedTexts: [String?] = []
        let runtime = PetSpeechRuntime(
            scheduler: periodicScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            receivedTexts.append($0?.text)
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: true,
                periodicIntervalMilliseconds: 8_000,
                behaviorChangePolicy: .dismiss,
                phrases: [
                    PetSpeechPhrase(
                        text: "집중 시작",
                        trigger: .sequence("focus"),
                        displayMode: .untilNextPhrase
                    ),
                    PetSpeechPhrase(
                        text: "주기 대사",
                        trigger: .periodic,
                        displayMode: .untilNextPhrase
                    )
                ]
            )
        )
        runtime.setAwake(true)
        runtime.behaviorSequenceDidChange("focus")

        runtime.behaviorSequenceDidChange("rest")

        XCTAssertNil(receivedTexts.last!)
        XCTAssertEqual(periodicScheduler.scheduledDelay, .seconds(8))
    }

    func testKeepPolicyRetainsBehaviorUntilPeriodicReplacement() {
        let periodicScheduler = ManualPetSpeechScheduler()
        var receivedTexts: [String?] = []
        let runtime = PetSpeechRuntime(
            scheduler: periodicScheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            receivedTexts.append($0?.text)
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: true,
                periodicIntervalMilliseconds: 6_000,
                behaviorChangePolicy: .keep,
                phrases: [
                    PetSpeechPhrase(
                        text: "집중 시작",
                        trigger: .sequence("focus"),
                        displayMode: .untilNextPhrase
                    ),
                    PetSpeechPhrase(
                        text: "다음 이야기",
                        trigger: .periodic,
                        displayMode: .untilNextPhrase
                    )
                ]
            )
        )
        runtime.setAwake(true)
        runtime.behaviorSequenceDidChange("focus")

        runtime.behaviorSequenceDidChange("rest")

        XCTAssertEqual(receivedTexts.last!, "집중 시작")
        XCTAssertEqual(periodicScheduler.scheduledDelay, .seconds(6))

        periodicScheduler.fire()

        XCTAssertEqual(receivedTexts.last!, "다음 이야기")
    }

    func testSequentialPeriodicOrderWrapsToFirstPhrase() {
        let scheduler = ManualPetSpeechScheduler()
        var receivedTexts: [String] = []
        let phrases = ["하나", "둘", "셋"].map {
            PetSpeechPhrase(
                text: $0,
                trigger: .periodic,
                displayMode: .untilNextPhrase
            )
        }
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            phrasePicker: { _, _ in
                XCTFail("순차 재생에서는 무작위 선택기를 사용하지 않아야 합니다.")
                return nil
            }
        ) {
            if let text = $0?.text {
                receivedTexts.append(text)
            }
        }
        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIsEnabled: true,
                periodicIntervalMilliseconds: 5_000,
                periodicOrder: .sequential,
                phrases: phrases
            )
        )
        runtime.setAwake(true)

        scheduler.fire()
        scheduler.fire()
        scheduler.fire()
        scheduler.fire()

        XCTAssertEqual(receivedTexts, ["하나", "둘", "셋", "하나"])
    }
}

@MainActor
private final class ManualPetSpeechScheduler: PetSpeechScheduling {
    private(set) var scheduledDelay: Duration?
    private var action: (() -> Void)?

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        scheduledDelay = delay
        self.action = action
    }

    func cancel() {
        scheduledDelay = nil
        action = nil
    }

    func fire() {
        let pendingAction = action
        scheduledDelay = nil
        action = nil
        pendingAction?()
    }
}
