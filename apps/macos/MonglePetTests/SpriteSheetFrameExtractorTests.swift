import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class SpriteSheetFrameExtractorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testBuildsUniformGridInReadingOrder() throws {
        let regions = try SpriteSheetFrameExtractor().uniformGridRegions(
            pixelSize: PixelSize(width: 100, height: 60),
            rows: 2,
            columns: 4,
            inset: 2
        )

        XCTAssertEqual(
            regions,
            [
                PixelRect(x: 2, y: 2, width: 21, height: 26),
                PixelRect(x: 27, y: 2, width: 21, height: 26),
                PixelRect(x: 52, y: 2, width: 21, height: 26),
                PixelRect(x: 77, y: 2, width: 21, height: 26),
                PixelRect(x: 2, y: 32, width: 21, height: 26),
                PixelRect(x: 27, y: 32, width: 21, height: 26),
                PixelRect(x: 52, y: 32, width: 21, height: 26),
                PixelRect(x: 77, y: 32, width: 21, height: 26)
            ]
        )
    }

    func testInfersGridDimensionsFromSuggestedRegionLayout() throws {
        let extractor = SpriteSheetFrameExtractor()
        let regions = try extractor.uniformGridRegions(
            pixelSize: PixelSize(width: 700, height: 800),
            rows: 8,
            columns: 7
        )

        XCTAssertEqual(
            extractor.inferredGridDimensions(for: regions),
            SpriteSheetGridDimensions(rows: 8, columns: 7)
        )

        var regionsWithEmptyCell = regions
        regionsWithEmptyCell.remove(at: 10)
        XCTAssertEqual(
            extractor.inferredGridDimensions(for: regionsWithEmptyCell),
            SpriteSheetGridDimensions(rows: 8, columns: 7)
        )
    }

    func testOrdersSelectedRegionsByReadingOrClickOrder() throws {
        let extractor = SpriteSheetFrameExtractor()
        let regions = try extractor.uniformGridRegions(
            pixelSize: PixelSize(width: 40, height: 10),
            rows: 1,
            columns: 4
        )
        let selected = Set([0, 1, 3])

        XCTAssertEqual(
            extractor.orderedSelectedRegionIndices(
                regionCount: regions.count,
                selectedIndices: selected,
                clickedOrder: nil
            ),
            [0, 1, 3]
        )
        XCTAssertEqual(
            extractor.orderedSelectedRegionIndices(
                regionCount: regions.count,
                selectedIndices: selected,
                clickedOrder: [3, 0, 3, 7, -1, 2, 1]
            ),
            [3, 0, 1]
        )
        XCTAssertEqual(
            extractor.orderedSelectedRegions(
                regions,
                selectedIndices: selected,
                clickedOrder: nil
            ),
            [regions[0], regions[1], regions[3]]
        )
        XCTAssertEqual(
            extractor.orderedSelectedRegions(
                regions,
                selectedIndices: selected,
                clickedOrder: [3, 0, 3, 2, 1]
            ),
            [regions[3], regions[0], regions[1]]
        )
    }

    func testLoadsStaticWebPSpriteSheet() throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("static.webp")
        let webPData = try XCTUnwrap(
            Data(
                base64Encoded:
                    "UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADMDOJaQAA3AA/v89WAAAAA=="
            )
        )
        try webPData.write(to: sourceURL)

        let document = try SpriteSheetFrameExtractor().load(at: sourceURL)

        XCTAssertEqual(document.pixelSize, PixelSize(width: 1, height: 1))
    }

    func testRejectsExtensionAndImageFormatMismatch() throws {
        let image = try makeImage(
            width: 8,
            height: 8,
            background: SpriteSheetColor(red: 10, green: 20, blue: 30, alpha: 255),
            rectangles: []
        )
        let sourceURL = temporaryDirectory.appendingPathComponent("mismatch.webp")
        try writePNG(image, to: sourceURL)

        XCTAssertThrowsError(try SpriteSheetFrameExtractor().load(at: sourceURL)) {
            XCTAssertEqual(
                $0 as? SpriteSheetImportError,
                .imageFormatMismatch("mismatch.webp")
            )
        }
    }

    func testSuggestsSeparatedTransparentFramesAndExtractsThemInOrder() throws {
        let image = try makeImage(
            width: 64,
            height: 32,
            background: SpriteSheetColor.clear,
            rectangles: [
                (PixelRect(x: 4, y: 5, width: 18, height: 20),
                 SpriteSheetColor(red: 255, green: 0, blue: 0, alpha: 255)),
                (PixelRect(x: 40, y: 5, width: 18, height: 20),
                 SpriteSheetColor(red: 0, green: 0, blue: 255, alpha: 255))
            ]
        )
        let sourceURL = temporaryDirectory.appendingPathComponent("transparent.png")
        try writePNG(image, to: sourceURL)

        let extractor = SpriteSheetFrameExtractor()
        let document = try extractor.load(at: sourceURL)
        XCTAssertTrue(document.hasTransparentBackground)
        XCTAssertEqual(
            document.suggestedRegions,
            [
                PixelRect(x: 0, y: 0, width: 32, height: 32),
                PixelRect(x: 32, y: 0, width: 32, height: 32)
            ]
        )

        let frames = try extractor.extractFrames(
            from: document,
            regions: document.suggestedRegions,
            removingBackground: nil
        )
        XCTAssertEqual(frames.count, 2)
        XCTAssertGreaterThan(pixel(in: frames[0], x: frames[0].width / 2, y: frames[0].height / 2).red, 200)
        XCTAssertGreaterThan(pixel(in: frames[1], x: frames[1].width / 2, y: frames[1].height / 2).blue, 200)
    }

    func testKeepsTopOriginRegionsAndProcessedPreviewOrientation() throws {
        let background = SpriteSheetColor(red: 255, green: 0, blue: 255, alpha: 255)
        let image = try makeImage(
            width: 32,
            height: 40,
            background: background,
            rectangles: [
                (
                    PixelRect(x: 8, y: 2, width: 16, height: 10),
                    SpriteSheetColor(red: 255, green: 20, blue: 20, alpha: 255)
                ),
                (
                    PixelRect(x: 8, y: 26, width: 16, height: 10),
                    SpriteSheetColor(red: 20, green: 20, blue: 255, alpha: 255)
                )
            ]
        )
        let sourceURL = temporaryDirectory.appendingPathComponent("vertical.png")
        try writePNG(image, to: sourceURL)

        let extractor = SpriteSheetFrameExtractor()
        let document = try extractor.load(at: sourceURL)
        XCTAssertEqual(
            document.suggestedRegions,
            [
                PixelRect(x: 0, y: 0, width: 32, height: 20),
                PixelRect(x: 0, y: 20, width: 32, height: 20)
            ]
        )

        let frames = try extractor.extractFrames(
            from: document,
            regions: document.suggestedRegions,
            removingBackground: SpriteSheetBackgroundRemoval(
                color: document.suggestedBackgroundColor,
                tolerance: 5
            )
        )
        XCTAssertGreaterThan(
            pixel(in: frames[0], x: frames[0].width / 2, y: frames[0].height / 2).red,
            200
        )
        XCTAssertGreaterThan(
            pixel(in: frames[1], x: frames[1].width / 2, y: frames[1].height / 2).blue,
            200
        )

        let processed = try extractor.processedImage(
            from: document,
            removingBackground: SpriteSheetBackgroundRemoval(
                color: document.suggestedBackgroundColor,
                tolerance: 5
            )
        )
        XCTAssertGreaterThan(pixel(in: processed, x: 16, y: 10).red, 200)
        XCTAssertGreaterThan(pixel(in: processed, x: 16, y: 34).blue, 200)
    }

    func testAutomaticRegionsPreserveRegularGridCellsWithUnevenContent() throws {
        let image = try makeImage(
            width: 96,
            height: 80,
            background: .clear,
            rectangles: [
                (
                    PixelRect(x: 5, y: 8, width: 18, height: 21),
                    SpriteSheetColor(red: 255, green: 0, blue: 0, alpha: 255)
                ),
                (
                    PixelRect(x: 39, y: 5, width: 13, height: 27),
                    SpriteSheetColor(red: 0, green: 255, blue: 0, alpha: 255)
                ),
                (
                    PixelRect(x: 70, y: 10, width: 20, height: 18),
                    SpriteSheetColor(red: 0, green: 0, blue: 255, alpha: 255)
                ),
                (
                    PixelRect(x: 7, y: 48, width: 16, height: 23),
                    SpriteSheetColor(red: 255, green: 255, blue: 0, alpha: 255)
                ),
                (
                    PixelRect(x: 36, y: 50, width: 20, height: 18),
                    SpriteSheetColor(red: 0, green: 255, blue: 255, alpha: 255)
                ),
                (
                    PixelRect(x: 72, y: 45, width: 15, height: 28),
                    SpriteSheetColor(red: 255, green: 0, blue: 255, alpha: 255)
                )
            ]
        )
        let sourceURL = temporaryDirectory.appendingPathComponent("regular-grid.png")
        try writePNG(image, to: sourceURL)

        let document = try SpriteSheetFrameExtractor().load(at: sourceURL)

        XCTAssertEqual(
            document.suggestedRegions,
            try SpriteSheetFrameExtractor().uniformGridRegions(
                pixelSize: PixelSize(width: 96, height: 80),
                rows: 2,
                columns: 3
            )
        )
    }

    func testBackgroundRemovalIsOptionalAndDoesNotMutateDocument() throws {
        let background = SpriteSheetColor(red: 255, green: 0, blue: 255, alpha: 255)
        let foreground = SpriteSheetColor(red: 20, green: 200, blue: 40, alpha: 255)
        let image = try makeImage(
            width: 24,
            height: 24,
            background: background,
            rectangles: [
                (PixelRect(x: 6, y: 6, width: 12, height: 12), foreground)
            ]
        )
        let sourceURL = temporaryDirectory.appendingPathComponent("solid-background.png")
        try writePNG(image, to: sourceURL)
        let extractor = SpriteSheetFrameExtractor()
        let document = try extractor.load(at: sourceURL)
        XCTAssertGreaterThan(document.suggestedBackgroundColor.red, 240)
        XCTAssertGreaterThan(document.suggestedBackgroundColor.blue, 240)

        let original = try extractor.processedImage(
            from: document,
            removingBackground: nil
        )
        let removed = try extractor.processedImage(
            from: document,
            removingBackground: SpriteSheetBackgroundRemoval(
                color: document.suggestedBackgroundColor,
                tolerance: 5
            )
        )

        XCTAssertEqual(pixel(in: original, x: 0, y: 0).alpha, 255)
        XCTAssertEqual(pixel(in: removed, x: 0, y: 0).alpha, 0)
        XCTAssertGreaterThan(pixel(in: removed, x: 12, y: 12).alpha, 200)
        XCTAssertEqual(pixel(in: document.image, x: 0, y: 0).alpha, 255)
    }

    private func makeImage(
        width: Int,
        height: Int,
        background: SpriteSheetColor,
        rectangles: [(PixelRect, SpriteSheetColor)]
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw TestError.imageCreation
        }
        context.setFillColor(cgColor(background))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (rect, color) in rectangles {
            context.setFillColor(cgColor(color))
            context.fill(
                CGRect(
                    x: rect.x,
                    y: height - rect.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
            )
        }
        guard let image = context.makeImage() else {
            throw TestError.imageCreation
        }
        return image
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestError.imageCreation
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageCreation
        }
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> SpriteSheetColor {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let sample = image.cropping(
            to: CGRect(x: x, y: y, width: 1, height: 1)
        ) else {
            return .clear
        }
        bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return
            }
            context.draw(
                sample,
                in: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        }
        return SpriteSheetColor(
            red: bytes[0],
            green: bytes[1],
            blue: bytes[2],
            alpha: bytes[3]
        )
    }

    private func cgColor(_ color: SpriteSheetColor) -> CGColor {
        CGColor(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255
        )
    }

    private enum TestError: Error {
        case imageCreation
    }
}
