import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import libwebp

nonisolated enum PetExportImagePolicy: Sendable {
    case pngOnly
    case losslessWebP

    static var current: Self {
        #if DEBUG
        .losslessWebP // Direct QA in Xcode; Release remains PNG until cross-platform QA.
        #else
        .pngOnly // Enable only after Windows and web round-trip QA.
        #endif
    }
}

nonisolated struct WebPExportOptimization: Sendable {
    let data: Data
    let format: PetPackageImageFormat
    let cacheHit: Bool
}

nonisolated struct WebPExportOptimizer {
    static let version = "libwebp-1.6.0-lossless6-exact-v1"
    static let maximumCacheBytes = 128 * 1_024 * 1_024
    typealias Encoder = @Sendable (WebPSourcePixels) throws -> Data

    private let cacheDirectory: URL?
    private let version: String
    private let encoder: Encoder

    init(
        cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MonglePet/SharedWebP", isDirectory: true),
        version: String = Self.version,
        encoder: @escaping Encoder = LosslessWebPCodec.encode
    ) {
        self.cacheDirectory = cacheDirectory
        self.version = version
        self.encoder = encoder
    }

    func optimize(originalPNG: Data, optimizedPNG: Data) -> WebPExportOptimization {
        let fallback = WebPExportOptimization(data: optimizedPNG, format: .png, cacheHit: false)
        guard let pixels = try? WebPSourcePixels(pngData: originalPNG) else { return fallback }
        let hash = SHA256.hash(data: originalPNG).map { String(format: "%02x", $0) }.joined()
        let cacheURL = cacheDirectory?.appendingPathComponent("\(version)-\(hash).webp")
        if let cacheURL,
           let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= Self.maximumCacheBytes,
           let candidate = try? Data(contentsOf: cacheURL),
           LosslessWebPCodec.validates(candidate, against: pixels, originalPNG: originalPNG) {
            return choose(candidate, or: optimizedPNG, cacheHit: true)
        }
        guard let candidate = try? encoder(pixels),
              candidate.count <= Self.maximumCacheBytes,
              LosslessWebPCodec.validates(candidate, against: pixels, originalPNG: originalPNG) else {
            return fallback
        }
        // Keep even a larger, valid candidate: repeated exports must not re-encode it.
        if let cacheURL {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? candidate.write(to: cacheURL, options: .atomic)
            pruneCache()
        }
        return choose(candidate, or: optimizedPNG, cacheHit: false)
    }

    private func choose(_ webP: Data, or png: Data, cacheHit: Bool) -> WebPExportOptimization {
        webP.count < png.count
            ? WebPExportOptimization(data: webP, format: .webP, cacheHit: cacheHit)
            : WebPExportOptimization(data: png, format: .png, cacheHit: cacheHit)
    }

    private func pruneCache() {
        guard let cacheDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
              ) else { return }
        let entries = urls.compactMap { url -> (URL, Int, Date)? in
            guard url.pathExtension == "webp",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) where total > Self.maximumCacheBytes {
            if (try? FileManager.default.removeItem(at: url)) != nil { total -= size }
        }
    }
}

nonisolated enum LosslessWebPCodec {
    enum Failure: Error { case encoding, metadata }

    static func encode(_ pixels: WebPSourcePixels) throws -> Data {
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0, WebPConfigLosslessPreset(&config, 6) != 0 else {
            throw Failure.encoding
        }
        config.exact = 1
        config.thread_level = 0
        guard WebPValidateConfig(&config) != 0 else { throw Failure.encoding }
        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw Failure.encoding }
        defer { WebPPictureFree(&picture) }
        picture.use_argb = 1
        picture.width = Int32(pixels.width)
        picture.height = Int32(pixels.height)
        let imported = pixels.rgba.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(pixels.width * 4))
        }
        guard imported != 0 else { throw Failure.encoding }
        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else { throw Failure.encoding }
        let data = Data(bytes: bytes, count: writer.size)
        guard let exif = pixels.exif else { return data }
        return try data.withUnsafeBytes { buffer in
            var input = WebPData(bytes: buffer.bindMemory(to: UInt8.self).baseAddress, size: data.count)
            guard let mux = WebPMuxCreate(&input, 1) else { throw Failure.metadata }
            defer { WebPMuxDelete(mux) }
            let status = exif.withUnsafeBytes { exifBuffer in
                var chunk = WebPData(bytes: exifBuffer.bindMemory(to: UInt8.self).baseAddress, size: exif.count)
                return WebPMuxSetChunk(mux, "EXIF", &chunk, 1)
            }
            guard status == WEBP_MUX_OK else { throw Failure.metadata }
            var output = WebPData()
            guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else {
                throw Failure.metadata
            }
            defer { WebPDataClear(&output) }
            return Data(bytes: bytes, count: output.size)
        }
    }

    static func validates(_ webP: Data, against pixels: WebPSourcePixels, originalPNG: Data) -> Bool {
        let rawMatches = webP.withUnsafeBytes { buffer -> Bool in
            let inputBytes = buffer.bindMemory(to: UInt8.self).baseAddress
            var features = WebPBitstreamFeatures()
            guard WebPGetFeatures(inputBytes, webP.count, &features) == VP8_STATUS_OK,
                  features.width == pixels.width, features.height == pixels.height,
                  features.format == 2, features.has_animation == 0,
                  features.has_alpha == 1 else { return false }
            var width: Int32 = 0
            var height: Int32 = 0
            guard let decoded = WebPDecodeRGBA(inputBytes, webP.count, &width, &height) else { return false }
            defer { WebPFree(decoded) }
            guard Data(bytes: decoded, count: pixels.rgba.count) == Data(pixels.rgba) else { return false }
            var input = WebPData(bytes: inputBytes, size: webP.count)
            guard let mux = WebPMuxCreate(&input, 0) else { return false }
            defer { WebPMuxDelete(mux) }
            var chunk = WebPData()
            let result = WebPMuxGetChunk(mux, "EXIF", &chunk)
            if let expected = pixels.exif {
                guard result == WEBP_MUX_OK, let bytes = chunk.bytes,
                      Data(bytes: bytes, count: chunk.size) == expected else { return false }
            } else if result != WEBP_MUX_NOT_FOUND { return false }
            for name in ["ICCP", "XMP "] {
                guard WebPMuxGetChunk(mux, name, &chunk) == WEBP_MUX_NOT_FOUND else { return false }
            }
            return true
        }
        // Also exercise the actual macOS decoder/color pipeline used for display/editing.
        guard rawMatches,
              let source = renderedPixels(originalPNG),
              let result = renderedPixels(webP) else { return false }
        return source == result
    }

    static func renderedPixels(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width <= 8_192, image.height <= 8_192,
              let color = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var output = Data(count: image.width * image.height * 4)
        let success = output.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: color,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return success ? output : nil
    }
}
