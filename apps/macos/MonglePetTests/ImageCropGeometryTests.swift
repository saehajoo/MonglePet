import AppKit
import CoreGraphics
import SwiftUI
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

    @MainActor
    func testResultPreviewKeepsFrameBoundaryInsideCanvas() {
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.fittedFrame(
                pixelSize: PixelSize(width: 200, height: 100),
                in: CGSize(width: 300, height: 300),
                inset: 10
            ),
            CGRect(x: 10, y: 80, width: 280, height: 140)
        )
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.fittedFrame(
                pixelSize: PixelSize(width: 100, height: 200),
                in: CGSize(width: 300, height: 300),
                inset: 10
            ),
            CGRect(x: 80, y: 10, width: 140, height: 280)
        )
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.fittedFrame(
                pixelSize: PixelSize(width: 100, height: 100),
                in: CGSize(width: 300, height: 220),
                inset: 10
            ),
            CGRect(x: 50, y: 10, width: 200, height: 200)
        )
    }

    @MainActor
    func testResultPreviewUsesLargestCropAsCommonCanvas() {
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.commonCanvasSize(
                for: [
                    PixelRect(x: 0, y: 0, width: 200, height: 100),
                    PixelRect(x: 10, y: 20, width: 80, height: 240)
                ]
            ),
            PixelSize(width: 200, height: 240)
        )
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.commonCanvasSize(for: []),
            PixelSize(width: 1, height: 1)
        )
    }

    @MainActor
    func testResultPreviewCentersCropWithoutIndividualAspectFit() {
        XCTAssertEqual(
            ImageCropResultPreviewGeometry.centeredContentFrame(
                pixelSize: PixelSize(width: 100, height: 50),
                canvasSize: PixelSize(width: 200, height: 200),
                canvasFrame: CGRect(x: 10, y: 20, width: 300, height: 300)
            ),
            CGRect(x: 85, y: 132.5, width: 150, height: 75)
        )
    }

    @MainActor
    func testEditorOnlyOwnsPanWhenImageIsZoomed() {
        XCTAssertFalse(ImageEditorViewportPolicy.usesInternalPan(at: 1))
        XCTAssertTrue(ImageEditorViewportPolicy.usesInternalPan(at: 1.5))
        XCTAssertTrue(ImageEditorViewportPolicy.usesInternalPan(at: 8))
    }

    @MainActor
    func testPNGEditorCanvasUsesRemainingViewportHeight() {
        XCTAssertEqual(
            PNGFrameCropEditorLayout.canvasHeight(availableHeight: 520),
            398
        )
        XCTAssertEqual(
            PNGFrameCropEditorLayout.canvasHeight(availableHeight: 300),
            260
        )
    }

    @MainActor
    func testCropResultPreviewProducesVisualQAReference() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 160,
                height: 120,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: 160, height: 120))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 35, y: 25, width: 90, height: 70))
        let image = try XCTUnwrap(context.makeImage())
        let cropRect = PixelRect(x: 10, y: 10, width: 140, height: 100)
        let reference = HStack(spacing: 16) {
            CroppedImagePreview(image: image, cropRect: cropRect)
                .frame(width: 280, height: 220)
            CroppedImagePreview(
                image: image,
                cropRect: cropRect,
                flipsHorizontally: true,
                flipsVertically: false
            )
            .frame(width: 280, height: 220)
        }
        .padding(16)
        .frame(width: 608, height: 252)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: reference)
        renderer.scale = 2
        let renderedImage = try XCTUnwrap(renderer.nsImage)

        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "crop-result-preview-boundaries"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
