import XCTest
@testable import MonglePet

final class PetMovementGeometryTests: XCTestCase {
    func testSafeOriginBoundsKeepWholePetInsideVisibleFrame() throws {
        let bounds = try XCTUnwrap(
            PetMovementGeometry.safeOriginBounds(
                in: rect(100, 50, 1_000, 700),
                petSize: size(200, 160),
                inset: 20
            )
        )

        XCTAssertEqual(bounds.minX, 120)
        XCTAssertEqual(bounds.maxX, 880)
        XCTAssertEqual(bounds.minY, 70)
        XCTAssertEqual(bounds.maxY, 570)
    }

    func testSafeOriginBoundsCenterPetWhenFrameIsTooSmall() throws {
        let bounds = try XCTUnwrap(
            PetMovementGeometry.safeOriginBounds(
                in: rect(-100, 40, 120, 80),
                petSize: size(200, 160),
                inset: 20
            )
        )

        XCTAssertEqual(bounds.minX, -140)
        XCTAssertEqual(bounds.maxX, -140)
        XCTAssertEqual(bounds.minY, 0)
        XCTAssertEqual(bounds.maxY, 0)
    }

    func testCursorTargetKeepsConfiguredDistanceFromPointer() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.cursorFollowingTargetOrigin(
                pointer: point(500, 150),
                currentOrigin: point(100, 100),
                petSize: size(100, 100),
                cursorDistance: 100,
                screenInset: 20,
                screens: [screen("main", 0, 0, 1_000, 800)]
            )
        )

        XCTAssertEqual(target, point(350, 100))
    }

    func testCursorTargetClampsPetInsidePointerScreen() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.cursorFollowingTargetOrigin(
                pointer: point(995, 795),
                currentOrigin: point(400, 300),
                petSize: size(100, 100),
                cursorDistance: 0,
                screenInset: 20,
                screens: [screen("main", 0, 0, 1_000, 800)]
            )
        )

        XCTAssertEqual(target, point(880, 680))
    }

    func testCursorTargetSupportsNegativeCoordinateDisplay() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.cursorFollowingTargetOrigin(
                pointer: point(-1_100, 450),
                currentOrigin: point(100, 100),
                petSize: size(100, 100),
                cursorDistance: 0,
                screenInset: 20,
                screens: [
                    screen("main", 0, 0, 1_000, 800),
                    screen("left", -1_200, 0, 1_200, 900)
                ]
            )
        )

        XCTAssertEqual(target, point(-1_150, 400))
    }

    func testCursorTargetUsesNearestScreenWhenPointerIsOutsideAllScreens() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.cursorFollowingTargetOrigin(
                pointer: point(1_100, 400),
                currentOrigin: point(400, 300),
                petSize: size(100, 100),
                cursorDistance: 0,
                screenInset: 20,
                screens: [
                    screen("main", 0, 0, 1_000, 800),
                    screen("far", 2_000, 0, 1_000, 800)
                ]
            )
        )

        XCTAssertEqual(target, point(880, 350))
    }

    func testFreeRoamingTargetPrefersIntersectingWindow() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.freeRoamingTargetOrigin(
                screens: [screen("main", 0, 0, 1_000, 800)],
                petSize: size(100, 100),
                screenInset: 20,
                preferredWindow: PetMovementWindow(
                    frame: rect(200, 100, 400, 300)
                ),
                sample: sample(screen: 0, horizontal: 0.5, vertical: 0.25)
            )
        )

        XCTAssertEqual(target, point(350, 150))
    }

    func testFreeRoamingTargetFallsBackWhenWindowCannotFitPet() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.freeRoamingTargetOrigin(
                screens: [screen("main", 0, 0, 1_000, 800)],
                petSize: size(100, 100),
                screenInset: 20,
                preferredWindow: PetMovementWindow(
                    frame: rect(300, 300, 40, 40)
                ),
                sample: sample(screen: 0, horizontal: 1, vertical: 1)
            )
        )

        XCTAssertEqual(target, point(880, 680))
    }

    func testFreeRoamingTargetSelectsScreenDeterministically() throws {
        let target = try XCTUnwrap(
            PetMovementGeometry.freeRoamingTargetOrigin(
                screens: [
                    screen("main", 0, 0, 1_000, 800),
                    screen("right", 1_000, 100, 800, 600)
                ],
                petSize: size(100, 100),
                screenInset: 20,
                preferredWindow: nil,
                sample: sample(screen: 0.75, horizontal: 0, vertical: 1)
            )
        )

        XCTAssertEqual(target, point(1_020, 580))
    }

    func testAdvanceMovesAtConfiguredPointsPerSecond() {
        let result = PetMovementGeometry.advance(
            from: point(0, 0),
            toward: point(300, 400),
            speed: 100,
            elapsedSeconds: 1,
            stopRadius: 10
        )

        XCTAssertEqual(result.origin.x, 60, accuracy: 0.000_001)
        XCTAssertEqual(result.origin.y, 80, accuracy: 0.000_001)
        XCTAssertTrue(result.didMove)
        XCTAssertFalse(result.hasArrived)
    }

    func testAdvanceReportsArrivalAfterEnteringStopRadius() {
        let result = PetMovementGeometry.advance(
            from: point(0, 0),
            toward: point(10, 0),
            speed: 4,
            elapsedSeconds: 1,
            stopRadius: 6
        )

        XCTAssertEqual(result.origin, point(4, 0))
        XCTAssertTrue(result.didMove)
        XCTAssertTrue(result.hasArrived)

        let settled = PetMovementGeometry.advance(
            from: result.origin,
            toward: point(10, 0),
            speed: 4,
            elapsedSeconds: 1,
            stopRadius: 6
        )
        XCTAssertEqual(settled.origin, result.origin)
        XCTAssertFalse(settled.didMove)
        XCTAssertTrue(settled.hasArrived)
    }

    func testInvalidGeometryDoesNotProduceTargetOrMovement() {
        XCTAssertNil(
            PetMovementGeometry.cursorFollowingTargetOrigin(
                pointer: point(100, 100),
                currentOrigin: point(0, 0),
                petSize: size(100, 100),
                cursorDistance: 20,
                screenInset: 20,
                screens: []
            )
        )

        let result = PetMovementGeometry.advance(
            from: point(0, 0),
            toward: point(100, 0),
            speed: 100,
            elapsedSeconds: 0,
            stopRadius: 10
        )
        XCTAssertEqual(result.origin, point(0, 0))
        XCTAssertFalse(result.didMove)
        XCTAssertFalse(result.hasArrived)
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

    private func screen(
        _ id: String,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) -> PetMovementScreen {
        PetMovementScreen(
            id: id,
            visibleFrame: rect(x, y, width, height)
        )
    }

    private func sample(
        screen: Double,
        horizontal: Double,
        vertical: Double
    ) -> PetMovementRandomSample {
        PetMovementRandomSample(
            screen: screen,
            horizontal: horizontal,
            vertical: vertical
        )
    }
}
