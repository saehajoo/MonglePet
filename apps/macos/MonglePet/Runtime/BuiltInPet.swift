nonisolated struct BuiltInPetAtlasDescriptor: Equatable, Sendable {
    let id: String
    let imageName: String
    let pixelSize: PixelSize
}

nonisolated enum BuiltInPet {
    static let id = "kr.mapleroom.monglepet.builtin.mongle"
    static let displayName = "몽글이"
    static let version = "1.0.1"
    static let author = "운영자"
    static let description = "MonglePet에서 기본으로 제공되는 몽글펫입니다."

    static let atlasID = "default"
    static let defaultMotionID = "기본"
    static let frameSize = PixelSize(width: 150, height: 150)

    static let atlasDescriptors = [
        descriptor(id: "default", imageName: "BuiltInMongleDefault", frameCount: 7),
        descriptor(id: "up", imageName: "BuiltInMongleUp", frameCount: 4),
        descriptor(id: "working", imageName: "BuiltInMongleWorking", frameCount: 7),
        descriptor(id: "front", imageName: "BuiltInMongleFront", frameCount: 6),
        descriptor(id: "sleeping", imageName: "BuiltInMongleSleeping", frameCount: 2),
        descriptor(id: "spouting", imageName: "BuiltInMongleSpouting", frameCount: 2),
        descriptor(id: "searching", imageName: "BuiltInMongleSearching", frameCount: 2),
        descriptor(id: "happy", imageName: "BuiltInMongleHappy", frameCount: 2),
        descriptor(id: "right", imageName: "BuiltInMongleRight", frameCount: 1),
        descriptor(id: "bubbles", imageName: "BuiltInMongleBubbles", frameCount: 3)
    ]

    static func mongleDefinition() -> PetDefinition {
        PetDefinition(
            id: id,
            displayName: displayName,
            defaultMotionID: defaultMotionID,
            motions: [
                motion(
                    id: defaultMotionID,
                    atlasID: "default",
                    durations: Array(repeating: 450, count: 7)
                ),
                motion(
                    id: "위로",
                    atlasID: "up",
                    durations: Array(repeating: 450, count: 4)
                ),
                motion(
                    id: "일하는 중",
                    atlasID: "working",
                    durations: Array(repeating: 450, count: 7)
                ),
                motion(
                    id: "정면",
                    atlasID: "front",
                    durations: Array(repeating: 450, count: 6)
                ),
                motion(
                    id: "자는중",
                    atlasID: "sleeping",
                    durations: [450, 3_000]
                ),
                motion(
                    id: "물뿜기",
                    atlasID: "spouting",
                    durations: [450, 450]
                ),
                motion(
                    id: "찾는 중",
                    atlasID: "searching",
                    durations: [450, 450]
                ),
                motion(
                    id: "해피",
                    atlasID: "happy",
                    durations: [450, 450]
                ),
                motion(
                    id: "오른쪽",
                    atlasID: "right",
                    durations: [450]
                ),
                motion(
                    id: "보글보글",
                    atlasID: "bubbles",
                    durations: [450, 450, 450]
                )
            ]
        )
    }

    private static func descriptor(
        id: String,
        imageName: String,
        frameCount: Int
    ) -> BuiltInPetAtlasDescriptor {
        BuiltInPetAtlasDescriptor(
            id: id,
            imageName: imageName,
            pixelSize: PixelSize(
                width: frameSize.width * frameCount,
                height: frameSize.height
            )
        )
    }

    private static func motion(
        id: String,
        atlasID: String,
        durations: [Int64]
    ) -> PetMotion {
        PetMotion(
            id: id,
            loops: true,
            frames: durations.enumerated().map { index, duration in
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: PixelRect(
                        x: index * frameSize.width,
                        y: 0,
                        width: frameSize.width,
                        height: frameSize.height
                    ),
                    duration: .milliseconds(duration)
                )
            }
        )
    }
}
