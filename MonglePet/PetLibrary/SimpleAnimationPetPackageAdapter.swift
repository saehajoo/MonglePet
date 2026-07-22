import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct SimplePetImportMetadata: Equatable, Sendable {
    let id: String
    let displayName: String
    let version: String
    let author: String
    let license: String
    let description: String?

    init(
        id: String,
        displayName: String,
        version: String = "1.0.0",
        author: String = "Unknown",
        license: String = "Unknown",
        description: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.author = author
        self.license = license
        self.description = description
    }
}

nonisolated enum SimpleAnimationImportError: Error, Equatable, Sendable {
    case emptySequence
    case tooManyFrames
    case invalidMetadata
    case invalidFrameDuration
    case missingSource(String)
    case symbolicLink(String)
    case sourceFileTooLarge(String)
    case unsupportedImageFormat(String)
    case imageFormatMismatch(String)
    case expectedAnimatedImage
    case animatedWebPUnsupported
    case animatedSequenceMember(String)
    case invalidImage(String)
    case frameDimensionsExceeded
    case atlasDimensionsExceeded
    case decodedPixelLimitExceeded
    case cannotCreateAtlas
}

extension SimpleAnimationImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptySequence:
            "PNG 시퀀스에 이미지가 없습니다."
        case .tooManyFrames:
            "가져올 프레임 수가 제한을 초과했습니다."
        case .invalidMetadata:
            "가져올 펫의 ID 또는 표시 이름이 올바르지 않습니다."
        case .invalidFrameDuration:
            "PNG 시퀀스 프레임 시간이 올바르지 않습니다."
        case let .missingSource(path):
            "가져올 이미지 파일을 찾을 수 없습니다: \(path)"
        case let .symbolicLink(path):
            "가져오기에 심볼릭 링크를 사용할 수 없습니다: \(path)"
        case let .sourceFileTooLarge(path):
            "가져올 이미지 파일 크기가 제한을 초과했습니다: \(path)"
        case let .unsupportedImageFormat(path):
            "지원하지 않는 애니메이션 이미지 형식입니다: \(path)"
        case let .imageFormatMismatch(path):
            "이미지 확장자와 실제 형식이 다릅니다: \(path)"
        case .expectedAnimatedImage:
            "GIF 또는 APNG에 두 개 이상의 프레임이 필요합니다."
        case .animatedWebPUnsupported:
            "animated WebP 단일 파일은 현재 지원하지 않습니다."
        case let .animatedSequenceMember(path):
            "PNG 시퀀스에는 정적 PNG만 사용할 수 있습니다: \(path)"
        case let .invalidImage(path):
            "이미지를 디코딩할 수 없습니다: \(path)"
        case .frameDimensionsExceeded:
            "가져올 프레임 크기가 제한을 초과했습니다."
        case .atlasDimensionsExceeded:
            "변환된 atlas 크기가 제한을 초과합니다."
        case .decodedPixelLimitExceeded:
            "가져올 이미지의 전체 디코딩 픽셀 제한을 초과했습니다."
        case .cannotCreateAtlas:
            "가져온 프레임으로 atlas를 만들 수 없습니다."
        }
    }
}

nonisolated struct SimpleAnimationPetPackageAdapter {
    private static let minimumDurationMilliseconds = 16
    private static let maximumDurationMilliseconds = 60_000
    private static let fallbackDurationMilliseconds = 100
    private static let maximumColumns = 8

    private let limits: PetPackageLimits
    private let writer: CompatiblePetPackageWriter
    private let fileManager: FileManager
    private let securityScopedAccess: SecurityScopedResourceAccess

    init(
        limits: PetPackageLimits = .standard,
        writer: CompatiblePetPackageWriter = CompatiblePetPackageWriter(),
        fileManager: FileManager = .default,
        securityScopedAccess: SecurityScopedResourceAccess = SecurityScopedResourceAccess()
    ) {
        self.limits = limits
        self.writer = writer
        self.fileManager = fileManager
        self.securityScopedAccess = securityScopedAccess
    }

    func convertAnimatedImage(
        at sourceURL: URL,
        metadata: SimplePetImportMetadata,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try securityScopedAccess.withAccess(to: sourceURL) {
            try validate(metadata: metadata)
            let frames = try loadAnimatedFrames(at: sourceURL)
            return try write(frames: frames, metadata: metadata, to: destinationURL)
        }
    }

    func convertPNGSequence(
        _ sourceURLs: [URL],
        frameDurationMilliseconds: Int = 120,
        metadata: SimplePetImportMetadata,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try validate(metadata: metadata)
        let atlas = try buildPNGSequenceAtlas(
            sourceURLs,
            frameDurationMilliseconds: frameDurationMilliseconds
        )
        return try write(atlas: atlas, metadata: metadata, to: destinationURL)
    }

    func buildPNGSequenceAtlas(
        _ sourceURLs: [URL],
        frameDurationMilliseconds: Int = 120
    ) throws -> PNGSequenceAtlas {
        guard Self.minimumDurationMilliseconds...Self.maximumDurationMilliseconds
            ~= frameDurationMilliseconds else {
            throw SimpleAnimationImportError.invalidFrameDuration
        }
        guard !sourceURLs.isEmpty else {
            throw SimpleAnimationImportError.emptySequence
        }
        guard sourceURLs.count <= limits.maximumFrameCount else {
            throw SimpleAnimationImportError.tooManyFrames
        }

        var decodedPixelCount: Int64 = 0
        let frames = try sourceURLs.map { sourceURL in
            try securityScopedAccess.withAccess(to: sourceURL) {
                let image = try loadStaticPNG(at: sourceURL)
                decodedPixelCount += Int64(image.width) * Int64(image.height)
                guard decodedPixelCount <= limits.maximumDecodedPixelCount else {
                    throw SimpleAnimationImportError.decodedPixelLimitExceeded
                }
                return SimpleAnimationFrame(
                    image: image,
                    durationMilliseconds: frameDurationMilliseconds
                )
            }
        }
        return try makeAtlas(frames: frames)
    }

    private func validate(metadata: SimplePetImportMetadata) throws {
        let id = metadata.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = metadata.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = metadata.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = metadata.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let license = metadata.license.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !displayName.isEmpty, !version.isEmpty, !author.isEmpty, !license.isEmpty else {
            throw SimpleAnimationImportError.invalidMetadata
        }
    }

    private func loadAnimatedFrames(at sourceURL: URL) throws -> [SimpleAnimationFrame] {
        try validateSourceFile(sourceURL)
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard fileExtension == "gif" || fileExtension == "png" || fileExtension == "webp" else {
            throw SimpleAnimationImportError.unsupportedImageFormat(sourceURL.lastPathComponent)
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let actualType = CGImageSourceGetType(source) as String? else {
            throw SimpleAnimationImportError.invalidImage(sourceURL.lastPathComponent)
        }
        if actualType == UTType.webP.identifier {
            throw SimpleAnimationImportError.animatedWebPUnsupported
        }
        let expectedType = fileExtension == "gif" ? UTType.gif.identifier : UTType.png.identifier
        guard actualType == expectedType else {
            throw SimpleAnimationImportError.imageFormatMismatch(sourceURL.lastPathComponent)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            throw SimpleAnimationImportError.expectedAnimatedImage
        }
        guard frameCount <= limits.maximumFrameCount else {
            throw SimpleAnimationImportError.tooManyFrames
        }

        var decodedPixelCount: Int64 = 0
        let decodedFrames = try (0..<frameCount).map { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw SimpleAnimationImportError.invalidImage(sourceURL.lastPathComponent)
            }
            try validateFrameDimensions(image)
            decodedPixelCount += Int64(image.width) * Int64(image.height)
            guard decodedPixelCount <= limits.maximumDecodedPixelCount else {
                throw SimpleAnimationImportError.decodedPixelLimitExceeded
            }
            return SimpleAnimationFrame(
                image: image,
                durationMilliseconds: frameDuration(
                    source: source,
                    index: index,
                    isGIF: actualType == UTType.gif.identifier
                )
            )
        }
        return try compositeAnimationFrames(
            decodedFrames,
            source: source,
            isGIF: actualType == UTType.gif.identifier
        )
    }

    private func loadStaticPNG(at sourceURL: URL) throws -> CGImage {
        try validateSourceFile(sourceURL)
        guard sourceURL.pathExtension.lowercased() == "png" else {
            throw SimpleAnimationImportError.unsupportedImageFormat(sourceURL.lastPathComponent)
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let actualType = CGImageSourceGetType(source) as String? else {
            throw SimpleAnimationImportError.invalidImage(sourceURL.lastPathComponent)
        }
        guard actualType == UTType.png.identifier else {
            throw SimpleAnimationImportError.imageFormatMismatch(sourceURL.lastPathComponent)
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw SimpleAnimationImportError.animatedSequenceMember(sourceURL.lastPathComponent)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SimpleAnimationImportError.invalidImage(sourceURL.lastPathComponent)
        }
        try validateFrameDimensions(image)
        return image
    }

    private func validateFrameDimensions(_ image: CGImage) throws {
        guard image.width > 0,
              image.height > 0,
              image.width <= limits.maximumImageDimension,
              image.height <= limits.maximumImageDimension else {
            throw SimpleAnimationImportError.frameDimensionsExceeded
        }
    }

    private func validateSourceFile(_ sourceURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw SimpleAnimationImportError.missingSource(sourceURL.path)
        }
        do {
            let values = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw SimpleAnimationImportError.symbolicLink(sourceURL.lastPathComponent)
            }
            guard values.isRegularFile == true else {
                throw SimpleAnimationImportError.missingSource(sourceURL.path)
            }
            guard Int64(values.fileSize ?? 0) <= limits.maximumExpandedByteCount else {
                throw SimpleAnimationImportError.sourceFileTooLarge(sourceURL.lastPathComponent)
            }
        } catch let error as SimpleAnimationImportError {
            throw error
        } catch {
            throw SimpleAnimationImportError.missingSource(sourceURL.path)
        }
    }

    private func frameDuration(
        source: CGImageSource,
        index: Int,
        isGIF: Bool
    ) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any] else {
            return Self.fallbackDurationMilliseconds
        }
        let dictionaryKey = isGIF ? kCGImagePropertyGIFDictionary : kCGImagePropertyPNGDictionary
        guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else {
            return Self.fallbackDurationMilliseconds
        }
        let unclampedKey = isGIF
            ? kCGImagePropertyGIFUnclampedDelayTime
            : kCGImagePropertyAPNGUnclampedDelayTime
        let delayKey = isGIF ? kCGImagePropertyGIFDelayTime : kCGImagePropertyAPNGDelayTime
        let seconds = (dictionary[unclampedKey] as? NSNumber)?.doubleValue
            ?? (dictionary[delayKey] as? NSNumber)?.doubleValue
        guard let seconds, seconds.isFinite else {
            return Self.fallbackDurationMilliseconds
        }
        let milliseconds = Int((seconds * 1_000).rounded())
        guard Self.minimumDurationMilliseconds...Self.maximumDurationMilliseconds ~= milliseconds else {
            return Self.fallbackDurationMilliseconds
        }
        return milliseconds
    }

    private func compositeAnimationFrames(
        _ frames: [SimpleAnimationFrame],
        source: CGImageSource,
        isGIF: Bool
    ) throws -> [SimpleAnimationFrame] {
        guard let firstFrame = frames.first else {
            throw SimpleAnimationImportError.emptySequence
        }
        let width = firstFrame.image.width
        let height = firstFrame.image.height
        guard frames.allSatisfy({ $0.image.width == width && $0.image.height == height }) else {
            throw SimpleAnimationImportError.invalidImage("animation frame canvas")
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SimpleAnimationImportError.cannotCreateAtlas
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let frameInfo = animationFrameInfo(source: source, isGIF: isGIF)
        var compositedFrames: [SimpleAnimationFrame] = []
        for (index, frame) in frames.enumerated() {
            let canvasBeforeFrame = context.makeImage()
            let info = index < frameInfo.count ? frameInfo[index] : [:]
            let blendMode = animationBlendMode(info: info, isGIF: isGIF)
            let frameRect = animationFrameRect(info: info, width: width, height: height)
            context.saveGState()
            context.clip(to: frameRect)
            context.setBlendMode(blendMode)
            context.draw(
                frame.image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            context.restoreGState()
            guard let compositedImage = context.makeImage() else {
                throw SimpleAnimationImportError.cannotCreateAtlas
            }
            compositedFrames.append(
                SimpleAnimationFrame(
                    image: compositedImage,
                    durationMilliseconds: frame.durationMilliseconds
                )
            )

            switch animationDisposal(info: info, isGIF: isGIF) {
            case .keep:
                break
            case .restoreBackground:
                context.clear(frameRect)
            case .restorePrevious:
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                if let canvasBeforeFrame {
                    context.draw(
                        canvasBeforeFrame,
                        in: CGRect(x: 0, y: 0, width: width, height: height)
                    )
                }
            }
        }
        return compositedFrames
    }

    private func animationFrameRect(
        info: [CFString: Any],
        width: Int,
        height: Int
    ) -> CGRect {
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        if let dictionary = info["FrameRect" as CFString] as? [CFString: Any],
           let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
           !rect.isEmpty {
            return topLeftRectToCanvas(rect, canvasHeight: height).intersection(fullRect)
        }

        let x = number(in: info, keys: ["XOffset", "X", "Left"])
        let y = number(in: info, keys: ["YOffset", "Y", "Top"])
        let frameWidth = number(in: info, keys: ["Width", "FrameWidth"])
        let frameHeight = number(in: info, keys: ["Height", "FrameHeight"])
        guard let x, let y, let frameWidth, let frameHeight,
              frameWidth > 0, frameHeight > 0 else {
            return fullRect
        }
        let rect = CGRect(x: x, y: y, width: frameWidth, height: frameHeight)
        let converted = topLeftRectToCanvas(rect, canvasHeight: height).intersection(fullRect)
        return converted.isEmpty ? fullRect : converted
    }

    private func topLeftRectToCanvas(_ rect: CGRect, canvasHeight: Int) -> CGRect {
        CGRect(
            x: rect.minX,
            y: CGFloat(canvasHeight) - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func number(in info: [CFString: Any], keys: [String]) -> CGFloat? {
        for key in keys {
            if let number = info[key as CFString] as? NSNumber {
                return CGFloat(number.doubleValue)
            }
        }
        return nil
    }

    private func animationFrameInfo(
        source: CGImageSource,
        isGIF: Bool
    ) -> [[CFString: Any]] {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] else {
            return []
        }
        let dictionaryKey = isGIF ? kCGImagePropertyGIFDictionary : kCGImagePropertyPNGDictionary
        let frameInfoKey = isGIF ? kCGImagePropertyGIFFrameInfoArray : kCGImagePropertyAPNGFrameInfoArray
        guard let dictionary = properties[dictionaryKey] as? [CFString: Any],
              let frameInfo = dictionary[frameInfoKey] as? [[CFString: Any]] else {
            return []
        }
        return frameInfo
    }

    private func animationBlendMode(info: [CFString: Any], isGIF: Bool) -> CGBlendMode {
        guard !isGIF else { return .normal }
        let blendOperation = (info["BlendOp" as CFString] as? NSNumber)?.intValue
            ?? (info["BlendOperation" as CFString] as? NSNumber)?.intValue
            ?? 0
        return blendOperation == 0 ? .copy : .normal
    }

    private func animationDisposal(
        info: [CFString: Any],
        isGIF: Bool
    ) -> AnimationFrameDisposal {
        let method = (info["DisposalMethod" as CFString] as? NSNumber)?.intValue
            ?? (info["DisposeOp" as CFString] as? NSNumber)?.intValue
            ?? 0
        if isGIF {
            return switch method {
            case 2: .restoreBackground
            case 3: .restorePrevious
            default: .keep
            }
        }
        return switch method {
        case 1: .restoreBackground
        case 2: .restorePrevious
        default: .keep
        }
    }

    private func write(
        frames: [SimpleAnimationFrame],
        metadata: SimplePetImportMetadata,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try write(
            atlas: makeAtlas(frames: frames),
            metadata: metadata,
            to: destinationURL
        )
    }

    private func makeAtlas(frames: [SimpleAnimationFrame]) throws -> PNGSequenceAtlas {
        guard !frames.isEmpty else {
            throw SimpleAnimationImportError.emptySequence
        }
        let cellWidth = frames.map(\.image.width).max() ?? 0
        let cellHeight = frames.map(\.image.height).max() ?? 0
        let columns = min(Self.maximumColumns, frames.count)
        let rows = (frames.count + columns - 1) / columns
        let atlasWidth = cellWidth * columns
        let atlasHeight = cellHeight * rows
        guard atlasWidth <= limits.maximumImageDimension,
              atlasHeight <= limits.maximumImageDimension else {
            throw SimpleAnimationImportError.atlasDimensionsExceeded
        }
        guard Int64(atlasWidth) * Int64(atlasHeight) <= limits.maximumDecodedPixelCount else {
            throw SimpleAnimationImportError.decodedPixelLimitExceeded
        }
        guard let context = CGContext(
            data: nil,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SimpleAnimationImportError.cannotCreateAtlas
        }
        context.clear(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

        var manifestFrames: [PetPackageManifest.Frame] = []
        for (index, frame) in frames.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = column * cellWidth
            let topY = row * cellHeight
            let drawX = x + (cellWidth - frame.image.width) / 2
            let drawY = atlasHeight - (topY + cellHeight) + (cellHeight - frame.image.height) / 2
            context.draw(
                frame.image,
                in: CGRect(
                    x: drawX,
                    y: drawY,
                    width: frame.image.width,
                    height: frame.image.height
                )
            )
            manifestFrames.append(
                PetPackageManifest.Frame(
                    x: x,
                    y: topY,
                    width: cellWidth,
                    height: cellHeight,
                    durationMs: frame.durationMilliseconds
                )
            )
        }
        guard let atlasImage = context.makeImage() else {
            throw SimpleAnimationImportError.cannotCreateAtlas
        }

        return PNGSequenceAtlas(
            atlasImage: atlasImage,
            previewImage: frames[0].image,
            pixelSize: PixelSize(width: atlasWidth, height: atlasHeight),
            frames: manifestFrames
        )
    }

    private func write(
        atlas: PNGSequenceAtlas,
        metadata: SimplePetImportMetadata,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        let manifest = PetPackageManifest(
            formatVersion: 1,
            id: metadata.id,
            displayName: metadata.displayName,
            version: metadata.version,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            previewPath: "preview.png",
            defaultMotion: "idle",
            atlases: [
                PetPackageManifest.Atlas(
                    id: "main",
                    path: "assets/spritesheet.png",
                    pixelWidth: atlas.pixelSize.width,
                    pixelHeight: atlas.pixelSize.height
                )
            ],
            motions: [
                PetPackageManifest.Motion(
                    id: "idle",
                    atlas: "main",
                    loop: true,
                    frames: atlas.frames
                )
            ]
        )
        return try writer.writePNGAtlasPackage(
            manifest: manifest,
            atlasImage: atlas.atlasImage,
            previewImage: atlas.previewImage,
            to: destinationURL
        )
    }
}

nonisolated struct PNGSequenceAtlas: @unchecked Sendable {
    let atlasImage: CGImage
    let previewImage: CGImage
    let pixelSize: PixelSize
    let frames: [PetPackageManifest.Frame]
}

private nonisolated struct SimpleAnimationFrame {
    let image: CGImage
    let durationMilliseconds: Int
}

private nonisolated enum AnimationFrameDisposal {
    case keep
    case restoreBackground
    case restorePrevious
}
