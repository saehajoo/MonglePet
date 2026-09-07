import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MonglePet

final class PNGExportOptimizerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL,
           FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func testOptimizationPreservesPixelsAndNeverChangesSource() throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source.png")
        try writePatternedPNG(to: sourceURL, seed: 1)
        let sourceData = try Data(contentsOf: sourceURL)
        let sourceModificationDate = try XCTUnwrap(
            sourceURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        )
        let optimizer = PNGExportOptimizer(
            cacheDirectoryURL: temporaryDirectoryURL.appendingPathComponent("cache")
        )

        let result = try optimizer.optimize(fileAt: sourceURL)

        XCTAssertTrue(result.usedOptimizedData)
        XCTAssertLessThan(result.outputByteCount, result.originalByteCount)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertEqual(
            try sourceURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
            sourceModificationDate
        )
        XCTAssertEqual(
            try decodedPixels(from: result.data),
            try decodedPixels(from: sourceData)
        )
    }

    func testUnchangedSourceUsesCacheAndChangedSourceDoesNot() throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source.png")
        let cacheURL = temporaryDirectoryURL.appendingPathComponent("cache")
        try writePatternedPNG(to: sourceURL, seed: 2)
        let optimizer = PNGExportOptimizer(cacheDirectoryURL: cacheURL)

        let first = try optimizer.optimize(fileAt: sourceURL)
        let second = try optimizer.optimize(fileAt: sourceURL)

        XCTAssertTrue(first.usedOptimizedData)
        XCTAssertFalse(first.cacheHit)
        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(second.data, first.data)

        try writePatternedPNG(to: sourceURL, seed: 3)
        let changed = try optimizer.optimize(fileAt: sourceURL)
        XCTAssertTrue(changed.usedOptimizedData)
        XCTAssertFalse(changed.cacheHit)
        XCTAssertNotEqual(changed.data, first.data)
    }

    func testUnreadablePNGReturnsOriginalBytesWithoutCaching() throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("broken.png")
        let original = Data("not a png".utf8)
        try original.write(to: sourceURL)
        let cacheURL = temporaryDirectoryURL.appendingPathComponent("cache")

        let result = try PNGExportOptimizer(
            cacheDirectoryURL: cacheURL
        ).optimize(fileAt: sourceURL)

        XCTAssertEqual(result.data, original)
        XCTAssertFalse(result.usedOptimizedData)
        XCTAssertFalse(result.cacheHit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testOptimizerVersionAndCorruptCacheCannotReuseStaleResult() throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source.png")
        let cacheURL = temporaryDirectoryURL.appendingPathComponent("cache")
        try writePatternedPNG(to: sourceURL, seed: 4)
        let firstOptimizer = PNGExportOptimizer(
            cacheDirectoryURL: cacheURL,
            optimizerVersion: "test-v1"
        )
        let first = try firstOptimizer.optimize(fileAt: sourceURL)
        XCTAssertTrue(first.usedOptimizedData)

        let versionChanged = try PNGExportOptimizer(
            cacheDirectoryURL: cacheURL,
            optimizerVersion: "test-v2"
        ).optimize(fileAt: sourceURL)
        XCTAssertFalse(versionChanged.cacheHit)
        XCTAssertEqual(versionChanged.data, first.data)

        let v1CacheFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: nil
            ).first(where: { $0.lastPathComponent.hasPrefix("test-v1-") })
        )
        try Data("damaged cache".utf8).write(to: v1CacheFile, options: .atomic)
        let recovered = try firstOptimizer.optimize(fileAt: sourceURL)
        XCTAssertFalse(recovered.cacheHit)
        XCTAssertEqual(
            try decodedPixels(from: recovered.data),
            try decodedPixels(from: Data(contentsOf: sourceURL))
        )
    }

    private func writePatternedPNG(to url: URL, seed: UInt8) throws {
        let width = 512
        let height = 384
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 32..<352 {
            for x in 48..<464 where (x / 32 + y / 32).isMultiple(of: 3) {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8((x + Int(seed) * 17) % 255)
                pixels[offset + 1] = UInt8((y + Int(seed) * 29) % 255)
                pixels[offset + 2] = seed &* 41
                pixels[offset + 3] = 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func decodedPixels(from data: Data) throws -> Data {
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let context = try XCTUnwrap(rendered)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return Data(pixels)
    }
}
