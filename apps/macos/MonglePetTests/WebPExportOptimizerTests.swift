import CoreGraphics
import Foundation
import XCTest
import zlib
@testable import MonglePet

final class WebPExportOptimizerTests: XCTestCase {
    func testCurrentDebugPolicyEnablesLosslessWebP() {
        XCTAssertEqual(PetExportImagePolicy.current, .losslessWebP)
    }

    func testLosslessWebPPreservesEverySampleIncludingTransparentRGBAndNativeRendering() throws {
        let png = try WebPExportFixture.png()
        let source = try WebPSourcePixels(pngData: png)
        XCTAssertEqual(source.rgba[3], 0)
        XCTAssertNotEqual(Array(source.rgba[0..<3]), [0, 0, 0])
        let result = WebPExportOptimizer(cacheDirectory: nil).optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertEqual(result.format, .webP)
        XCTAssertLessThan(result.data.count, png.count)
        XCTAssertTrue(LosslessWebPCodec.validates(result.data, against: source, originalPNG: png))
        XCTAssertEqual(LosslessWebPCodec.renderedPixels(png), LosslessWebPCodec.renderedPixels(result.data))
    }

    func testCacheIsReusedAndSourceVersionOrCorruptionInvalidatesIt() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let png = try WebPExportFixture.png()
        let first = WebPExportOptimizer(cacheDirectory: cache).optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertFalse(first.cacheHit)
        let noEncoder = WebPExportOptimizer(cacheDirectory: cache, encoder: { _ in throw TestFailure.expected })
        let cached = noEncoder.optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertTrue(cached.cacheHit)
        XCTAssertEqual(cached.data, first.data)
        let changed = try WebPExportFixture.png(seed: 2)
        XCTAssertFalse(noEncoder.optimize(originalPNG: changed, optimizedPNG: changed).cacheHit)
        let newVersion = WebPExportOptimizer(cacheDirectory: cache, version: "next", encoder: { _ in throw TestFailure.expected })
        XCTAssertEqual(newVersion.optimize(originalPNG: png, optimizedPNG: png).format, .png)
        let cacheFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        try Data("damaged".utf8).write(to: cacheFile)
        XCTAssertEqual(noEncoder.optimize(originalPNG: png, optimizedPNG: png).data, png)
    }

    func testFailureIncorrectPixelsAndLargerCandidateUsePNG() throws {
        let png = try WebPExportFixture.png()
        let failed = WebPExportOptimizer(cacheDirectory: nil, encoder: { _ in throw TestFailure.expected })
        XCTAssertEqual(failed.optimize(originalPNG: png, optimizedPNG: png).data, png)
        let changed = try WebPSourcePixels(pngData: WebPExportFixture.png(seed: 2))
        let wrong = WebPExportOptimizer(cacheDirectory: nil, encoder: { _ in try LosslessWebPCodec.encode(changed) })
        XCTAssertEqual(wrong.optimize(originalPNG: png, optimizedPNG: png).format, .png)
        let bigger = WebPExportOptimizer(cacheDirectory: nil, encoder: { source in
            var data = try LosslessWebPCodec.encode(source)
            // A valid RIFF unknown chunk makes the otherwise correct encoding larger.
            data.append(Data("JUNK".utf8))
            data.append(WebPExportFixture.littleEndian(UInt32(png.count * 2)))
            data.append(Data(repeating: 0, count: png.count * 2))
            data.replaceSubrange(4..<8, with: WebPExportFixture.littleEndian(UInt32(data.count - 8)))
            return data
        })
        let result = bigger.optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertEqual(result.format, .png)
        XCTAssertEqual(result.data, png)
    }

    func testExifIsPreservedAndUnsupportedColorMetadataKeepsPNG() throws {
        let exif = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0,
                         0x12, 1, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0])
        let png = try WebPExportFixture.png(extraChunks: [("eXIf", exif)])
        let source = try WebPSourcePixels(pngData: png)
        XCTAssertEqual(source.exif, exif)
        let result = WebPExportOptimizer(cacheDirectory: nil).optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertEqual(result.format, .webP)
        XCTAssertTrue(LosslessWebPCodec.validates(result.data, against: source, originalPNG: png))

        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let profile = try XCTUnwrap(space.copyICCData()) as Data
        var iccp = Data("DisplayP3\0".utf8)
        iccp.append(0)
        iccp.append(try WebPExportFixture.deflate(profile))
        let wideGamut = try WebPExportFixture.png(extraChunks: [("iCCP", iccp)], includeSRGB: false)
        let fallback = WebPExportOptimizer(cacheDirectory: nil).optimize(originalPNG: wideGamut, optimizedPNG: wideGamut)
        XCTAssertEqual(fallback.format, .png)
        XCTAssertEqual(fallback.data, wideGamut)
    }

    func testOpaqueRGBAKeepsPNGWhenWebPWouldDropRequiredAlphaChannel() throws {
        let png = try WebPExportFixture.png(opaque: true)
        let result = WebPExportOptimizer(cacheDirectory: nil).optimize(originalPNG: png, optimizedPNG: png)
        XCTAssertEqual(result.format, .png)
        XCTAssertEqual(result.data, png)
    }

    private enum TestFailure: Error { case expected }
}

enum WebPExportFixture {
    static func png(width: Int = 128, height: Int = 128, seed: Int = 1,
                    extraChunks: [(String, Data)] = [], includeSRGB: Bool = true, opaque: Bool = false) throws -> Data {
        var rows = Data()
        for y in 0..<height {
            rows.append(0)
            for x in 0..<width {
                rows.append(contentsOf: [UInt8((x * 3 + seed * 47) % 256), UInt8((y * 5 + seed) % 256),
                                        UInt8(((x / 8 + y / 8) * 13 + seed) % 256),
                                        opaque ? 255 : (x % 7 == 0 ? 0 : (x % 5 == 0 ? 128 : 255))])
            }
        }
        var header = bigEndian(UInt32(width)) + bigEndian(UInt32(height))
        header.append(contentsOf: [8, 6, 0, 0, 0])
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        png.append(chunk("IHDR", header))
        if includeSRGB { png.append(chunk("sRGB", Data([0]))) }
        for (name, data) in extraChunks { png.append(chunk(name, data)) }
        png.append(chunk("IDAT", try deflate(rows)))
        png.append(chunk("IEND", Data()))
        return png
    }

    static func deflate(_ data: Data) throws -> Data {
        var length = compressBound(uLong(data.count))
        var output = Data(count: Int(length))
        let status = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compress2(destination.bindMemory(to: UInt8.self).baseAddress, &length,
                          source.bindMemory(to: UInt8.self).baseAddress, uLong(data.count), 6)
            }
        }
        guard status == Z_OK else { throw CocoaError(.fileWriteUnknown) }
        output.count = Int(length)
        return output
    }

    static func chunk(_ type: String, _ payload: Data) -> Data {
        let content = Data(type.utf8) + payload
        let checksum = content.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(content.count)) }
        return bigEndian(UInt32(payload.count)) + content + bigEndian(UInt32(checksum))
    }

    static func bigEndian(_ n: UInt32) -> Data {
        Data([UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
    }

    static func littleEndian(_ n: UInt32) -> Data { Data(bigEndian(n).reversed()) }
}
