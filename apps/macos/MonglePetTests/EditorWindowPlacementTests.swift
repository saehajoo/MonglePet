import CoreGraphics
import XCTest
@testable import MonglePet

final class EditorWindowPlacementTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 25, width: 1_728, height: 1_059)
    private let idealSize = CGSize(width: 920, height: 720)
    private let minimumSize = CGSize(width: 760, height: 560)

    func testReplacesCorruptedTinyFrameWithCenteredIdealSize() {
        let result = EditorWindowPlacement.adjustedFrame(
            proposedFrame: CGRect(x: 1_282, y: 498, width: 1, height: 32),
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            fallbackCenter: CGPoint(x: 864, y: 554.5)
        )

        XCTAssertEqual(result, CGRect(x: 404, y: 194.5, width: 920, height: 720))
    }

    func testClampsValidRestoredFrameFullyInsideVisibleScreen() {
        let result = EditorWindowPlacement.adjustedFrame(
            proposedFrame: CGRect(x: 1_200, y: 700, width: 900, height: 700),
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            fallbackCenter: CGPoint(x: 864, y: 554.5)
        )

        XCTAssertEqual(result, CGRect(x: 828, y: 384, width: 900, height: 700))
    }

    func testShrinksOversizedRestoredFrameToVisibleScreen() {
        let result = EditorWindowPlacement.adjustedFrame(
            proposedFrame: CGRect(x: -300, y: -200, width: 2_400, height: 1_400),
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            fallbackCenter: CGPoint(x: 864, y: 554.5)
        )

        XCTAssertEqual(result, visibleFrame)
    }

    func testPreservesValidVisibleRestoredFrame() {
        let proposed = CGRect(x: 320, y: 180, width: 1_000, height: 760)

        XCTAssertEqual(
            EditorWindowPlacement.adjustedFrame(
                proposedFrame: proposed,
                idealSize: idealSize,
                minimumSize: minimumSize,
                visibleFrame: visibleFrame,
                fallbackCenter: CGPoint(x: 864, y: 554.5)
            ),
            proposed
        )
    }
}
