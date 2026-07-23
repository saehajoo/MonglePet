import Foundation

@MainActor
final class PetPlaybackCoordinator {
    private static let movementSequenceID = "__monglepet_movement__"

    private var petDefinition: PetDefinition
    private var behaviorPlayback: ScheduledMotion?
    private var movementActivity = PetMovementActivity.stationary
    private let onPlaybackChange: (ScheduledMotion?) -> Void
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?

    init(
        petDefinition: PetDefinition,
        onPlaybackChange: @escaping (ScheduledMotion?) -> Void
    ) {
        self.petDefinition = petDefinition
        self.onPlaybackChange = onPlaybackChange
    }

    func replacePetDefinition(_ petDefinition: PetDefinition) {
        self.petDefinition = petDefinition
        behaviorPlayback = nil
        movementActivity = .stationary
        currentPlayback = nil
        hasEmittedPlayback = false
    }

    func setBehaviorPlayback(_ playback: ScheduledMotion?) {
        behaviorPlayback = playback
        refresh()
    }

    func setMovementActivity(_ activity: PetMovementActivity) {
        movementActivity = activity
        refresh()
    }

    private func refresh() {
        emit(effectivePlayback)
    }

    private var effectivePlayback: ScheduledMotion? {
        if behaviorPlayback?.isInteraction == true {
            return behaviorPlayback
        }
        return movementPlayback ?? behaviorPlayback
    }

    private var movementPlayback: ScheduledMotion? {
        guard
            movementActivity.isMoving,
            let motionID = movementActivity.motionID,
            let motion = petDefinition.motion(id: motionID)
        else {
            return nil
        }

        let loopingMotion = PetMotion(
            id: motion.id,
            loops: true,
            frames: motion.frames
        )
        return ScheduledMotion(
            sequenceID: Self.movementSequenceID,
            stepIndex: 0,
            requestedMotionID: motionID,
            motion: loopingMotion,
            playbackSpeed: 1,
            isInteraction: false
        )
    }

    private func emit(_ playback: ScheduledMotion?) {
        guard !hasEmittedPlayback || playback != currentPlayback else {
            return
        }
        hasEmittedPlayback = true
        currentPlayback = playback
        onPlaybackChange(playback)
    }
}
