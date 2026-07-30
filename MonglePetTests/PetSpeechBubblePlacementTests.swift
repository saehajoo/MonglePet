import AppKit
import XCTest
@testable import MonglePet

final class PetSpeechBubblePlacementTests: XCTestCase {
    @MainActor
    func testBubblePanelAlwaysIgnoresMouseEvents() {
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let controller = PetSpeechBubbleWindowController(
            parentWindow: parentWindow
        )

        XCTAssertTrue(controller.ignoresMouseEvents)
    }

    func testPlacesBubbleCenteredAbovePetWhenSpaceAllows() {
        let origin = PetSpeechBubblePlacement.origin(
            parentFrame: rect(400, 200, 200, 180),
            bubbleSize: size(240, 80),
            visibleFrame: rect(0, 0, 1_000, 800)
        )

        XCTAssertEqual(origin, point(380, 388))
    }

    func testUsesBelowPetNearTopEdgeAndClampsHorizontally() {
        let origin = PetSpeechBubblePlacement.origin(
            parentFrame: rect(0, 650, 160, 140),
            bubbleSize: size(240, 80),
            visibleFrame: rect(0, 0, 1_000, 800)
        )

        XCTAssertEqual(origin, point(0, 562))
    }

    func testSupportsNegativeCoordinateDisplay() {
        let origin = PetSpeechBubblePlacement.origin(
            parentFrame: rect(-1_150, 100, 160, 140),
            bubbleSize: size(220, 70),
            visibleFrame: rect(-1_200, 0, 1_200, 900)
        )

        XCTAssertEqual(origin, point(-1_180, 248))
    }

    private func point(_ x: Double, _ y: Double) -> PetMovementPoint {
        PetMovementPoint(x: x, y: y)
    }

    private func size(_ width: Double, _ height: Double) -> PetMovementSize {
        PetMovementSize(width: width, height: height)
    }

    private func rect(
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) -> PetMovementRect {
        PetMovementRect(x: x, y: y, width: width, height: height)
    }
}
