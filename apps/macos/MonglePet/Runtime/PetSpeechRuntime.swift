import Foundation

nonisolated struct PetSpeechPresentation: Equatable, Sendable {
    let phraseID: UUID
    let text: String
    let displayDurationMilliseconds: Int64
    let theme: PetSpeechBubbleTheme
    let placement: PetSpeechBubblePlacementSettings

    init(
        phraseID: UUID,
        text: String,
        displayDurationMilliseconds: Int64,
        theme: PetSpeechBubbleTheme = .default,
        placement: PetSpeechBubblePlacementSettings = .default
    ) {
        self.phraseID = phraseID
        self.text = text
        self.displayDurationMilliseconds = displayDurationMilliseconds
        self.theme = theme
        self.placement = placement
    }
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

    private enum PresentationSource: Equatable {
        case periodic
        case behavior(String)
    }

    private struct ActivePresentation {
        let presentation: PetSpeechPresentation
        let source: PresentationSource
        let displayMode: PetSpeechDisplayMode
    }

    private var settings: PetSpeechSettings = .default
    private let periodicScheduler: any PetSpeechScheduling
    private let dismissalScheduler: any PetSpeechScheduling
    private let phrasePicker: PhrasePicker
    private let onPresentationChange: (PetSpeechPresentation?) -> Void
    private var isAwake = false
    private var isSystemSuspended = false
    private var lastSequenceID: String?
    private var lastPeriodicPhraseID: UUID?
    private var lastBehaviorPhraseIDs: [String: UUID] = [:]
    private var activePresentation: ActivePresentation?
    private var isPeriodicScheduled = false
    private var isDismissalScheduled = false

    init(
        scheduler: any PetSpeechScheduling = RunLoopPetSpeechScheduler(),
        dismissalScheduler: any PetSpeechScheduling =
            RunLoopPetSpeechScheduler(),
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
        periodicScheduler = scheduler
        self.dismissalScheduler = dismissalScheduler
        self.phrasePicker = phrasePicker
        self.onPresentationChange = onPresentationChange
    }

    func update(settings: PetSpeechSettings) {
        guard settings != self.settings else {
            return
        }
        self.settings = settings
        cancelPeriodic()
        cancelDismissal()
        lastSequenceID = nil
        lastPeriodicPhraseID = nil
        lastBehaviorPhraseIDs = [:]
        dismissCurrentPresentation()
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
            cancelPeriodic()
            cancelDismissal()
            dismissCurrentPresentation()
            lastSequenceID = nil
        }
    }

    func setSystemSuspended(_ isSuspended: Bool) {
        guard isSuspended != isSystemSuspended else {
            return
        }
        isSystemSuspended = isSuspended
        if isSuspended {
            cancelPeriodic()
            cancelDismissal()
            dismissCurrentPresentation()
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
        guard canPresent else {
            return
        }

        if let sequenceID,
           let phrase = behaviorPhrase(for: sequenceID) {
            lastBehaviorPhraseIDs[sequenceID] = phrase.id
            present(phrase, source: .behavior(sequenceID))
            return
        }

        if settings.behaviorChangePolicy == .dismiss {
            dismissCurrentPresentation()
            scheduleNextPeriodicPresentation()
            return
        }

        guard let activePresentation else {
            ensurePeriodicPresentationScheduled()
            return
        }
        if case .behavior = activePresentation.source,
           activePresentation.displayMode == .untilNextPhrase {
            scheduleNextPeriodicPresentation()
        }
    }

    func stop() {
        cancelPeriodic()
        cancelDismissal()
        dismissCurrentPresentation()
        settings = .default
        isAwake = false
        isSystemSuspended = false
        lastSequenceID = nil
        lastPeriodicPhraseID = nil
        lastBehaviorPhraseIDs = [:]
    }

    func prepareForPetChange() {
        cancelPeriodic()
        cancelDismissal()
        dismissCurrentPresentation()
        settings = .default
        isAwake = false
        lastSequenceID = nil
        lastPeriodicPhraseID = nil
        lastBehaviorPhraseIDs = [:]
    }

    private var canPresent: Bool {
        settings.isEnabled && isAwake && !isSystemSuspended
    }

    private func scheduleNextPeriodicPresentation() {
        cancelPeriodic()
        guard
            canPresent,
            settings.periodicIsEnabled,
            !settings.periodicPhrases.isEmpty
        else {
            return
        }
        isPeriodicScheduled = true
        periodicScheduler.schedule(
            after: .milliseconds(settings.periodicIntervalMilliseconds)
        ) { [weak self] in
            self?.periodicTimerDidFire()
        }
    }

    private func periodicTimerDidFire() {
        isPeriodicScheduled = false
        guard canPresent else {
            cancelPeriodic()
            return
        }
        guard let phrase = nextPeriodicPhrase() else {
            return
        }
        lastPeriodicPhraseID = phrase.id
        present(phrase, source: .periodic)
    }

    private func present(
        _ phrase: PetSpeechPhrase,
        source: PresentationSource
    ) {
        cancelDismissal()
        if case .behavior = source {
            cancelPeriodic()
        }
        let presentation = PetSpeechPresentation(
            phraseID: phrase.id,
            text: phrase.text,
            displayDurationMilliseconds:
                phrase.displayDurationMilliseconds,
            theme: settings.theme,
            placement: settings.placement
        )
        activePresentation = ActivePresentation(
            presentation: presentation,
            source: source,
            displayMode: phrase.displayMode
        )
        onPresentationChange(presentation)

        switch phrase.displayMode {
        case .timed:
            scheduleDismissal(
                phraseID: phrase.id,
                after: phrase.displayDurationMilliseconds
            )
        case .untilNextPhrase:
            scheduleNextPeriodicPresentation()
        }
    }

    private func scheduleDismissal(
        phraseID: UUID,
        after milliseconds: Int64
    ) {
        cancelDismissal()
        isDismissalScheduled = true
        dismissalScheduler.schedule(
            after: .milliseconds(milliseconds)
        ) { [weak self] in
            self?.dismissalTimerDidFire(for: phraseID)
        }
    }

    private func dismissalTimerDidFire(for phraseID: UUID) {
        isDismissalScheduled = false
        guard activePresentation?.presentation.phraseID == phraseID else {
            return
        }
        dismissCurrentPresentation()
        scheduleNextPeriodicPresentation()
    }

    private func dismissCurrentPresentation() {
        cancelDismissal()
        guard activePresentation != nil else {
            return
        }
        activePresentation = nil
        onPresentationChange(nil)
    }

    private func ensurePeriodicPresentationScheduled() {
        guard !isPeriodicScheduled else {
            return
        }
        scheduleNextPeriodicPresentation()
    }

    private func cancelPeriodic() {
        periodicScheduler.cancel()
        isPeriodicScheduled = false
    }

    private func cancelDismissal() {
        dismissalScheduler.cancel()
        isDismissalScheduled = false
    }

    private func behaviorPhrase(
        for sequenceID: String
    ) -> PetSpeechPhrase? {
        phrasePicker(
            settings.behaviorPhrases.filter {
                $0.trigger == .sequence(sequenceID)
            },
            lastBehaviorPhraseIDs[sequenceID]
        )
    }

    private func nextPeriodicPhrase() -> PetSpeechPhrase? {
        let phrases = settings.periodicPhrases
        switch settings.periodicOrder {
        case .random:
            return phrasePicker(phrases, lastPeriodicPhraseID)
        case .sequential:
            guard
                let lastPeriodicPhraseID,
                let index = phrases.firstIndex(
                    where: { $0.id == lastPeriodicPhraseID }
                )
            else {
                return phrases.first
            }
            let nextIndex = phrases.index(after: index)
            return nextIndex == phrases.endIndex
                ? phrases.first
                : phrases[nextIndex]
        }
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
