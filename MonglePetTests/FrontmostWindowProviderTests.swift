import XCTest
@testable import MonglePet

final class FrontmostWindowResolverTests: XCTestCase {
    func testResolverConvertsCoreGraphicsTopLeftCoordinates() throws {
        let window = try XCTUnwrap(
            FrontmostWindowResolver.representativeWindow(
                frontmostPID: 42,
                snapshots: [snapshot(pid: 42, x: 100, y: 50, width: 800, height: 600)],
                displayLayout: layout(
                    mainScreenMaxY: 900,
                    screens: [screen("main", 0, 0, 1_440, 900)]
                )
            )
        )

        XCTAssertEqual(window.frame, rect(100, 250, 800, 600))
    }

    func testResolverConvertsWindowOnDisplayAboveMainScreen() throws {
        let window = try XCTUnwrap(
            FrontmostWindowResolver.representativeWindow(
                frontmostPID: 42,
                snapshots: [snapshot(pid: 42, x: 100, y: -700, width: 800, height: 600)],
                displayLayout: layout(
                    mainScreenMaxY: 900,
                    screens: [
                        screen("main", 0, 0, 1_440, 900),
                        screen("above", 0, 900, 1_200, 800)
                    ]
                )
            )
        )

        XCTAssertEqual(window.frame, rect(100, 1_000, 800, 600))
    }

    func testResolverConvertsWindowOnDisplayBelowMainScreen() throws {
        let window = try XCTUnwrap(
            FrontmostWindowResolver.representativeWindow(
                frontmostPID: 42,
                snapshots: [snapshot(pid: 42, x: 100, y: 900, width: 800, height: 600)],
                displayLayout: layout(
                    mainScreenMaxY: 900,
                    screens: [
                        screen("main", 0, 0, 1_440, 900),
                        screen("below", 0, -800, 1_200, 800)
                    ]
                )
            )
        )

        XCTAssertEqual(window.frame, rect(100, -600, 800, 600))
    }

    func testResolverFiltersForeignOverlayTransparentAndTinyWindows() throws {
        let window = try XCTUnwrap(
            FrontmostWindowResolver.representativeWindow(
                frontmostPID: 42,
                snapshots: [
                    snapshot(pid: 7, x: 0, y: 0, width: 1_000, height: 700),
                    snapshot(pid: 42, layer: 25, x: 50, y: 50, width: 900, height: 700),
                    snapshot(pid: 42, alpha: 0, x: 50, y: 50, width: 900, height: 700),
                    snapshot(pid: 42, x: 50, y: 50, width: 40, height: 40),
                    snapshot(pid: 42, x: 100, y: 200, width: 500, height: 400),
                    snapshot(pid: 42, x: 300, y: 300, width: 200, height: 100)
                ],
                displayLayout: layout(
                    mainScreenMaxY: 900,
                    screens: [screen("main", 0, 0, 1_440, 900)]
                )
            )
        )

        XCTAssertEqual(window.frame, rect(100, 300, 500, 400))
    }

    func testResolverReturnsNilWhenFrontmostAppHasFullScreenWindow() {
        let window = FrontmostWindowResolver.representativeWindow(
            frontmostPID: 42,
            snapshots: [
                snapshot(pid: 42, x: 0, y: 0, width: 1_440, height: 900),
                snapshot(pid: 42, x: 200, y: 200, width: 300, height: 200)
            ],
            displayLayout: layout(
                mainScreenMaxY: 900,
                screens: [screen("main", 0, 0, 1_440, 900)]
            )
        )

        XCTAssertNil(window)
    }

    func testResolverIgnoresWindowsOutsideKnownScreens() {
        let window = FrontmostWindowResolver.representativeWindow(
            frontmostPID: 42,
            snapshots: [snapshot(pid: 42, x: 5_000, y: 5_000, width: 800, height: 600)],
            displayLayout: layout(
                mainScreenMaxY: 900,
                screens: [screen("main", 0, 0, 1_440, 900)]
            )
        )

        XCTAssertNil(window)
    }

    private func snapshot(
        pid: Int32,
        layer: Int = 0,
        alpha: Double = 1,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> PetWindowSnapshot {
        PetWindowSnapshot(
            ownerPID: pid,
            layer: layer,
            alpha: alpha,
            bounds: rect(x, y, width, height)
        )
    }

    private func layout(
        mainScreenMaxY: Double,
        screens: [PetMovementScreen]
    ) -> PetMovementDisplayLayout {
        PetMovementDisplayLayout(
            screens: screens,
            mainScreenMaxY: mainScreenMaxY
        )
    }
}

@MainActor
final class FrontmostWindowProviderTests: XCTestCase {
    func testProviderCachesWindowServerReadWithinRefreshInterval() {
        var now: TimeInterval = 10
        var snapshotReadCount = 0
        let provider = FrontmostWindowProvider(
            minimumRefreshInterval: 1,
            frontmostPIDProvider: { 42 },
            windowSnapshotsProvider: {
                snapshotReadCount += 1
                return [self.snapshot(pid: 42, x: 100, y: 100, width: 500, height: 400)]
            },
            displayLayoutProvider: { self.defaultLayout },
            uptimeProvider: { now }
        )

        XCTAssertNotNil(provider.representativeWindow())
        now = 10.9
        XCTAssertNotNil(provider.representativeWindow())
        XCTAssertEqual(snapshotReadCount, 1)

        now = 11
        XCTAssertNotNil(provider.representativeWindow())
        XCTAssertEqual(snapshotReadCount, 2)
    }

    func testProviderRefreshesImmediatelyWhenFrontmostPIDChanges() {
        var now: TimeInterval = 10
        var frontmostPID: Int32? = 42
        var snapshotReadCount = 0
        let provider = FrontmostWindowProvider(
            minimumRefreshInterval: 10,
            frontmostPIDProvider: { frontmostPID },
            windowSnapshotsProvider: {
                snapshotReadCount += 1
                return [
                    self.snapshot(pid: 42, x: 100, y: 100, width: 500, height: 400),
                    self.snapshot(pid: 84, x: 300, y: 200, width: 600, height: 500)
                ]
            },
            displayLayoutProvider: { self.defaultLayout },
            uptimeProvider: { now }
        )

        XCTAssertEqual(provider.representativeWindow()?.frame.size.width, 500)
        frontmostPID = 84
        now = 10.1
        XCTAssertEqual(provider.representativeWindow()?.frame.size.width, 600)
        XCTAssertEqual(snapshotReadCount, 2)
    }

    func testProviderCachesNilAndInvalidateForcesRefresh() {
        var snapshotReadCount = 0
        let provider = FrontmostWindowProvider(
            minimumRefreshInterval: 10,
            frontmostPIDProvider: { 42 },
            windowSnapshotsProvider: {
                snapshotReadCount += 1
                return []
            },
            displayLayoutProvider: { self.defaultLayout },
            uptimeProvider: { 10 }
        )

        XCTAssertNil(provider.representativeWindow())
        XCTAssertNil(provider.representativeWindow())
        XCTAssertEqual(snapshotReadCount, 1)

        provider.invalidate()
        XCTAssertNil(provider.representativeWindow())
        XCTAssertEqual(snapshotReadCount, 2)
    }

    func testProviderDoesNotReadWindowServerWithoutFrontmostPID() {
        var snapshotReadCount = 0
        let provider = FrontmostWindowProvider(
            frontmostPIDProvider: { nil },
            windowSnapshotsProvider: {
                snapshotReadCount += 1
                return []
            },
            displayLayoutProvider: { self.defaultLayout },
            uptimeProvider: { 10 }
        )

        XCTAssertNil(provider.representativeWindow())
        XCTAssertEqual(snapshotReadCount, 0)
    }

    func testSystemProviderReadsWithoutAccessibilitySetup() {
        let provider = FrontmostWindowProvider()

        _ = provider.representativeWindow()
    }

    private var defaultLayout: PetMovementDisplayLayout {
        PetMovementDisplayLayout(
            screens: [screen("main", 0, 0, 1_440, 900)],
            mainScreenMaxY: 900
        )
    }

    private func snapshot(
        pid: Int32,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> PetWindowSnapshot {
        PetWindowSnapshot(
            ownerPID: pid,
            layer: 0,
            alpha: 1,
            bounds: rect(x, y, width, height)
        )
    }
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
