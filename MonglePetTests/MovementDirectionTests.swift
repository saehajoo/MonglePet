import XCTest
@testable import MonglePet

final class MovementDirectionTests: XCTestCase {
    func testFourDirectionClassificationUsesCardinalSectors() {
        let cases: [(Double, Double, MovementDirection)] = [
            (10, 0, .right),
            (-10, 0, .left),
            (0, 10, .up),
            (0, -10, .down),
            (10, 9, .right),
            (9, 10, .up)
        ]

        for (deltaX, deltaY, expected) in cases {
            var classifier = MovementDirectionClassifier()
            XCTAssertEqual(
                classifier.classify(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    usesDiagonals: false
                ),
                expected
            )
        }
    }

    func testEightDirectionClassificationUsesDiagonalSectors() {
        let cases: [(Double, Double, MovementDirection)] = [
            (10, 10, .upRight),
            (-10, 10, .upLeft),
            (-10, -10, .downLeft),
            (10, -10, .downRight)
        ]

        for (deltaX, deltaY, expected) in cases {
            var classifier = MovementDirectionClassifier()
            XCTAssertEqual(
                classifier.classify(
                    deltaX: deltaX,
                    deltaY: deltaY,
                    usesDiagonals: true
                ),
                expected
            )
        }
    }

    func testClassificationKeepsCurrentDirectionInsideHysteresisMargin() {
        var classifier = MovementDirectionClassifier(
            hysteresisDegrees: 8
        )

        XCTAssertEqual(
            classifier.classify(
                deltaX: 10,
                deltaY: 0,
                usesDiagonals: false
            ),
            .right
        )
        XCTAssertEqual(
            classifier.classify(
                deltaX: cos(50 * .pi / 180),
                deltaY: sin(50 * .pi / 180),
                usesDiagonals: false
            ),
            .right
        )
        XCTAssertEqual(
            classifier.classify(
                deltaX: cos(60 * .pi / 180),
                deltaY: sin(60 * .pi / 180),
                usesDiagonals: false
            ),
            .up
        )
    }

    func testDirectionalAnimationUsesExactThenCardinalThenFallback() {
        let animation = MovementAnimationSettings(
            fallbackMotionID: "fallback",
            usesDirectionalMotions: true,
            usesDiagonalMotions: true,
            directionMotionIDs: DirectionalMotionIDs(
                left: "left",
                right: "right",
                upRight: "up-right"
            )
        )

        XCTAssertEqual(
            animation.resolvedMotionID(
                for: .upRight,
                deltaX: 10,
                deltaY: 10
            ),
            "up-right"
        )
        XCTAssertEqual(
            animation.resolvedMotionID(
                for: .downLeft,
                deltaX: -10,
                deltaY: -8
            ),
            "left"
        )
        XCTAssertEqual(
            animation.resolvedMotionID(
                for: .downRight,
                deltaX: 4,
                deltaY: -10
            ),
            "fallback"
        )
    }

    func testCommonAnimationIgnoresDirection() {
        let animation = MovementAnimationSettings.single("run")

        XCTAssertEqual(
            animation.resolvedMotionID(
                for: .left,
                deltaX: -10,
                deltaY: 0
            ),
            "run"
        )
    }
}
