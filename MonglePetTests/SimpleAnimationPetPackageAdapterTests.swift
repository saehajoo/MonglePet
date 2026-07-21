import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class SimpleAnimationPetPackageAdapterTests: XCTestCase {
    func testConvertsAnimatedGIFWithFrameDelays() throws {
        let fixture = try makeEnvironment()
        let gifURL = fixture.temporaryURL.appendingPathComponent("pet.gif")
        try writeAnimatedImage(
            to: gifURL,
            type: .gif,
            delays: [0.08, 0.15, 0.24]
        )

        let package = try SimpleAnimationPetPackageAdapter().convertAnimatedImage(
            at: gifURL,
            metadata: metadata(id: "local.gif"),
            to: fixture.outputURL
        )

        let idle = try XCTUnwrap(package.definition.motion(id: "idle"))
        XCTAssertEqual(idle.frames.count, 3)
        XCTAssertEqual(
            idle.frames.map(\.duration),
            [.milliseconds(80), .milliseconds(150), .milliseconds(240)]
        )
        XCTAssertTrue(idle.loops)
        XCTAssertEqual(package.atlases[0].pixelSize, PixelSize(width: 12, height: 3))
        XCTAssertEqual(package.atlases[0].format, .png)
    }

    func testConvertsAPNGWithFrameDelays() throws {
        let fixture = try makeEnvironment()
        let apngURL = fixture.temporaryURL.appendingPathComponent("pet.png")
        try writeAnimatedImage(
            to: apngURL,
            type: .apng,
            delays: [0.1, 0.2]
        )

        let package = try SimpleAnimationPetPackageAdapter().convertAnimatedImage(
            at: apngURL,
            metadata: metadata(id: "local.apng"),
            to: fixture.outputURL
        )

        let idle = try XCTUnwrap(package.definition.motion(id: "idle"))
        XCTAssertEqual(idle.frames.map(\.duration), [.milliseconds(100), .milliseconds(200)])
        XCTAssertEqual(idle.frames.map(\.sourceRect.x), [0, 4])
    }

    func testConvertsPNGSequenceInCallerProvidedOrder() throws {
        let fixture = try makeEnvironment()
        let blueURL = fixture.temporaryURL.appendingPathComponent("z-blue.png")
        let redURL = fixture.temporaryURL.appendingPathComponent("a-red.png")
        try writePNG(to: blueURL, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        try writePNG(to: redURL, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        let package = try SimpleAnimationPetPackageAdapter().convertPNGSequence(
            [blueURL, redURL],
            frameDurationMilliseconds: 175,
            metadata: metadata(id: "local.sequence"),
            to: fixture.outputURL
        )

        let idle = try XCTUnwrap(package.definition.motion(id: "idle"))
        XCTAssertEqual(idle.frames.map(\.duration), [.milliseconds(175), .milliseconds(175)])
        XCTAssertEqual(idle.frames.map(\.sourceRect.x), [0, 4])
        let colors = try readAtlasPixelColors(
            at: package.atlases[0].fileURL,
            points: [(1, 1), (5, 1)]
        )
        XCTAssertGreaterThan(colors[0].blue, colors[0].red)
        XCTAssertGreaterThan(colors[1].red, colors[1].blue)
    }

    func testUsesFallbackForTooShortAnimatedDelay() throws {
        let fixture = try makeEnvironment()
        let gifURL = fixture.temporaryURL.appendingPathComponent("fast.gif")
        try writeAnimatedImage(to: gifURL, type: .gif, delays: [0.001, 0.02])

        let package = try SimpleAnimationPetPackageAdapter().convertAnimatedImage(
            at: gifURL,
            metadata: metadata(id: "local.fast"),
            to: fixture.outputURL
        )

        XCTAssertEqual(
            package.definition.defaultMotion?.frames.map(\.duration),
            [.milliseconds(100), .milliseconds(20)]
        )
    }

    func testGIFDecoderPreservesCompositedCanvasAcrossTransparentFrame() throws {
        let fixture = try makeEnvironment()
        let gifURL = fixture.temporaryURL.appendingPathComponent("composited.gif")
        try writeCompositedGIF(to: gifURL)

        let package = try SimpleAnimationPetPackageAdapter().convertAnimatedImage(
            at: gifURL,
            metadata: metadata(id: "local.composited-gif"),
            to: fixture.outputURL
        )

        let colors = try readAtlasPixelColors(
            at: package.atlases[0].fileURL,
            points: [(4, 1), (7, 1)]
        )
        XCTAssertGreaterThan(colors[0].red, colors[0].green)
        XCTAssertGreaterThan(colors[1].green, colors[1].red)
    }

    func testRejectsStaticImageAsAnimatedAndAnimatedPNGInSequence() throws {
        let fixture = try makeEnvironment()
        let staticURL = fixture.temporaryURL.appendingPathComponent("static.png")
        try writePNG(to: staticURL, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let adapter = SimpleAnimationPetPackageAdapter()

        XCTAssertThrowsError(
            try adapter.convertAnimatedImage(
                at: staticURL,
                metadata: metadata(id: "local.static"),
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(error as? SimpleAnimationImportError, .expectedAnimatedImage)
        }

        let animatedURL = fixture.temporaryURL.appendingPathComponent("animated.png")
        try writeAnimatedImage(to: animatedURL, type: .apng, delays: [0.1, 0.1])
        XCTAssertThrowsError(
            try adapter.convertPNGSequence(
                [animatedURL],
                metadata: metadata(id: "local.bad-sequence"),
                to: fixture.outputURL
            )
        ) { error in
            XCTAssertEqual(
                error as? SimpleAnimationImportError,
                .animatedSequenceMember("animated.png")
            )
        }
    }

    func testFailureDoesNotLeavePartialDestination() throws {
        let fixture = try makeEnvironment()
        let missingURL = fixture.temporaryURL.appendingPathComponent("missing.png")

        XCTAssertThrowsError(
            try SimpleAnimationPetPackageAdapter().convertPNGSequence(
                [missingURL],
                metadata: metadata(id: "local.missing"),
                to: fixture.outputURL
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outputURL.path))
        let remaining = try FileManager.default.contentsOfDirectory(
            at: fixture.temporaryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(remaining.contains { $0.lastPathComponent.hasPrefix(".importing-") })
    }

    private func makeEnvironment() throws -> SimpleAdapterFixture {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporaryURL) }
        return SimpleAdapterFixture(
            temporaryURL: temporaryURL,
            outputURL: temporaryURL.appendingPathComponent("converted.monglepet", isDirectory: true)
        )
    }

    private func metadata(id: String) -> SimplePetImportMetadata {
        SimplePetImportMetadata(id: id, displayName: "간편 가져오기 펫")
    }

    private func writeAnimatedImage(
        to fileURL: URL,
        type: AnimatedFixtureType,
        delays: [Double]
    ) throws {
        let destinationType: UTType = type == .gif ? .gif : .png
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                destinationType.identifier as CFString,
                delays.count,
                nil
            )
        )
        let globalDictionary: [CFString: Any]
        switch type {
        case .gif:
            globalDictionary = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
            ]
        case .apng:
            globalDictionary = [
                kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
            ]
        }
        CGImageDestinationSetProperties(destination, globalDictionary as CFDictionary)

        let colors = [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        ]
        for (index, delay) in delays.enumerated() {
            let image = try makeImage(color: colors[index % colors.count])
            let frameProperties: [CFString: Any]
            switch type {
            case .gif:
                frameProperties = [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]
                ]
            case .apng:
                frameProperties = [
                    kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGUnclampedDelayTime: delay]
                ]
            }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fileURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), delays.count)
    }

    private func writePNG(to fileURL: URL, color: CGColor) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, try makeImage(color: color), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeCompositedGIF(to fileURL: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                UTType.gif.identifier as CFString,
                2,
                nil
            )
        )
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.1]
        ] as CFDictionary
        CGImageDestinationAddImage(
            destination,
            try makeImage(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            frameProperties
        )

        let overlayContext = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        overlayContext.clear(CGRect(x: 0, y: 0, width: 4, height: 3))
        overlayContext.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        overlayContext.fill(CGRect(x: 2, y: 0, width: 2, height: 3))
        CGImageDestinationAddImage(
            destination,
            try XCTUnwrap(overlayContext.makeImage()),
            frameProperties
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeImage(color: CGColor) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try XCTUnwrap(context.makeImage())
    }

    private func readAtlasPixelColors(
        at fileURL: URL,
        points: [(Int, Int)]
    ) throws -> [(red: UInt8, green: UInt8, blue: UInt8)] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fileURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try pixels.withUnsafeMutableBytes { bytes in
            try XCTUnwrap(
                CGContext(
                    data: bytes.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
            )
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return points.map { x, y in
            let offset = y * bytesPerRow + x * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
        }
    }
}

private struct SimpleAdapterFixture {
    let temporaryURL: URL
    let outputURL: URL
}

private enum AnimatedFixtureType {
    case gif
    case apng
}
