nonisolated struct PixelRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func isContained(in pixelSize: PixelSize) -> Bool {
        x >= 0
            && y >= 0
            && width > 0
            && height > 0
            && x <= pixelSize.width - width
            && y <= pixelSize.height - height
    }
}

nonisolated struct PixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

nonisolated struct MotionFrame: Equatable, Sendable {
    let atlasID: String
    let sourceRect: PixelRect
    let duration: Duration
}

nonisolated struct PetMotion: Equatable, Identifiable, Sendable {
    let id: String
    let loops: Bool
    let frames: [MotionFrame]

    var cycleDuration: Duration? {
        guard !frames.isEmpty, frames.allSatisfy({ $0.duration > .zero }) else {
            return nil
        }

        let duration = frames.reduce(Duration.zero) { partialResult, frame in
            partialResult + frame.duration
        }
        return duration > .zero ? duration : nil
    }
}

nonisolated enum PetMotionReference {
    static let currentPetDefault = "__monglepet_current_pet_default__"
}

nonisolated struct PetDefinition: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let defaultMotionID: String
    let motions: [PetMotion]

    func motion(id: String) -> PetMotion? {
        motions.first { $0.id == id }
    }

    var defaultMotion: PetMotion? {
        motion(id: defaultMotionID) ?? motion(id: "idle") ?? motions.first
    }
}
