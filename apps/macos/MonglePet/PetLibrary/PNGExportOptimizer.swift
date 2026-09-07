import Compression
import CryptoKit
import Foundation

nonisolated struct PNGExportOptimization: Equatable, Sendable {
    let data: Data
    let originalByteCount: Int
    let outputByteCount: Int
    let usedOptimizedData: Bool
    let cacheHit: Bool
}

nonisolated struct PNGExportOptimizer {
    static let optimizerVersion = "adaptive-filter-v1"
    static let maximumCacheByteCount = 256 * 1_024 * 1_024

    private let cacheDirectoryURL: URL?
    private let optimizerVersion: String
    private let fileManager: FileManager

    init(
        cacheDirectoryURL: URL? = Self.defaultCacheDirectoryURL(),
        optimizerVersion: String = Self.optimizerVersion,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectoryURL = cacheDirectoryURL
        self.optimizerVersion = optimizerVersion
        self.fileManager = fileManager
    }

    func optimize(fileAt sourceURL: URL) throws -> PNGExportOptimization {
        let sourceData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard let sourceImage = try? PNGImageData(data: sourceData) else {
            return originalResult(sourceData)
        }

        let cacheURL = cachedFileURL(for: sourceData)
        if let cacheURL,
           let cachedData = try? Data(contentsOf: cacheURL, options: .mappedIfSafe),
           cachedData.count < sourceData.count,
           let cachedImage = try? PNGImageData(data: cachedData),
           cachedImage.hasSamePixels(as: sourceImage) {
            return PNGExportOptimization(
                data: cachedData,
                originalByteCount: sourceData.count,
                outputByteCount: cachedData.count,
                usedOptimizedData: true,
                cacheHit: true
            )
        }

        guard let optimizedData = try? sourceImage.optimizedPNGData(),
              optimizedData.count < sourceData.count,
              let optimizedImage = try? PNGImageData(data: optimizedData),
              optimizedImage.hasSamePixels(as: sourceImage) else {
            return originalResult(sourceData)
        }

        if let cacheURL {
            storeCacheBestEffort(optimizedData, at: cacheURL)
        }
        return PNGExportOptimization(
            data: optimizedData,
            originalByteCount: sourceData.count,
            outputByteCount: optimizedData.count,
            usedOptimizedData: true,
            cacheHit: false
        )
    }

    private func originalResult(_ data: Data) -> PNGExportOptimization {
        PNGExportOptimization(
            data: data,
            originalByteCount: data.count,
            outputByteCount: data.count,
            usedOptimizedData: false,
            cacheHit: false
        )
    }

    private func cachedFileURL(for sourceData: Data) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let digest = SHA256.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectoryURL.appendingPathComponent(
            "\(optimizerVersion)-\(digest).png",
            isDirectory: false
        )
    }

    private func storeCacheBestEffort(_ data: Data, at cacheURL: URL) {
        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            pruneCacheBestEffort(in: cacheURL.deletingLastPathComponent())
        } catch {
            // The cache is optional. A valid optimized result is still usable.
        }
    }

    private func pruneCacheBestEffort(in directoryURL: URL) {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let entries: [(url: URL, byteCount: Int, date: Date)] = urls.compactMap {
            url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return (
                url,
                max(values.fileSize ?? 0, 0),
                values.contentModificationDate ?? .distantPast
            )
        }
        var totalByteCount = entries.reduce(0) { $0 + $1.byteCount }
        guard totalByteCount > Self.maximumCacheByteCount else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard totalByteCount > Self.maximumCacheByteCount else { break }
            do {
                try fileManager.removeItem(at: entry.url)
                totalByteCount -= entry.byteCount
            } catch {
                continue
            }
        }
    }

    private static func defaultCacheDirectoryURL() -> URL? {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "MonglePet/SharedPNG/\(optimizerVersion)",
            isDirectory: true
        )
    }
}

private nonisolated struct PNGImageData {
    private static let signature = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    ])

    let chunks: [PNGChunk]
    let width: Int
    let height: Int
    let bytesPerPixel: Int
    let rows: [UInt8]

    init(data: Data) throws {
        guard data.count >= Self.signature.count,
              data.prefix(Self.signature.count) == Self.signature else {
            throw PNGOptimizationError.invalidPNG
        }
        chunks = try Self.parseChunks(data)
        guard let header = chunks.first(where: { $0.type == "IHDR" }),
              header.data.count == 13 else {
            throw PNGOptimizationError.unsupportedPNG
        }
        width = try Self.integer(from: header.data, at: 0)
        height = try Self.integer(from: header.data, at: 4)
        let bitDepth = Int(header.data[8])
        let colorType = Int(header.data[9])
        let compressionMethod = header.data[10]
        let filterMethod = header.data[11]
        let interlaceMethod = header.data[12]
        guard width > 0,
              height > 0,
              bitDepth == 8,
              compressionMethod == 0,
              filterMethod == 0,
              interlaceMethod == 0,
              let channelCount = Self.channelCount(for: colorType) else {
            throw PNGOptimizationError.unsupportedPNG
        }
        bytesPerPixel = channelCount

        let (rowByteCount, rowOverflow) = width.multipliedReportingOverflow(
            by: channelCount
        )
        let (scanlineByteCount, scanlineOverflow) = rowByteCount
            .addingReportingOverflow(1)
        let (expectedByteCount, imageOverflow) = scanlineByteCount
            .multipliedReportingOverflow(by: height)
        guard !rowOverflow,
              !scanlineOverflow,
              !imageOverflow,
              expectedByteCount <= 256 * 1_024 * 1_024 else {
            throw PNGOptimizationError.unsupportedPNG
        }

        let compressed = chunks
            .filter { $0.type == "IDAT" }
            .reduce(into: Data()) { $0.append($1.data) }
        let filtered = try Self.inflateZlib(
            compressed,
            expectedByteCount: expectedByteCount
        )
        rows = try Self.unfilteredRows(
            filtered,
            width: width,
            height: height,
            bytesPerPixel: channelCount
        )
    }

    func hasSamePixels(as other: PNGImageData) -> Bool {
        width == other.width
            && height == other.height
            && bytesPerPixel == other.bytesPerPixel
            && rows == other.rows
            && chunks.filter { $0.type != "IDAT" }.map(\.encoded)
                == other.chunks.filter { $0.type != "IDAT" }.map(\.encoded)
    }

    func optimizedPNGData() throws -> Data {
        let filtered = Self.adaptivelyFilteredRows(
            rows,
            width: width,
            height: height,
            bytesPerPixel: bytesPerPixel
        )
        let zlibData = try Self.deflateZlib(filtered)
        var result = Self.signature
        var insertedImageData = false
        for chunk in chunks {
            if chunk.type == "IDAT" {
                if !insertedImageData {
                    result.append(Self.chunk(type: "IDAT", data: zlibData))
                    insertedImageData = true
                }
            } else {
                result.append(chunk.encoded)
            }
        }
        guard insertedImageData else {
            throw PNGOptimizationError.invalidPNG
        }
        return result
    }

    private static func parseChunks(_ data: Data) throws -> [PNGChunk] {
        var chunks: [PNGChunk] = []
        var offset = signature.count
        var foundEnd = false
        while offset < data.count {
            guard offset <= data.count - 12 else {
                throw PNGOptimizationError.invalidPNG
            }
            let length = try integer(from: data, at: offset)
            let (chunkEnd, overflow) = offset.addingReportingOverflow(12 + length)
            guard !overflow, chunkEnd <= data.count else {
                throw PNGOptimizationError.invalidPNG
            }
            let typeData = data[(offset + 4)..<(offset + 8)]
            guard let type = String(data: typeData, encoding: .ascii),
                  type.utf8.count == 4 else {
                throw PNGOptimizationError.invalidPNG
            }
            let payload = Data(data[(offset + 8)..<(offset + 8 + length)])
            chunks.append(
                PNGChunk(
                    type: type,
                    data: payload,
                    encoded: Data(data[offset..<chunkEnd])
                )
            )
            offset = chunkEnd
            if type == "IEND" {
                foundEnd = true
                break
            }
        }
        guard foundEnd,
              offset == data.count,
              chunks.first?.type == "IHDR",
              chunks.contains(where: { $0.type == "IDAT" }) else {
            throw PNGOptimizationError.invalidPNG
        }
        return chunks
    }

    private static func inflateZlib(
        _ data: Data,
        expectedByteCount: Int
    ) throws -> [UInt8] {
        guard data.count >= 6 else {
            throw PNGOptimizationError.invalidPNG
        }
        let cmf = Int(data[0])
        let flg = Int(data[1])
        guard cmf & 0x0F == 8,
              ((cmf << 8) + flg).isMultiple(of: 31),
              flg & 0x20 == 0 else {
            throw PNGOptimizationError.unsupportedPNG
        }
        let deflateData = data.dropFirst(2).dropLast(4)
        var output = [UInt8](repeating: 0, count: expectedByteCount)
        let decodedByteCount = output.withUnsafeMutableBytes { outputBuffer in
            deflateData.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedByteCount,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    deflateData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedByteCount == expectedByteCount,
              adler32(output) == integerUnchecked(from: data, at: data.count - 4) else {
            throw PNGOptimizationError.invalidPNG
        }
        return output
    }

    private static func deflateZlib(_ data: [UInt8]) throws -> Data {
        let capacity = data.count + data.count / 1_000 + 128
        var compressed = [UInt8](repeating: 0, count: max(capacity, 128))
        let compressedCapacity = compressed.count
        let compressedByteCount = compressed.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_encode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressedCapacity,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard compressedByteCount > 0 else {
            throw PNGOptimizationError.compressionFailed
        }
        var result = Data([0x78, 0x9C])
        result.append(contentsOf: compressed.prefix(compressedByteCount))
        appendUInt32(adler32(data), to: &result)
        return result
    }

    private static func unfilteredRows(
        _ filtered: [UInt8],
        width: Int,
        height: Int,
        bytesPerPixel: Int
    ) throws -> [UInt8] {
        let rowByteCount = width * bytesPerPixel
        var rows = [UInt8](repeating: 0, count: rowByteCount * height)
        for row in 0..<height {
            let inputOffset = row * (rowByteCount + 1)
            let outputOffset = row * rowByteCount
            let filter = filtered[inputOffset]
            guard filter <= 4 else {
                throw PNGOptimizationError.invalidPNG
            }
            for column in 0..<rowByteCount {
                let left = column >= bytesPerPixel
                    ? rows[outputOffset + column - bytesPerPixel]
                    : 0
                let up = row > 0
                    ? rows[outputOffset - rowByteCount + column]
                    : 0
                let upperLeft = row > 0 && column >= bytesPerPixel
                    ? rows[outputOffset - rowByteCount + column - bytesPerPixel]
                    : 0
                let predictor: UInt8
                switch filter {
                case 0:
                    predictor = 0
                case 1:
                    predictor = left
                case 2:
                    predictor = up
                case 3:
                    predictor = UInt8((Int(left) + Int(up)) / 2)
                default:
                    predictor = paeth(left, up, upperLeft)
                }
                rows[outputOffset + column] = filtered[inputOffset + 1 + column]
                    &+ predictor
            }
        }
        return rows
    }

    private static func adaptivelyFilteredRows(
        _ rows: [UInt8],
        width: Int,
        height: Int,
        bytesPerPixel: Int
    ) -> [UInt8] {
        let rowByteCount = width * bytesPerPixel
        var filtered = [UInt8](
            repeating: 0,
            count: height * (rowByteCount + 1)
        )
        var candidate = [UInt8](repeating: 0, count: rowByteCount)
        var best = candidate
        for row in 0..<height {
            let rowOffset = row * rowByteCount
            var bestFilter: UInt8 = 0
            var bestScore = Int64.max
            for filter in UInt8(0)...UInt8(4) {
                var score: Int64 = 0
                for column in 0..<rowByteCount {
                    let current = rows[rowOffset + column]
                    let left = column >= bytesPerPixel
                        ? rows[rowOffset + column - bytesPerPixel]
                        : 0
                    let up = row > 0
                        ? rows[rowOffset - rowByteCount + column]
                        : 0
                    let upperLeft = row > 0 && column >= bytesPerPixel
                        ? rows[rowOffset - rowByteCount + column - bytesPerPixel]
                        : 0
                    let predictor: UInt8
                    switch filter {
                    case 0:
                        predictor = 0
                    case 1:
                        predictor = left
                    case 2:
                        predictor = up
                    case 3:
                        predictor = UInt8((Int(left) + Int(up)) / 2)
                    default:
                        predictor = paeth(left, up, upperLeft)
                    }
                    let value = current &- predictor
                    candidate[column] = value
                    score += Int64(min(Int(value), 256 - Int(value)))
                }
                if score < bestScore {
                    bestScore = score
                    bestFilter = filter
                    best = candidate
                }
            }
            let outputOffset = row * (rowByteCount + 1)
            filtered[outputOffset] = bestFilter
            filtered.replaceSubrange(
                (outputOffset + 1)..<(outputOffset + 1 + rowByteCount),
                with: best
            )
        }
        return filtered
    }

    private static func paeth(_ left: UInt8, _ up: UInt8, _ upperLeft: UInt8) -> UInt8 {
        let left = Int(left)
        let up = Int(up)
        let upperLeft = Int(upperLeft)
        let estimate = left + up - upperLeft
        let leftDistance = abs(estimate - left)
        let upDistance = abs(estimate - up)
        let upperLeftDistance = abs(estimate - upperLeft)
        if leftDistance <= upDistance && leftDistance <= upperLeftDistance {
            return UInt8(left)
        }
        if upDistance <= upperLeftDistance {
            return UInt8(up)
        }
        return UInt8(upperLeft)
    }

    private static func channelCount(for colorType: Int) -> Int? {
        switch colorType {
        case 0, 3:
            1
        case 2:
            3
        case 4:
            2
        case 6:
            4
        default:
            nil
        }
    }

    private static func integer(from data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, offset <= data.count - 4 else {
            throw PNGOptimizationError.invalidPNG
        }
        let value = integerUnchecked(from: data, at: offset)
        return Int(value)
    }

    private static func integerUnchecked(from data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let modulus: UInt32 = 65_521
        var first: UInt32 = 1
        var second: UInt32 = 0
        for byte in bytes {
            first = (first + UInt32(byte)) % modulus
            second = (second + first) % modulus
        }
        return (second << 16) | first
    }

    private static func chunk(type: String, data: Data) -> Data {
        let typeData = Data(type.utf8)
        var result = Data()
        appendUInt32(UInt32(data.count), to: &result)
        result.append(typeData)
        result.append(data)
        appendUInt32(crc32(typeData + data), to: &result)
        return result
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum = UInt32.max
        for byte in data {
            let index = Int((checksum ^ UInt32(byte)) & 0xFF)
            checksum = Self.crcTable[index] ^ (checksum >> 8)
        }
        return checksum ^ UInt32.max
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)
        for _ in 0..<8 {
            current = current & 1 == 1
                ? 0xEDB88320 ^ (current >> 1)
                : current >> 1
        }
        return current
    }
}

private nonisolated struct PNGChunk {
    let type: String
    let data: Data
    let encoded: Data
}

private nonisolated enum PNGOptimizationError: Error {
    case invalidPNG
    case unsupportedPNG
    case compressionFailed
}
