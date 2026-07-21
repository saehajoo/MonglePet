nonisolated enum BuiltInPet {
    static let atlasID = "main"

    static func mongleDefinition(atlasPixelSize: PixelSize) -> PetDefinition {
        let fullFrame = PixelRect(
            x: 0,
            y: 0,
            width: atlasPixelSize.width,
            height: atlasPixelSize.height
        )
        let breathingFrame = inset(
            fullFrame,
            horizontal: max(atlasPixelSize.width / 100, 1),
            top: max(atlasPixelSize.height / 160, 1),
            bottom: max(atlasPixelSize.height / 120, 1)
        )
        let idle = PetMotion(
            id: "idle",
            loops: true,
            frames: [
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: fullFrame,
                    duration: .milliseconds(1_100)
                ),
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: breathingFrame,
                    duration: .milliseconds(300)
                )
            ]
        )

        return PetDefinition(
            id: "kr.mapleroom.monglepet.builtin.mongle",
            displayName: "몽글이",
            defaultMotionID: idle.id,
            motions: [idle]
        )
    }

    private static func inset(
        _ rect: PixelRect,
        horizontal: Int,
        top: Int,
        bottom: Int
    ) -> PixelRect {
        PixelRect(
            x: rect.x + horizontal,
            y: rect.y + top,
            width: rect.width - (horizontal * 2),
            height: rect.height - top - bottom
        )
    }
}
