import XCTest
@testable import MonglePet

@MainActor
final class PetSpeechRuntimeTests: XCTestCase {
    func testPeriodicSpeechUsesOneShotTimerAndReschedules() throws {
        let scheduler = ManualPetSpeechScheduler()
        var presentations: [PetSpeechPresentation?] = []
        let phrase = PetSpeechPhrase(
            id: UUID(
                uuidString: "10000000-0000-0000-0000-000000000001"
            )!,
            text: "잠깐 쉬어 갈까요?",
            displayDurationMilliseconds: 4_000,
            trigger: .periodic
        )
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
            phrasePicker: { phrases, _ in phrases.first }
        ) {
            presentations.append($0)
        }

        runtime.update(
            settings: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 15_000,
                phrases: [phrase]
            )
        )
        XCTAssertNil(scheduler.scheduledDelay)

        runtime.setAwake(true)
        XCTAssertEqual(scheduler.scheduledDelay, .seconds(15))

        scheduler.fire()

        XCTAssertEqual(
            presentations.compactMap { $0 }.last,
            PetSpeechPresentation(
                phraseID: phrase.id,
                text: phrase.text,
                displayDurationMilliseconds: 4_000
            )
        )
        XCTAssertEqual(scheduler.scheduledDelay, .seconds(15))
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
        let first = PetSpeechPhrase(text: "첫 번째", trigger: .periodic)
        let second = PetSpeechPhrase(text: "두 번째", trigger: .periodic)
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
        var presentations: [PetSpeechPresentation?] = []
        let runtime = PetSpeechRuntime(
            scheduler: scheduler,
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

        runtime.setSystemSuspended(true)
        XCTAssertNil(scheduler.scheduledDelay)
        XCTAssertNil(presentations.last!)

        runtime.setSystemSuspended(false)
        XCTAssertEqual(scheduler.scheduledDelay, .seconds(10))

        runtime.setAwake(false)
        XCTAssertNil(scheduler.scheduledDelay)
        XCTAssertNil(presentations.last!)
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
