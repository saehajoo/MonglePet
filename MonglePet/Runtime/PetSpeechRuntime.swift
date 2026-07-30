import Foundation

nonisolated struct PetSpeechPresentation: Equatable, Sendable {
    let phraseID: UUID
    let text: String
    let displayDurationMilliseconds: Int64
}

@MainActor
protocol PetSpeechScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping () -> Void)
    func cancel()
}

@MainActor
final class RunLoopPetSpeechScheduler: NSObject, PetSpeechScheduling {
    private var timer: Timer?
    private var action: (() -> Void)?

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        cancel()
        self.action = action
        let timer = Timer(
            timeInterval: max(delay.timeInterval, 0.001),
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    @objc
    private func timerDidFire() {
        timer = nil
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}

@MainActor
final class PetSpeechRuntime {
    typealias PhrasePicker = ([PetSpeechPhrase], UUID?) -> PetSpeechPhrase?

    private var settings: PetSpeechSettings = .default
    private let scheduler: any PetSpeechScheduling
    private let phrasePicker: PhrasePicker
    private let onPresentationChange: (PetSpeechPresentation?) -> Void
    private var isAwake = false
    private var isSystemSuspended = false
    private var lastSequenceID: String?
    private var lastPeriodicPhraseID: UUID?

    init(
        scheduler: any PetSpeechScheduling = RunLoopPetSpeechScheduler(),
        phrasePicker: @escaping PhrasePicker = { phrases, excludedID in
            let candidates: [PetSpeechPhrase]
            if phrases.count > 1, let excludedID {
                candidates = phrases.filter { $0.id != excludedID }
            } else {
                candidates = phrases
            }
            return candidates.randomElement()
        },
        onPresentationChange: @escaping (PetSpeechPresentation?) -> Void
    ) {
        self.scheduler = scheduler
        self.phrasePicker = phrasePicker
        self.onPresentationChange = onPresentationChange
    }

    func update(settings: PetSpeechSettings) {
        guard settings != self.settings else {
            return
        }
        self.settings = settings
        lastSequenceID = nil
        lastPeriodicPhraseID = nil
        onPresentationChange(nil)
        scheduleNextPeriodicPresentation()
    }

    func setAwake(_ isAwake: Bool) {
        guard isAwake != self.isAwake else {
            return
        }
        self.isAwake = isAwake
        if isAwake {
            scheduleNextPeriodicPresentation()
        } else {
            scheduler.cancel()
            onPresentationChange(nil)
            lastSequenceID = nil
        }
    }

    func setSystemSuspended(_ isSuspended: Bool) {
        guard isSuspended != isSystemSuspended else {
            return
        }
        isSystemSuspended = isSuspended
        if isSuspended {
            scheduler.cancel()
            onPresentationChange(nil)
            lastSequenceID = nil
        } else {
            scheduleNextPeriodicPresentation()
        }
    }

    func behaviorSequenceDidChange(_ sequenceID: String?) {
        guard sequenceID != lastSequenceID else {
            return
        }
        lastSequenceID = sequenceID
        guard
            canPresent,
            let sequenceID,
            let phrase = phrasePicker(
                settings.phrases.filter {
                    $0.trigger == .sequence(sequenceID)
                },
                nil
            )
        else {
            return
        }
        present(phrase)
    }

    func stop() {
        scheduler.cancel()
        onPresentationChange(nil)
        settings = .default
        isAwake = false
        isSystemSuspended = false
        lastSequenceID = nil
        lastPeriodicPhraseID = nil
    }

    private var canPresent: Bool {
        settings.isEnabled && isAwake && !isSystemSuspended
    }

    private func scheduleNextPeriodicPresentation() {
        scheduler.cancel()
        guard
            canPresent,
            settings.phrases.contains(where: { $0.trigger == .periodic })
        else {
            return
        }
        scheduler.schedule(
            after: .milliseconds(settings.periodicIntervalMilliseconds)
        ) { [weak self] in
            self?.periodicTimerDidFire()
        }
    }

    private func periodicTimerDidFire() {
        guard canPresent else {
            scheduler.cancel()
            return
        }
        let phrases = settings.phrases.filter { $0.trigger == .periodic }
        if let phrase = phrasePicker(phrases, lastPeriodicPhraseID) {
            lastPeriodicPhraseID = phrase.id
            present(phrase)
        }
        scheduleNextPeriodicPresentation()
    }

    private func present(_ phrase: PetSpeechPhrase) {
        onPresentationChange(
            PetSpeechPresentation(
                phraseID: phrase.id,
                text: phrase.text,
                displayDurationMilliseconds:
                    phrase.displayDurationMilliseconds
            )
        )
    }

}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds)
                / 1_000_000_000_000_000_000
    }
}
