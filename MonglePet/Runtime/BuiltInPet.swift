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
        let focusedFrame = inset(
            fullFrame,
            horizontal: max(atlasPixelSize.width / 140, 1),
            top: max(atlasPixelSize.height / 90, 1),
            bottom: max(atlasPixelSize.height / 180, 1)
        )
        let restingFrame = inset(
            fullFrame,
            horizontal: max(atlasPixelSize.width / 80, 1),
            top: max(atlasPixelSize.height / 180, 1),
            bottom: max(atlasPixelSize.height / 70, 1)
        )
        let sleepingFrame = inset(
            fullFrame,
            horizontal: max(atlasPixelSize.width / 55, 1),
            top: max(atlasPixelSize.height / 150, 1),
            bottom: max(atlasPixelSize.height / 45, 1)
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
        let focus = PetMotion(
            id: "focus",
            loops: true,
            frames: [
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: fullFrame,
                    duration: .milliseconds(320)
                ),
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: focusedFrame,
                    duration: .milliseconds(180)
                )
            ]
        )
        let rest = PetMotion(
            id: "rest",
            loops: true,
            frames: [
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: fullFrame,
                    duration: .milliseconds(1_600)
                ),
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: restingFrame,
                    duration: .milliseconds(650)
                )
            ]
        )
        let sleep = PetMotion(
            id: "sleep",
            loops: true,
            frames: [
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: sleepingFrame,
                    duration: .milliseconds(2_800)
                ),
                MotionFrame(
                    atlasID: atlasID,
                    sourceRect: restingFrame,
                    duration: .milliseconds(900)
                )
            ]
        )

        return PetDefinition(
            id: "kr.mapleroom.monglepet.builtin.mongle",
            displayName: "몽글이",
            defaultMotionID: idle.id,
            motions: [idle, focus, rest, sleep]
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
