import AppKit
import XCTest
@testable import MonglePet

@MainActor
final class PetSharedRuntimeResourcesTests: XCTestCase {
    func testDesktopEnvironmentMonitorOwnsOnePointerAndDisplaySnapshot() {
        let notificationCenter = NotificationCenter()
        var pointer = PetMovementPoint(x: 120, y: 240)
        var displays = [Self.display(id: "first", x: 0)]
        var pointerReadCount = 0
        var displayReadCount = 0
        var displayChangeCount = 0
        let monitor = PetDesktopEnvironmentMonitor(
            notificationCenter: notificationCenter,
            pointerProvider: {
                pointerReadCount += 1
                return pointer
            },
            displaysProvider: {
                displayReadCount += 1
                return displays
            }
        )

        monitor.start {
            displayChangeCount += 1
        }
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(
            monitor.currentSnapshot.pointerLocation,
            PetMovementPoint(x: 120, y: 240)
        )
        XCTAssertEqual(monitor.currentSnapshot.displays.map(\.id), ["first"])

        pointer = PetMovementPoint(x: 1_200, y: 480)
        monitor.refreshPointer()
        XCTAssertEqual(monitor.currentSnapshot.pointerLocation, pointer)
        XCTAssertEqual(displayChangeCount, 0)

        displays = [
            Self.display(id: "first", x: 0),
            Self.display(id: "second", x: 1_000)
        ]
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        XCTAssertEqual(
            monitor.currentSnapshot.displays.map(\.id),
            ["first", "second"]
        )
        XCTAssertEqual(displayChangeCount, 1)
        XCTAssertEqual(pointerReadCount, 4)
        XCTAssertEqual(displayReadCount, 3)

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testPresentationCacheSharesResourcesAndReleasesWeakEntries() throws {
        let cache = PetPresentationResourceCache()
        weak var weakResources: PetPresentationResources?

        do {
            let first = try cache.builtInResources()
            let second = try cache.builtInResources()
            XCTAssertTrue(first === second)
            XCTAssertEqual(cache.resourceLoadCount, 1)
            XCTAssertEqual(cache.liveResourceCount, 1)
            weakResources = first
        }

        XCTAssertNil(weakResources)
        cache.removeReleasedEntries()
        XCTAssertEqual(cache.liveResourceCount, 0)
    }

    func testTwoOverlayViewsShareOneAlphaMask() throws {
        let image = try Self.makeImage(width: 2, height: 2)
        let atlas = PetAtlasImage(
            id: "shared",
            image: image,
            pixelSize: PixelSize(width: 2, height: 2)
        )
        var alphaMaskBuildCount = 0
        let resources = PetPresentationResources(
            atlases: [atlas],
            alphaMaskBuilder: { _, _ in
                alphaMaskBuildCount += 1
                return PetFrameAlphaMask(
                    width: 2,
                    height: 2,
                    alphaValues: [255, 255, 255, 255]
                )
            }
        )
        let firstView = try XCTUnwrap(
            PetOverlayView(resources: resources, atlasID: "shared")
        )
        let secondView = try XCTUnwrap(
            PetOverlayView(resources: resources, atlasID: "shared")
        )
        let frame = MotionFrame(
            atlasID: "shared",
            sourceRect: PixelRect(x: 0, y: 0, width: 2, height: 2),
            duration: .milliseconds(100)
        )
        for view in [firstView, secondView] {
            view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            XCTAssertTrue(view.display(frame))
            XCTAssertTrue(
                view.containsVisibleContent(at: NSPoint(x: 50, y: 50))
            )
        }

        XCTAssertEqual(alphaMaskBuildCount, 1)
        XCTAssertEqual(resources.cachedAlphaMaskCount, 1)
    }

    func testWindowControllersReuseBuiltInPresentationResources() {
        let cache = PetPresentationResourceCache()
        let environment = StaticPetDesktopEnvironmentProvider(
            snapshot: PetDesktopEnvironmentSnapshot(
                pointerLocation: nil,
                displays: [Self.display(id: "test", x: 0)]
            )
        )

        let first = PetWindowController(
            environmentProvider: environment,
            resourceCache: cache
        )
        let second = PetWindowController(
            environmentProvider: environment,
            resourceCache: cache
        )

        XCTAssertNotNil(first.panel)
        XCTAssertNotNil(second.panel)
        XCTAssertEqual(cache.resourceLoadCount, 1)
        XCTAssertEqual(cache.liveResourceCount, 1)
    }

    private static func display(
        id: String,
        x: Double
    ) -> PetDesktopDisplaySnapshot {
        PetDesktopDisplaySnapshot(
            id: id,
            name: id,
            frame: PetMovementRect(x: x, y: 0, width: 1_000, height: 800),
            visibleFrame: PetMovementRect(
                x: x,
                y: 0,
                width: 1_000,
                height: 760
            )
        )
    }

    private static func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
