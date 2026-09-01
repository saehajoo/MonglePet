import AppKit
import XCTest
@testable import MonglePet

final class PetPointerOverlapTests: XCTestCase {
    func testAlphaMaskReportsNormalizedVisibleBounds() {
        let mask = PetFrameAlphaMask(
            width: 4,
            height: 3,
            alphaValues: [
                0, 0, 0, 0,
                0, 255, 255, 0,
                0, 0, 255, 0
            ]
        )

        XCTAssertEqual(
            mask.normalizedVisibleBounds,
            CGRect(x: 0.25, y: 1.0 / 3.0, width: 0.5, height: 2.0 / 3.0)
        )
    }

    func testAlphaMaskUsesVisiblePixelsAndAspectFitContentArea() throws {
        let mask = PetFrameAlphaMask(
            width: 2,
            height: 2,
            alphaValues: [
                0, 255,
                255, 0
            ]
        )

        XCTAssertFalse(
            mask.containsVisiblePixel(
                normalizedX: 0.25,
                normalizedY: 0.25
            )
        )
        XCTAssertTrue(
            mask.containsVisiblePixel(
                normalizedX: 0.75,
                normalizedY: 0.25
            )
        )
        XCTAssertTrue(
            mask.containsVisiblePixel(
                normalizedX: 0.25,
                normalizedY: 0.75
            )
        )
        XCTAssertNil(
            PetFrameAlphaMask.normalizedContentPoint(
                pointX: 20,
                pointY: 20,
                boundsWidth: 200,
                boundsHeight: 200,
                contentWidth: 200,
                contentHeight: 100
            )
        )
        let point = try XCTUnwrap(
            PetFrameAlphaMask.normalizedContentPoint(
                pointX: 150,
                pointY: 75,
                boundsWidth: 200,
                boundsHeight: 200,
                contentWidth: 200,
                contentHeight: 100
            )
        )
        XCTAssertEqual(point.x, 0.75, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.001)
    }

    @MainActor
    func testOverlayViewUsesTopOriginSourceRectForAlphaHitTesting() throws {
        let atlas = try makeImage(
            width: 4,
            height: 4,
            opaqueRects: [
                CGRect(x: 0, y: 2, width: 4, height: 2)
            ]
        )
        let view = try XCTUnwrap(
            PetOverlayView(
                atlasID: "atlas",
                image: NSImage(
                    cgImage: atlas,
                    size: NSSize(width: 4, height: 4)
                )
            )
        )
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)

        XCTAssertTrue(
            view.display(
                MotionFrame(
                    atlasID: "atlas",
                    sourceRect: PixelRect(
                        x: 0,
                        y: 0,
                        width: 4,
                        height: 2
                    ),
                    duration: .milliseconds(100)
                )
            )
        )
        XCTAssertTrue(
            view.containsVisibleContent(at: NSPoint(x: 100, y: 50))
        )

        XCTAssertTrue(
            view.display(
                MotionFrame(
                    atlasID: "atlas",
                    sourceRect: PixelRect(
                        x: 0,
                        y: 2,
                        width: 4,
                        height: 2
                    ),
                    duration: .milliseconds(100)
                )
            )
        )
        XCTAssertFalse(
            view.containsVisibleContent(at: NSPoint(x: 100, y: 50))
        )
    }

    @MainActor
    func testOverlayViewDistinguishesTransparentAndOpaquePixelsInFrame() throws {
        let atlas = try makeImage(
            width: 4,
            height: 2,
            opaqueRects: [
                CGRect(x: 2, y: 0, width: 2, height: 2)
            ]
        )
        let view = try XCTUnwrap(
            PetOverlayView(
                atlasID: "atlas",
                image: NSImage(
                    cgImage: atlas,
                    size: NSSize(width: 4, height: 2)
                )
            )
        )
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertTrue(
            view.display(
                MotionFrame(
                    atlasID: "atlas",
                    sourceRect: PixelRect(
                        x: 0,
                        y: 0,
                        width: 4,
                        height: 2
                    ),
                    duration: .milliseconds(100)
                )
            )
        )

        XCTAssertFalse(
            view.containsVisibleContent(at: NSPoint(x: 25, y: 50))
        )
        XCTAssertTrue(
            view.containsVisibleContent(at: NSPoint(x: 175, y: 50))
        )
        XCTAssertEqual(
            view.visibleContentBounds(),
            NSRect(x: 100, y: 0, width: 100, height: 100)
        )
    }

    @MainActor
    func testLifecycleMonitorsOnlyWhenEnabledAndRestoresBaseOpacity() {
        let scheduler = TestPointerOverlapScheduler()
        var isOverlapping = false
        var applied: [(opacity: Double, animated: Bool)] = []
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: {
                PetPointerObservation(
                    screenLocation: .zero,
                    isInsidePanel: isOverlapping,
                    isOverVisibleContent: isOverlapping
                )
            },
            applyOpacity: { applied.append(($0, $1)) }
        )
        let settings = makeOverlaySettings(
            clickThrough: true,
            opacity: 0.8,
            fadeEnabled: true,
            overlapOpacity: 0.2
        )

        lifecycle.setSettings(settings)

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
        XCTAssertEqual(applied.map(\.opacity), [0.8])

        lifecycle.setAwake(true)

        XCTAssertTrue(lifecycle.isMonitoring)
        XCTAssertNotNil(scheduler.action)
        XCTAssertEqual(applied.map(\.opacity), [0.8])

        isOverlapping = true
        scheduler.fire()

        XCTAssertEqual(applied.map(\.opacity), [0.8, 0.2])
        XCTAssertTrue(applied.last?.animated == true)
        XCTAssertNotNil(scheduler.action)

        lifecycle.setReduceMotion(true)

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
        XCTAssertEqual(applied.map(\.opacity), [0.8, 0.2, 0.8])

        lifecycle.setReduceMotion(false)

        XCTAssertTrue(lifecycle.isMonitoring)
        XCTAssertEqual(applied.map(\.opacity), [0.8, 0.2, 0.8, 0.2])

        lifecycle.setAwake(false)

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
        XCTAssertEqual(
            applied.map(\.opacity),
            [0.8, 0.2, 0.8, 0.2, 0.8]
        )

        lifecycle.setAwake(true)

        XCTAssertTrue(lifecycle.isMonitoring)
        XCTAssertEqual(
            applied.map(\.opacity),
            [0.8, 0.2, 0.8, 0.2, 0.8, 0.2]
        )

        lifecycle.setSystemSuspended(true)

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
        XCTAssertEqual(
            applied.map(\.opacity),
            [0.8, 0.2, 0.8, 0.2, 0.8, 0.2, 0.8]
        )
    }

    @MainActor
    func testLifecycleNeverRaisesOpacityWhilePointerOverlaps() {
        let scheduler = TestPointerOverlapScheduler()
        var applied: [Double] = []
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: {
                PetPointerObservation(
                    screenLocation: .zero,
                    isInsidePanel: true,
                    isOverVisibleContent: true
                )
            },
            applyOpacity: { opacity, _ in applied.append(opacity) }
        )

        lifecycle.setSettings(
            makeOverlaySettings(
                clickThrough: true,
                opacity: 0.3,
                fadeEnabled: true,
                overlapOpacity: 0.9
            )
        )
        lifecycle.setAwake(true)

        XCTAssertEqual(applied, [0.3])
        XCTAssertTrue(lifecycle.isMonitoring)

        lifecycle.setSettings(
            makeOverlaySettings(
                clickThrough: false,
                opacity: 0.3,
                fadeEnabled: true,
                overlapOpacity: 0.1
            )
        )

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
        XCTAssertEqual(applied, [0.3])
    }

    @MainActor
    func testHoverPettingWaitsForDwellAndRequiresExitBeforeRepeating() {
        let scheduler = TestPointerOverlapScheduler()
        var observation = PetPointerObservation(
            screenLocation: CGPoint(x: 10, y: 10),
            isInsidePanel: false,
            isOverVisibleContent: false
        )
        var pettingCount = 0
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: { observation },
            applyOpacity: { _, _ in },
            requestPetting: { pettingCount += 1 }
        )

        lifecycle.setSettings(
            makeOverlaySettings(
                clickThrough: false,
                opacity: 1,
                fadeEnabled: false,
                overlapOpacity: 0.2
            )
        )
        lifecycle.setPettingEnabled(true)
        lifecycle.setAwake(true)

        XCTAssertTrue(lifecycle.isMonitoring)
        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 30, y: 30),
            isInsidePanel: true,
            isOverVisibleContent: true
        )
        scheduler.fire()
        XCTAssertEqual(pettingCount, 0)

        for opacity in [0.9, 0.8, 0.7] {
            lifecycle.setSettings(
                makeOverlaySettings(
                    clickThrough: false,
                    opacity: opacity,
                    fadeEnabled: false,
                    overlapOpacity: 0.2
                )
            )
        }
        XCTAssertEqual(pettingCount, 0)

        for _ in 0..<PetPointerOverlapLifecycle.pettingDwellSampleCount {
            scheduler.fire()
        }
        XCTAssertEqual(pettingCount, 1)

        for _ in 0..<5 {
            scheduler.fire()
        }
        XCTAssertEqual(pettingCount, 1)

        lifecycle.setSettings(
            makeOverlaySettings(
                clickThrough: true,
                opacity: 1,
                fadeEnabled: false,
                overlapOpacity: 0.2
            )
        )
        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 40, y: 30),
            isInsidePanel: false,
            isOverVisibleContent: false
        )
        scheduler.fire()
        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 50, y: 30),
            isInsidePanel: true,
            isOverVisibleContent: true
        )
        scheduler.fire()
        for _ in 0..<PetPointerOverlapLifecycle.pettingDwellSampleCount {
            scheduler.fire()
        }

        XCTAssertEqual(pettingCount, 2)
    }

    @MainActor
    func testHoverPettingDoesNotTriggerWhenPetMovesUnderStationaryPointer() {
        let scheduler = TestPointerOverlapScheduler()
        var observation = PetPointerObservation(
            screenLocation: CGPoint(x: 10, y: 10),
            isInsidePanel: false,
            isOverVisibleContent: false
        )
        var pettingCount = 0
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: { observation },
            applyOpacity: { _, _ in },
            requestPetting: { pettingCount += 1 }
        )

        lifecycle.setPettingEnabled(true)
        lifecycle.setAwake(true)
        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 10, y: 10),
            isInsidePanel: true,
            isOverVisibleContent: true
        )
        scheduler.fire()
        for _ in 0..<5 {
            scheduler.fire()
        }

        XCTAssertEqual(pettingCount, 0)

        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 20, y: 10),
            isInsidePanel: true,
            isOverVisibleContent: true
        )
        for _ in 0..<5 {
            scheduler.fire()
        }
        XCTAssertEqual(pettingCount, 0)
    }

    @MainActor
    func testHoverPettingIsSuppressedUntilExitAfterUserDrag() {
        let scheduler = TestPointerOverlapScheduler()
        var observation = PetPointerObservation(
            screenLocation: CGPoint(x: 0, y: 0),
            isInsidePanel: false,
            isOverVisibleContent: false
        )
        var pettingCount = 0
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: { observation },
            applyOpacity: { _, _ in },
            requestPetting: { pettingCount += 1 }
        )

        lifecycle.setPettingEnabled(true)
        lifecycle.setAwake(true)
        lifecycle.setUserDragging(true)
        observation = PetPointerObservation(
            screenLocation: CGPoint(x: 20, y: 20),
            isInsidePanel: true,
            isOverVisibleContent: true
        )
        scheduler.fire()
        lifecycle.setUserDragging(false)
        for _ in 0..<5 {
            scheduler.fire()
        }

        XCTAssertEqual(pettingCount, 0)
    }

    @MainActor
    func testPettingKeepsMonitoringDuringReduceMotionAndStopsWhenDisabled() {
        let scheduler = TestPointerOverlapScheduler()
        let lifecycle = PetPointerOverlapLifecycle(
            scheduler: scheduler,
            observePointer: {
                PetPointerObservation(
                    screenLocation: .zero,
                    isInsidePanel: false,
                    isOverVisibleContent: false
                )
            },
            applyOpacity: { _, _ in }
        )

        lifecycle.setPettingEnabled(true)
        lifecycle.setAwake(true)
        lifecycle.setReduceMotion(true)

        XCTAssertTrue(lifecycle.isMonitoring)
        XCTAssertNotNil(scheduler.action)

        lifecycle.setPettingEnabled(false)

        XCTAssertFalse(lifecycle.isMonitoring)
        XCTAssertNil(scheduler.action)
    }

    private func makeOverlaySettings(
        clickThrough: Bool,
        opacity: Double,
        fadeEnabled: Bool,
        overlapOpacity: Double
    ) -> OverlaySettings {
        OverlaySettings(
            screenIdentifier: nil,
            originX: 0,
            originY: 0,
            width: 192,
            clickThrough: clickThrough,
            opacity: opacity,
            pointerOverlapFadeEnabled: fadeEnabled,
            pointerOverlapOpacity: overlapOpacity
        )
    }

    @MainActor
    private func makeImage(
        width: Int,
        height: Int,
        opaqueRects: [CGRect]
    ) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.white.cgColor)
        for rect in opaqueRects {
            context.fill(rect)
        }
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
private final class TestPointerOverlapScheduler:
    PetPointerOverlapScheduling {
    private(set) var delay: Duration?
    private(set) var action: (() -> Void)?

    func schedule(after delay: Duration, action: @escaping () -> Void) {
        self.delay = delay
        self.action = action
    }

    func cancel() {
        delay = nil
        action = nil
    }

    func fire() {
        let pendingAction = action
        delay = nil
        action = nil
        pendingAction?()
    }
}
