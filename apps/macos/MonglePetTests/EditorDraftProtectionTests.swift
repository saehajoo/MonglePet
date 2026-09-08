import CoreGraphics
import XCTest
@testable import MonglePet

final class EditorDraftProtectionTests: XCTestCase {
    func testUnchangedAndRevertedDraftCloseWithoutConfirmation() {
        let original = makeSnapshot()
        var gate = EditorDraftCloseGate(initialSnapshot: original)
        XCTAssertTrue(gate.requestClose(currentSnapshot: original))

        var edited = original
        edited.animationName = "수정한 이름"
        XCTAssertFalse(gate.requestClose(currentSnapshot: edited))
        XCTAssertTrue(gate.isConfirmingDiscard)

        edited.animationName = original.animationName
        XCTAssertTrue(gate.requestClose(currentSnapshot: edited))
        XCTAssertFalse(gate.isConfirmingDiscard)
    }

    func testContinueEditingPreservesOriginalComparison() {
        let original = makeSnapshot()
        var edited = original
        edited.petName = "새 펫"
        var gate = EditorDraftCloseGate(initialSnapshot: original)

        XCTAssertFalse(gate.requestClose(currentSnapshot: edited))
        gate.continueEditing()
        XCTAssertFalse(gate.isConfirmingDiscard)
        XCTAssertFalse(gate.requestClose(currentSnapshot: edited))
        XCTAssertTrue(gate.requestClose(currentSnapshot: original))
    }

    func testFrameOrderTimingPlacementAndFlipsRequireConfirmation() {
        let first = frame(index: 0, duration: 450)
        let second = frame(index: 1, duration: 600)
        let original = makeSnapshot(frames: [first, second])
        let alternatives = [
            [second, first],
            [frame(index: 0, duration: 700), second],
            [frame(index: 0, duration: 450, x: 8), second],
            [frame(index: 0, duration: 450, horizontal: true), second],
            [frame(index: 0, duration: 450, vertical: true), second],
            [first],
            [first, first, second]
        ]

        for frames in alternatives {
            var edited = original
            edited.frames = frames
            var gate = EditorDraftCloseGate(initialSnapshot: original)
            XCTAssertFalse(gate.requestClose(currentSnapshot: edited))
            XCTAssertTrue(gate.requestClose(currentSnapshot: original))
        }
    }

    func testMetadataAndBehaviorLinkChangesRequireConfirmation() {
        let original = makeSnapshot()
        let changes: [(inout AnimationEditorDraftSnapshot) -> Void] = [
            { $0.version = "2.0.0" },
            { $0.author = "새 제작자" },
            { $0.petDescription = "새 설명" },
            { $0.newFrameDurationMilliseconds = 500 },
            { $0.behaviorLinkMode = "newBehavior"; $0.newBehaviorName = "새 행동" },
            { $0.behaviorLinkMode = "existingBehavior"; $0.existingBehaviorID = "existing" }
        ]
        for change in changes {
            var edited = original
            change(&edited)
            var gate = EditorDraftCloseGate(initialSnapshot: original)
            XCTAssertFalse(gate.requestClose(currentSnapshot: edited))
        }
    }

    @MainActor
    func testFrameSnapshotIgnoresPreviewCacheButTracksActualPlacement() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        var draft = try XCTUnwrap(UserPetAnimationFrameDraft(
            source: .image(UserPetSourceImage(displayName: "원본", image: image)),
            durationMilliseconds: 450,
            image: image,
            canvasSize: PixelSize(width: 16, height: 16),
            baseScale: 1,
            anchorX: 8,
            anchorBottom: 16
        ))
        let original = draft.editSnapshot

        draft.previewImage = nil
        draft.refreshPreview()
        draft.refreshTransform()
        XCTAssertEqual(draft.editSnapshot, original)

        draft.offsetX = 2
        XCTAssertNotEqual(draft.editSnapshot, original)
        draft.resetPlacement()
        XCTAssertEqual(draft.editSnapshot, original)

        draft.flipsHorizontally = true
        draft.refreshTransform()
        XCTAssertNotEqual(draft.editSnapshot, original)
        draft.resetFlips()
        XCTAssertEqual(draft.editSnapshot, original)
    }

    func testExistingFrameSelectionCanReturnToUnchangedState() {
        var gate = EditorDraftCloseGate(initialSnapshot: [ExistingPetFrameID]())
        let selected = [ExistingPetFrameID(motionID: "걷기", frameIndex: 0)]
        XCTAssertFalse(gate.requestClose(currentSnapshot: selected))
        gate.continueEditing()
        XCTAssertTrue(gate.requestClose(currentSnapshot: []))
    }

    func testSpeechThemeAndPlacementAreBothProtected() {
        let original = SpeechBubbleEditorDraftSnapshot(theme: .default, placement: .default)
        var gate = EditorDraftCloseGate(initialSnapshot: original)
        XCTAssertTrue(gate.requestClose(currentSnapshot: original))

        let changedTheme = SpeechBubbleEditorDraftSnapshot(
            theme: PetSpeechBubbleTheme(colorStyle: .system, showsTail: true),
            placement: .default
        )
        XCTAssertFalse(gate.requestClose(currentSnapshot: changedTheme))
        gate.continueEditing()

        let changedPlacement = SpeechBubbleEditorDraftSnapshot(
            theme: .default,
            placement: PetSpeechBubblePlacementSettings(
                preferredPosition: .above, horizontalOffset: 8, gap: 12
            )
        )
        XCTAssertFalse(gate.requestClose(currentSnapshot: changedPlacement))
        XCTAssertTrue(gate.requestClose(currentSnapshot: original))
    }

    private func makeSnapshot(
        frames: [UserPetAnimationFrameRequest] = []
    ) -> AnimationEditorDraftSnapshot {
        AnimationEditorDraftSnapshot(
            animationName: "기본",
            newFrameDurationMilliseconds: 450,
            frames: frames
        )
    }

    private func frame(
        index: Int,
        duration: Int,
        x: Double = 0,
        horizontal: Bool = false,
        vertical: Bool = false
    ) -> UserPetAnimationFrameRequest {
        UserPetAnimationFrameRequest(
            source: .existing(index: index),
            durationMilliseconds: duration,
            placement: FrameCanvasPlacement(
                canvasWidth: 32, canvasHeight: 32, scale: 1, x: x, y: 0
            ),
            flipsHorizontally: horizontal,
            flipsVertically: vertical
        )
    }
}
