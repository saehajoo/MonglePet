import CoreGraphics
import XCTest
@testable import MonglePet

final class ImageCropGeometryTests: XCTestCase {
    private let pixelSize = PixelSize(width: 100, height: 80)
    private let geometry = ImageCropGeometry(minimumDimension: 4)

    func testClampsCropSizeAndOriginInsideImage() {
        XCTAssertEqual(
            geometry.clamped(
                PixelRect(x: 95, y: -10, width: 30, height: 2),
                to: pixelSize
            ),
            PixelRect(x: 70, y: 0, width: 30, height: 4)
        )
        XCTAssertEqual(
            geometry.clamped(
                PixelRect(x: 10, y: 10, width: 200, height: 200),
                to: pixelSize
            ),
            PixelRect(x: 0, y: 0, width: 100, height: 80)
        )
    }

    func testMovesCropWithoutLeavingImage() {
        let rect = PixelRect(x: 20, y: 15, width: 30, height: 20)

        XCTAssertEqual(
            geometry.moving(rect, byX: -50, y: 100, in: pixelSize),
            PixelRect(x: 0, y: 60, width: 30, height: 20)
        )
        XCTAssertEqual(
            geometry.moving(rect, byX: 12, y: -8, in: pixelSize),
            PixelRect(x: 32, y: 7, width: 30, height: 20)
        )
    }

    func testResizesCropFromEveryEdgeAndHonorsMinimum() {
        let rect = PixelRect(x: 20, y: 15, width: 30, height: 20)

        XCTAssertEqual(
            geometry.resizing(
                rect,
                handle: .topLeft,
                byX: -10,
                y: -5,
                in: pixelSize
            ),
            PixelRect(x: 10, y: 10, width: 40, height: 25)
        )
        XCTAssertEqual(
            geometry.resizing(
                rect,
                handle: .bottomRight,
                byX: 80,
                y: 80,
                in: pixelSize
            ),
            PixelRect(x: 20, y: 15, width: 80, height: 65)
        )
        XCTAssertEqual(
            geometry.resizing(
                rect,
                handle: .left,
                byX: 100,
                y: 0,
                in: pixelSize
            ),
            PixelRect(x: 46, y: 15, width: 4, height: 20)
        )
        XCTAssertEqual(
            geometry.resizing(
                rect,
                handle: .top,
                byX: 0,
                y: 100,
                in: pixelSize
            ),
            PixelRect(x: 20, y: 31, width: 30, height: 4)
        )
    }

    func testCropsImageUsingValidatedPixelRect() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 12,
                height: 10,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())

        let cropped = try XCTUnwrap(
            ImageCropProcessor().crop(
                image,
                to: PixelRect(x: 2, y: 3, width: 7, height: 5)
            )
        )

        XCTAssertEqual(cropped.width, 7)
        XCTAssertEqual(cropped.height, 5)
        XCTAssertNil(
            ImageCropProcessor().crop(
                image,
                to: PixelRect(x: 10, y: 0, width: 4, height: 5)
            )
        )
    }

    @MainActor
    func testCropPreviewFitsSelectedRegionWithoutCreatingAnotherImage() {
        XCTAssertEqual(
            ImageCropDisplayGeometry.sourceImageFrame(
                imageSize: PixelSize(width: 200, height: 100),
                cropRect: PixelRect(x: 50, y: 10, width: 100, height: 50),
                previewSize: CGSize(width: 300, height: 300)
            ),
            CGRect(x: -150, y: 45, width: 600, height: 300)
        )
    }
}
