import CoreGraphics
import XCTest
@testable import MonglePet

final class EditorWindowPlacementTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 25, width: 1_728, height: 1_059)
    private let idealSize = CGSize(width: 920, height: 720)
    private let minimumSize = CGSize(width: 760, height: 560)

    func testPlacesIdealWindowNearParentCenter() {
        let result = EditorWindowPlacement.frame(
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            parentFrame: CGRect(x: 200, y: 200, width: 840, height: 620)
        )

        XCTAssertEqual(result, CGRect(x: 184, y: 126, width: 920, height: 720))
    }

    func testClampsParentRelativeWindowInsideVisibleScreen() {
        let result = EditorWindowPlacement.frame(
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            parentFrame: CGRect(x: 1_500, y: 900, width: 300, height: 200)
        )

        XCTAssertEqual(result, CGRect(x: 808, y: 364, width: 920, height: 720))
    }

    func testCentersWindowInVisibleScreenWithoutParent() {
        let result = EditorWindowPlacement.frame(
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            parentFrame: nil
        )

        XCTAssertEqual(result, CGRect(x: 404, y: 194.5, width: 920, height: 720))
    }

    func testShrinksIdealWindowToSmallVisibleScreen() {
        let smallVisibleFrame = CGRect(x: 100, y: 80, width: 640, height: 480)

        let result = EditorWindowPlacement.frame(
            idealSize: CGSize(width: 1_080, height: 760),
            minimumSize: minimumSize,
            visibleFrame: smallVisibleFrame,
            parentFrame: CGRect(x: 200, y: 120, width: 500, height: 400)
        )

        XCTAssertEqual(result, smallVisibleFrame)
    }
}
