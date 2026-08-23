import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum SpriteSheetImportError: Error, Equatable, Sendable {
    case missingSource(String)
    case symbolicLink(String)
    case sourceFileTooLarge(String)
    case unsupportedImageFormat(String)
    case imageFormatMismatch(String)
    case animatedImageUnsupported
    case invalidImage(String)
    case imageDimensionsExceeded
    case decodedPixelLimitExceeded
    case invalidGrid
    case emptySelection
    case invalidFrameRegion
    case cannotProcessImage
}

extension SpriteSheetImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingSource(path):
            "스프라이트 시트 파일을 찾을 수 없습니다: \(path)"
        case let .symbolicLink(path):
            "스프라이트 시트에 심볼릭 링크를 사용할 수 없습니다: \(path)"
        case let .sourceFileTooLarge(path):
            "스프라이트 시트 파일 크기가 제한을 초과했습니다: \(path)"
        case let .unsupportedImageFormat(path):
            "정적 PNG 또는 WebP 스프라이트 시트만 사용할 수 있습니다: \(path)"
        case let .imageFormatMismatch(path):
            "스프라이트 시트 확장자와 실제 이미지 형식이 다릅니다: \(path)"
        case .animatedImageUnsupported:
            "animated WebP와 APNG는 스프라이트 시트로 사용할 수 없습니다."
        case let .invalidImage(path):
            "스프라이트 시트를 디코딩할 수 없습니다: \(path)"
        case .imageDimensionsExceeded:
            "스프라이트 시트 크기가 제한을 초과했습니다."
        case .decodedPixelLimitExceeded:
            "스프라이트 시트의 디코딩 픽셀 제한을 초과했습니다."
        case .invalidGrid:
            "행과 열은 각각 1~32 사이여야 합니다."
        case .emptySelection:
            "가져올 프레임을 하나 이상 선택해 주세요."
        case .invalidFrameRegion:
            "선택한 프레임 경계가 이미지 범위를 벗어났습니다."
        case .cannotProcessImage:
            "스프라이트 시트 픽셀을 처리하지 못했습니다."
        }
    }
}

nonisolated struct SpriteSheetColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    static let clear = SpriteSheetColor(red: 0, green: 0, blue: 0, alpha: 0)
}

nonisolated struct SpriteSheetDocument: @unchecked Sendable {
    let sourceURL: URL
    let image: CGImage
    let pixelSize: PixelSize
    let suggestedRegions: [PixelRect]
    let suggestedBackgroundColor: SpriteSheetColor
    let hasTransparentBackground: Bool
}

nonisolated struct SpriteSheetBackgroundRemoval: Equatable, Sendable {
    let color: SpriteSheetColor
    let tolerance: Int
}

nonisolated struct SpriteSheetGridDimensions: Equatable, Sendable {
    let rows: Int
    let columns: Int
}

nonisolated struct SpriteSheetFrameExtractor {
    private static let maximumGridDimension = 32
    fileprivate static let alphaThreshold: UInt8 = 12
    private static let backgroundDetectionTolerance = 28

    private let limits: PetPackageLimits
    private let fileManager: FileManager
    private let securityScopedAccess: SecurityScopedResourceAccess

    init(
        limits: PetPackageLimits = .standard,
        fileManager: FileManager = .default,
        securityScopedAccess: SecurityScopedResourceAccess = SecurityScopedResourceAccess()
    ) {
        self.limits = limits
        self.fileManager = fileManager
        self.securityScopedAccess = securityScopedAccess
    }

    func load(at sourceURL: URL) throws -> SpriteSheetDocument {
        try securityScopedAccess.withAccess(to: sourceURL) {
            try validateSourceFile(sourceURL)
            let fileExtension = sourceURL.pathExtension.lowercased()
            let expectedType: String
            switch fileExtension {
            case "png":
                expectedType = UTType.png.identifier
            case "webp":
                expectedType = UTType.webP.identifier
            default:
                throw SpriteSheetImportError.unsupportedImageFormat(
                    sourceURL.lastPathComponent
                )
            }
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let actualType = CGImageSourceGetType(source) as String? else {
                throw SpriteSheetImportError.invalidImage(sourceURL.lastPathComponent)
            }
            guard actualType == expectedType else {
                throw SpriteSheetImportError.imageFormatMismatch(
                    sourceURL.lastPathComponent
                )
            }
            guard CGImageSourceGetCount(source) == 1 else {
                throw SpriteSheetImportError.animatedImageUnsupported
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw SpriteSheetImportError.invalidImage(sourceURL.lastPathComponent)
            }
            try validateDimensions(image)
            let buffer = try PixelBuffer(image: image)
            let background = buffer.suggestedBackgroundColor
            let transparent = buffer.hasTransparentCorner
            let mask = buffer.foregroundMask(
                backgroundColor: background,
                usesAlpha: transparent,
                tolerance: Self.backgroundDetectionTolerance
            )
            let regions = suggestedRegions(
                mask: mask,
                width: image.width,
                height: image.height
            )
            return SpriteSheetDocument(
                sourceURL: sourceURL,
                image: image,
                pixelSize: PixelSize(width: image.width, height: image.height),
                suggestedRegions: regions,
                suggestedBackgroundColor: background,
                hasTransparentBackground: transparent
            )
        }
    }

    func uniformGridRegions(
        pixelSize: PixelSize,
        rows: Int,
        columns: Int,
        inset: Int = 0
    ) throws -> [PixelRect] {
        guard 1...Self.maximumGridDimension ~= rows,
              1...Self.maximumGridDimension ~= columns,
              pixelSize.width > 0,
              pixelSize.height > 0,
              inset >= 0 else {
            throw SpriteSheetImportError.invalidGrid
        }
        let frameCount = rows * columns
        guard frameCount <= limits.maximumFrameCount else {
            throw SpriteSheetImportError.invalidGrid
        }

        return try (0..<rows).flatMap { row in
            try (0..<columns).map { column in
                let left = pixelSize.width * column / columns
                let right = pixelSize.width * (column + 1) / columns
                let top = pixelSize.height * row / rows
                let bottom = pixelSize.height * (row + 1) / rows
                let rect = PixelRect(
                    x: left + inset,
                    y: top + inset,
                    width: right - left - inset * 2,
                    height: bottom - top - inset * 2
                )
                guard rect.isContained(in: pixelSize) else {
                    throw SpriteSheetImportError.invalidGrid
                }
                return rect
            }
        }
    }

    func inferredGridDimensions(
        for regions: [PixelRect]
    ) -> SpriteSheetGridDimensions {
        guard !regions.isEmpty else {
            return SpriteSheetGridDimensions(rows: 1, columns: 1)
        }

        let rowOrigins = Set(regions.map(\.y))
        let columnOrigins = Set(regions.map(\.x))
        let rows = rowOrigins.count
        let columns = columnOrigins.count
        guard 1...Self.maximumGridDimension ~= rows,
              1...Self.maximumGridDimension ~= columns,
              rows * columns >= regions.count else {
            return SpriteSheetGridDimensions(
                rows: 1,
                columns: min(Self.maximumGridDimension, regions.count)
            )
        }
        return SpriteSheetGridDimensions(rows: rows, columns: columns)
    }

    func orderedSelectedRegions(
        _ regions: [PixelRect],
        selectedIndices: Set<Int>,
        clickedOrder: [Int]?
    ) -> [PixelRect] {
        orderedSelectedRegionIndices(
            regionCount: regions.count,
            selectedIndices: selectedIndices,
            clickedOrder: clickedOrder
        ).map { regions[$0] }
    }

    func orderedSelectedRegionIndices(
        regionCount: Int,
        selectedIndices: Set<Int>,
        clickedOrder: [Int]?
    ) -> [Int] {
        guard regionCount > 0 else {
            return []
        }
        let validIndices = 0..<regionCount
        let candidateIndices = clickedOrder ?? Array(validIndices)
        var included = Set<Int>()
        return candidateIndices.compactMap { index in
            guard validIndices.contains(index),
                  selectedIndices.contains(index),
                  included.insert(index).inserted else {
                return nil
            }
            return index
        }
    }

    func processedImage(
        from document: SpriteSheetDocument,
        removingBackground removal: SpriteSheetBackgroundRemoval?
    ) throws -> CGImage {
        guard let removal else {
            return document.image
        }
        guard 0...255 ~= removal.tolerance else {
            throw SpriteSheetImportError.cannotProcessImage
        }
        var buffer = try PixelBuffer(image: document.image)
        buffer.removeBackground(
            color: removal.color,
            tolerance: removal.tolerance
        )
        return try buffer.makeImage()
    }

    func extractFrames(
        from document: SpriteSheetDocument,
        regions: [PixelRect],
        removingBackground removal: SpriteSheetBackgroundRemoval?
    ) throws -> [CGImage] {
        guard !regions.isEmpty else {
            throw SpriteSheetImportError.emptySelection
        }
        guard regions.count <= limits.maximumFrameCount else {
            throw SpriteSheetImportError.invalidGrid
        }
        guard regions.allSatisfy({ $0.isContained(in: document.pixelSize) }) else {
            throw SpriteSheetImportError.invalidFrameRegion
        }
        let image = try processedImage(from: document, removingBackground: removal)
        return try regions.map { region in
            guard let frame = ImageCropProcessor().crop(image, to: region) else {
                throw SpriteSheetImportError.invalidFrameRegion
            }
            return frame
        }
    }

    private func validateSourceFile(_ sourceURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw SpriteSheetImportError.missingSource(sourceURL.path)
        }
        do {
            let values = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw SpriteSheetImportError.symbolicLink(sourceURL.lastPathComponent)
            }
            guard values.isRegularFile == true else {
                throw SpriteSheetImportError.missingSource(sourceURL.path)
            }
            guard Int64(values.fileSize ?? 0) <= limits.maximumExpandedByteCount else {
                throw SpriteSheetImportError.sourceFileTooLarge(
                    sourceURL.lastPathComponent
                )
            }
        } catch let error as SpriteSheetImportError {
            throw error
        } catch {
            throw SpriteSheetImportError.missingSource(sourceURL.path)
        }
    }

    private func validateDimensions(_ image: CGImage) throws {
        guard image.width > 0,
              image.height > 0,
              image.width <= limits.maximumImageDimension,
              image.height <= limits.maximumImageDimension else {
            throw SpriteSheetImportError.imageDimensionsExceeded
        }
        guard Int64(image.width) * Int64(image.height)
            <= limits.maximumDecodedPixelCount else {
            throw SpriteSheetImportError.decodedPixelLimitExceeded
        }
    }

    private func suggestedRegions(
        mask: [Bool],
        width: Int,
        height: Int
    ) -> [PixelRect] {
        let columnCounts = (0..<width).map { x in
            (0..<height).reduce(into: 0) { count, y in
                if mask[y * width + x] {
                    count += 1
                }
            }
        }
        let rowCounts = (0..<height).map { y in
            (0..<width).reduce(into: 0) { count, x in
                if mask[y * width + x] {
                    count += 1
                }
            }
        }
        let columns = activeRuns(
            counts: columnCounts,
            threshold: max(1, height / 512),
            bridge: max(1, width / 256)
        )
        let rows = activeRuns(
            counts: rowCounts,
            threshold: max(1, width / 512),
            bridge: max(1, height / 256)
        )
        let pixelSize = PixelSize(width: width, height: height)
        let columnCells = cellRanges(around: columns, length: width)
        let rowCells = cellRanges(around: rows, length: height)
        let candidates = rows.enumerated().flatMap { rowIndex, row in
            columns.enumerated().compactMap { columnIndex, column -> PixelRect? in
                let raw = PixelRect(
                    x: column.lowerBound,
                    y: row.lowerBound,
                    width: column.count,
                    height: row.count
                )
                let foregroundCount = foregroundCount(
                    mask: mask,
                    imageWidth: width,
                    rect: raw
                )
                guard foregroundCount >= max(1, raw.width * raw.height / 1_000) else {
                    return nil
                }
                let columnCell = columnCells[columnIndex]
                let rowCell = rowCells[rowIndex]
                let cell = PixelRect(
                    x: columnCell.lowerBound,
                    y: rowCell.lowerBound,
                    width: columnCell.count,
                    height: rowCell.count
                )
                return cell.isContained(in: pixelSize) ? cell : nil
            }
        }
        if candidates.count > 1, candidates.count <= limits.maximumFrameCount {
            return candidates
        }
        return [PixelRect(x: 0, y: 0, width: width, height: height)]
    }

    private func activeRuns(
        counts: [Int],
        threshold: Int,
        bridge: Int
    ) -> [Range<Int>] {
        var active = counts.map { $0 >= threshold }
        var index = 0
        while index < active.count {
            guard !active[index] else {
                index += 1
                continue
            }
            let start = index
            while index < active.count, !active[index] {
                index += 1
            }
            let end = index
            if start > 0, end < active.count, end - start <= bridge {
                for bridgedIndex in start..<end {
                    active[bridgedIndex] = true
                }
            }
        }

        var result: [Range<Int>] = []
        index = 0
        while index < active.count {
            guard active[index] else {
                index += 1
                continue
            }
            let start = index
            while index < active.count, active[index] {
                index += 1
            }
            result.append(start..<index)
        }
        return result
    }

    private func cellRanges(
        around contentRuns: [Range<Int>],
        length: Int
    ) -> [Range<Int>] {
        guard !contentRuns.isEmpty, length > 0 else {
            return []
        }
        guard contentRuns.count > 1 else {
            return [0..<length]
        }

        if contentRuns.enumerated().allSatisfy({ index, run in
            let expectedCenter = Double(2 * index + 1) * Double(length)
                / Double(contentRuns.count * 2)
            let actualCenter = Double(run.lowerBound + run.upperBound) / 2
            let cellLength = Double(length) / Double(contentRuns.count)
            return abs(actualCenter - expectedCenter) <= cellLength * 0.25
        }) {
            return contentRuns.indices.map { index in
                let lowerBound = length * index / contentRuns.count
                let upperBound = length * (index + 1) / contentRuns.count
                return lowerBound..<upperBound
            }
        }

        var boundaries = [0]
        for index in 0..<(contentRuns.count - 1) {
            let leftCenter = Double(
                contentRuns[index].lowerBound + contentRuns[index].upperBound
            ) / 2
            let rightCenter = Double(
                contentRuns[index + 1].lowerBound
                    + contentRuns[index + 1].upperBound
            ) / 2
            let boundary = Int(((leftCenter + rightCenter) / 2).rounded())
            boundaries.append(
                min(length, max(boundaries.last ?? 0, boundary))
            )
        }
        boundaries.append(length)

        return boundaries.indices.dropLast().compactMap { index in
            let lowerBound = boundaries[index]
            let upperBound = boundaries[index + 1]
            return lowerBound < upperBound ? lowerBound..<upperBound : nil
        }
    }

    private func foregroundCount(
        mask: [Bool],
        imageWidth: Int,
        rect: PixelRect
    ) -> Int {
        var count = 0
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) where mask[y * imageWidth + x] {
                count += 1
            }
        }
        return count
    }

}

private nonisolated struct PixelBuffer {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(image: CGImage) throws {
        let localWidth = image.width
        let localHeight = image.height
        width = localWidth
        height = localHeight
        let (pixelCount, pixelOverflow) = localWidth.multipliedReportingOverflow(
            by: localHeight
        )
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard localWidth > 0, localHeight > 0, !pixelOverflow, !byteOverflow else {
            throw SpriteSheetImportError.cannotProcessImage
        }
        var storage = [UInt8](repeating: 0, count: byteCount)
        let rendered = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: localWidth,
                height: localHeight,
                bitsPerComponent: 8,
                bytesPerRow: localWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.clear(
                CGRect(x: 0, y: 0, width: localWidth, height: localHeight)
            )
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: localWidth, height: localHeight)
            )
            return true
        }
        guard rendered else {
            throw SpriteSheetImportError.cannotProcessImage
        }
        pixels = storage
    }

    var hasTransparentCorner: Bool {
        cornerColors.contains { $0.alpha <= SpriteSheetFrameExtractor.alphaThreshold }
    }

    var suggestedBackgroundColor: SpriteSheetColor {
        let colors = cornerColors
        guard !colors.isEmpty else {
            return .clear
        }
        if let transparent = colors.first(where: {
            $0.alpha <= SpriteSheetFrameExtractor.alphaThreshold
        }) {
            return transparent
        }
        let selected = colors.min { left, right in
            totalDistance(from: left, to: colors) < totalDistance(from: right, to: colors)
        }
        return selected ?? colors[0]
    }

    func foregroundMask(
        backgroundColor: SpriteSheetColor,
        usesAlpha: Bool,
        tolerance: Int
    ) -> [Bool] {
        (0..<(width * height)).map { index in
            let color = color(atPixelIndex: index)
            if usesAlpha {
                return color.alpha > SpriteSheetFrameExtractor.alphaThreshold
            }
            return colorDistance(color, backgroundColor) > tolerance
        }
    }

    mutating func removeBackground(
        color backgroundColor: SpriteSheetColor,
        tolerance: Int
    ) {
        for pixelIndex in 0..<(width * height) {
            let color = color(atPixelIndex: pixelIndex)
            guard color.alpha > 0,
                  colorDistance(color, backgroundColor) <= tolerance else {
                continue
            }
            let offset = pixelIndex * 4
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }
    }

    func makeImage() throws -> CGImage {
        var storage = pixels
        guard let image = storage.withUnsafeMutableBytes({ bytes -> CGImage? in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return nil
            }
            return context.makeImage()
        }) else {
            throw SpriteSheetImportError.cannotProcessImage
        }
        return image
    }

    private var cornerColors: [SpriteSheetColor] {
        [
            color(x: 0, y: 0),
            color(x: max(0, width - 1), y: 0),
            color(x: 0, y: max(0, height - 1)),
            color(x: max(0, width - 1), y: max(0, height - 1))
        ]
    }

    private func color(x: Int, y: Int) -> SpriteSheetColor {
        color(atPixelIndex: y * width + x)
    }

    private func color(atPixelIndex index: Int) -> SpriteSheetColor {
        let offset = index * 4
        return SpriteSheetColor(
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }

    private func totalDistance(
        from color: SpriteSheetColor,
        to colors: [SpriteSheetColor]
    ) -> Int {
        colors.reduce(0) { $0 + colorDistance(color, $1) }
    }

    private func colorDistance(
        _ left: SpriteSheetColor,
        _ right: SpriteSheetColor
    ) -> Int {
        max(
            abs(Int(left.red) - Int(right.red)),
            abs(Int(left.green) - Int(right.green)),
            abs(Int(left.blue) - Int(right.blue))
        )
    }
}
