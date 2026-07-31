import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum CodexSpriteVersion: Int, Equatable, Sendable {
    case legacyV1 = 1
    case v2 = 2

    var pixelSize: PixelSize {
        switch self {
        case .legacyV1: PixelSize(width: 1_536, height: 1_872)
        case .v2: PixelSize(width: 1_536, height: 2_288)
        }
    }
}

nonisolated enum CodexPetImportError: Error, Equatable, Sendable {
    case invalidSourceDirectory
    case missingManifest
    case unreadableManifest
    case invalidManifest
    case unsupportedSpriteVersion(Int)
    case invalidRelativePath(String)
    case symbolicLink(String)
    case missingSpritesheet(String)
    case unsupportedImageFormat(String)
    case imageFormatMismatch(String)
    case animatedImage
    case invalidImage
    case imageMissingAlpha
    case imageDimensionsMismatch(expected: PixelSize, actual: PixelSize)
    case emptyUsedCell(row: Int, column: Int)
    case opaqueUnusedCell(row: Int, column: Int)
}

nonisolated struct CodexPetImportMetadata: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String?

    init(id: String, displayName: String, description: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.description = description
    }
}

extension CodexPetImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSourceDirectory:
            "Codex 펫 디렉터리를 읽을 수 없습니다."
        case .missingManifest:
            "Codex 펫 디렉터리에 pet.json이 없습니다."
        case .unreadableManifest:
            "Codex pet.json을 읽을 수 없습니다."
        case .invalidManifest:
            "Codex pet.json 형식이 올바르지 않습니다."
        case let .unsupportedSpriteVersion(version):
            "지원하지 않는 Codex sprite 버전입니다: \(version)"
        case let .invalidRelativePath(path):
            "안전하지 않은 Codex spritesheet 경로입니다: \(path)"
        case let .symbolicLink(path):
            "Codex 펫 가져오기에 심볼릭 링크를 사용할 수 없습니다: \(path)"
        case let .missingSpritesheet(path):
            "Codex spritesheet를 찾을 수 없습니다: \(path)"
        case let .unsupportedImageFormat(path):
            "지원하지 않는 Codex spritesheet 형식입니다: \(path)"
        case let .imageFormatMismatch(path):
            "Codex spritesheet 확장자와 실제 이미지 형식이 다릅니다: \(path)"
        case .animatedImage:
            "Codex atlas는 정적 PNG 또는 WebP 한 장이어야 합니다."
        case .invalidImage:
            "Codex spritesheet를 디코딩할 수 없습니다."
        case .imageMissingAlpha:
            "Codex spritesheet에 알파 채널이 없습니다."
        case let .imageDimensionsMismatch(expected, actual):
            "Codex sprite 버전의 크기와 실제 이미지 크기가 다릅니다: \(expected.width)×\(expected.height), \(actual.width)×\(actual.height)"
        case let .emptyUsedCell(row, column):
            "Codex atlas의 사용 셀이 비어 있습니다: row \(row), column \(column)"
        case let .opaqueUnusedCell(row, column):
            "Codex atlas의 미사용 셀에 불투명 픽셀이 있습니다: row \(row), column \(column)"
        }
    }
}

nonisolated struct CodexPetPackageAdapter {
    static let cellSize = PixelSize(width: 192, height: 208)

    private static let standardRows: [CodexMotionRow] = [
        CodexMotionRow(id: "idle", durations: [280, 110, 110, 140, 140, 320]),
        CodexMotionRow(id: "running-right", durations: [120, 120, 120, 120, 120, 120, 120, 220]),
        CodexMotionRow(id: "running-left", durations: [120, 120, 120, 120, 120, 120, 120, 220]),
        CodexMotionRow(id: "waving", durations: [140, 140, 140, 280]),
        CodexMotionRow(id: "jumping", durations: [140, 140, 140, 140, 280]),
        CodexMotionRow(id: "failed", durations: [140, 140, 140, 140, 140, 140, 140, 240]),
        CodexMotionRow(id: "waiting", durations: [150, 150, 150, 150, 150, 260]),
        CodexMotionRow(id: "running", durations: [120, 120, 120, 120, 120, 220]),
        CodexMotionRow(id: "review", durations: [150, 150, 150, 150, 150, 280])
    ]
    private static let lookDirections = [
        "000", "022.5", "045", "067.5", "090", "112.5", "135", "157.5",
        "180", "202.5", "225", "247.5", "270", "292.5", "315", "337.5"
    ]

    private let writer: CompatiblePetPackageWriter
    private let fileManager: FileManager
    private let securityScopedAccess: SecurityScopedResourceAccess

    init(
        writer: CompatiblePetPackageWriter = CompatiblePetPackageWriter(),
        fileManager: FileManager = .default,
        securityScopedAccess: SecurityScopedResourceAccess = SecurityScopedResourceAccess()
    ) {
        self.writer = writer
        self.fileManager = fileManager
        self.securityScopedAccess = securityScopedAccess
    }

    func convert(
        sourceDirectoryURL: URL,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try securityScopedAccess.withAccess(to: sourceDirectoryURL) {
            try convertAccessedSource(
                sourceDirectoryURL: sourceDirectoryURL,
                to: destinationURL
            )
        }
    }

    func convertSpritesheet(
        at spritesheetURL: URL,
        confirmedVersion: CodexSpriteVersion,
        metadata: CodexPetImportMetadata,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try securityScopedAccess.withAccess(to: spritesheetURL) {
            guard !metadata.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !metadata.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CodexPetImportError.invalidManifest
            }
            let format = try imageFormat(for: spritesheetURL.lastPathComponent)
            let inspected = try inspectImage(at: spritesheetURL, format: format)
            guard inspected.pixelSize == confirmedVersion.pixelSize else {
                throw CodexPetImportError.imageDimensionsMismatch(
                    expected: confirmedVersion.pixelSize,
                    actual: inspected.pixelSize
                )
            }
            try validateCells(in: inspected.image, version: confirmedVersion)
            let manifest = CodexPetManifest(
                id: metadata.id,
                displayName: metadata.displayName,
                description: metadata.description,
                spriteVersionNumber: confirmedVersion.rawValue,
                spritesheetPath: spritesheetURL.lastPathComponent
            )
            return try writeConvertedPackage(
                codexManifest: manifest,
                version: confirmedVersion,
                spritesheetURL: spritesheetURL,
                format: format,
                image: inspected.image,
                destinationURL: destinationURL
            )
        }
    }

    private func convertAccessedSource(
        sourceDirectoryURL: URL,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        let rootURL = sourceDirectoryURL.standardizedFileURL
        try validateRoot(rootURL)
        let manifest = try loadManifest(from: rootURL)
        let versionNumber = manifest.spriteVersionNumber ?? 1
        guard let version = CodexSpriteVersion(rawValue: versionNumber) else {
            throw CodexPetImportError.unsupportedSpriteVersion(versionNumber)
        }
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexPetImportError.invalidManifest
        }

        let normalizedPath = try normalizedRelativePath(manifest.spritesheetPath)
        let spritesheetURL = try resolveFile(normalizedPath, in: rootURL)
        let format = try imageFormat(for: normalizedPath)
        let inspected = try inspectImage(at: spritesheetURL, format: format)
        guard inspected.pixelSize == version.pixelSize else {
            throw CodexPetImportError.imageDimensionsMismatch(
                expected: version.pixelSize,
                actual: inspected.pixelSize
            )
        }
        try validateCells(in: inspected.image, version: version)

        return try writeConvertedPackage(
            codexManifest: manifest,
            version: version,
            spritesheetURL: spritesheetURL,
            format: format,
            image: inspected.image,
            destinationURL: destinationURL
        )
    }

    private func writeConvertedPackage(
        codexManifest: CodexPetManifest,
        version: CodexSpriteVersion,
        spritesheetURL: URL,
        format: CodexImageFormat,
        image: CGImage,
        destinationURL: URL
    ) throws -> LoadedPetPackage {
        let atlasFilename = "spritesheet.\(format.rawValue)"
        let convertedManifest = makeManifest(
            codexManifest: codexManifest,
            version: version,
            atlasPath: "assets/\(atlasFilename)"
        )
        guard let previewImage = image.cropping(
            to: CGRect(x: 0, y: 0, width: Self.cellSize.width, height: Self.cellSize.height)
        ) else {
            throw CodexPetImportError.invalidImage
        }

        return try writer.writeCopiedAtlasPackage(
            manifest: convertedManifest,
            sourceAtlasURL: spritesheetURL,
            previewImage: previewImage,
            to: destinationURL
        )
    }

    private func validateRoot(_ rootURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CodexPetImportError.invalidSourceDirectory
        }
        do {
            if try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CodexPetImportError.symbolicLink(rootURL.lastPathComponent)
            }
        } catch let error as CodexPetImportError {
            throw error
        } catch {
            throw CodexPetImportError.invalidSourceDirectory
        }
    }

    private func loadManifest(from rootURL: URL) throws -> CodexPetManifest {
        let manifestURL = rootURL.appendingPathComponent("pet.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw CodexPetImportError.missingManifest
        }
        do {
            let values = try manifestURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw CodexPetImportError.symbolicLink("pet.json")
            }
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 1_048_576 else {
                throw CodexPetImportError.invalidManifest
            }
        } catch let error as CodexPetImportError {
            throw error
        } catch {
            throw CodexPetImportError.unreadableManifest
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw CodexPetImportError.unreadableManifest
        }
        do {
            return try JSONDecoder().decode(CodexPetManifest.self, from: data)
        } catch {
            throw CodexPetImportError.invalidManifest
        }
    }

    private func normalizedRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty,
              !(path as NSString).isAbsolutePath,
              !path.contains("\\"),
              !path.contains("\0") else {
            throw CodexPetImportError.invalidRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CodexPetImportError.invalidRelativePath(path)
        }
        return components.joined(separator: "/")
    }

    private func resolveFile(_ relativePath: String, in rootURL: URL) throws -> URL {
        var currentURL = rootURL
        for component in relativePath.split(separator: "/") {
            currentURL.appendPathComponent(String(component))
            guard fileManager.fileExists(atPath: currentURL.path) else {
                throw CodexPetImportError.missingSpritesheet(relativePath)
            }
            do {
                if try currentURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw CodexPetImportError.symbolicLink(relativePath)
                }
            } catch let error as CodexPetImportError {
                throw error
            } catch {
                throw CodexPetImportError.missingSpritesheet(relativePath)
            }
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: currentURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw CodexPetImportError.missingSpritesheet(relativePath)
        }
        return currentURL
    }

    private func imageFormat(for path: String) throws -> CodexImageFormat {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": .png
        case "webp": .webP
        default: throw CodexPetImportError.unsupportedImageFormat(path)
        }
    }

    private func inspectImage(at url: URL, format: CodexImageFormat) throws -> CodexInspectedImage {
        do {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw CodexPetImportError.symbolicLink(url.lastPathComponent)
            }
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 100 * 1_024 * 1_024 else {
                throw CodexPetImportError.invalidImage
            }
        } catch let error as CodexPetImportError {
            throw error
        } catch {
            throw CodexPetImportError.invalidImage
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CodexPetImportError.invalidImage
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw CodexPetImportError.animatedImage
        }
        let expectedType = switch format {
        case .png: UTType.png.identifier
        case .webP: UTType.webP.identifier
        }
        guard let actualType = CGImageSourceGetType(source) as String?, actualType == expectedType else {
            throw CodexPetImportError.imageFormatMismatch(url.lastPathComponent)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CodexPetImportError.invalidImage
        }
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
        guard hasAlpha else {
            throw CodexPetImportError.imageMissingAlpha
        }
        return CodexInspectedImage(
            image: image,
            pixelSize: PixelSize(width: width, height: height)
        )
    }

    private func validateCells(in image: CGImage, version: CodexSpriteVersion) throws {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drewImage = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else {
            throw CodexPetImportError.invalidImage
        }

        let usedColumns = Self.standardRows.map(\.durations.count)
            + (version == .v2 ? [8, 8] : [])
        for (row, usedColumnCount) in usedColumns.enumerated() {
            for column in 0..<8 {
                let hasVisiblePixel = cellHasVisiblePixel(
                    pixels: pixels,
                    bytesPerRow: bytesPerRow,
                    row: row,
                    column: column
                )
                if column < usedColumnCount, !hasVisiblePixel {
                    throw CodexPetImportError.emptyUsedCell(row: row, column: column)
                }
                if column >= usedColumnCount, hasVisiblePixel {
                    throw CodexPetImportError.opaqueUnusedCell(row: row, column: column)
                }
            }
        }
    }

    private func cellHasVisiblePixel(
        pixels: [UInt8],
        bytesPerRow: Int,
        row: Int,
        column: Int
    ) -> Bool {
        let startX = column * Self.cellSize.width
        let endX = startX + Self.cellSize.width
        let startY = row * Self.cellSize.height
        let endY = startY + Self.cellSize.height
        let imageHeight = pixels.count / bytesPerRow
        for y in startY..<endY {
            let rowOffset = (imageHeight - 1 - y) * bytesPerRow
            for x in startX..<endX where pixels[rowOffset + x * 4 + 3] != 0 {
                return true
            }
        }
        return false
    }

    private func makeManifest(
        codexManifest: CodexPetManifest,
        version: CodexSpriteVersion,
        atlasPath: String
    ) -> PetPackageManifest {
        var motions = Self.standardRows.enumerated().map { row, definition in
            PetPackageManifest.Motion(
                id: definition.id,
                atlas: "main",
                loop: true,
                frames: definition.durations.enumerated().map { column, duration in
                    PetPackageManifest.Frame(
                        x: column * Self.cellSize.width,
                        y: row * Self.cellSize.height,
                        width: Self.cellSize.width,
                        height: Self.cellSize.height,
                        durationMs: duration
                    )
                }
            )
        }
        if version == .v2 {
            motions.append(contentsOf: Self.lookDirections.enumerated().map { index, direction in
                let row = 9 + index / 8
                let column = index % 8
                return PetPackageManifest.Motion(
                    id: "look-\(direction)",
                    atlas: "main",
                    loop: false,
                    frames: [
                        PetPackageManifest.Frame(
                            x: column * Self.cellSize.width,
                            y: row * Self.cellSize.height,
                            width: Self.cellSize.width,
                            height: Self.cellSize.height,
                            durationMs: 1_000
                        )
                    ]
                )
            })
        }

        return PetPackageManifest(
            formatVersion: 1,
            id: codexManifest.id,
            displayName: codexManifest.displayName,
            version: "codex-\(version.rawValue)",
            author: "Unknown",
            license: "Unknown",
            description: codexManifest.description,
            previewPath: "preview.png",
            defaultMotion: "idle",
            atlases: [
                PetPackageManifest.Atlas(
                    id: "main",
                    path: atlasPath,
                    pixelWidth: version.pixelSize.width,
                    pixelHeight: version.pixelSize.height
                )
            ],
            motions: motions
        )
    }
}

private nonisolated struct CodexPetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String?
    let spriteVersionNumber: Int?
    let spritesheetPath: String
}

private nonisolated struct CodexMotionRow {
    let id: String
    let durations: [Int]
}

private nonisolated enum CodexImageFormat: String {
    case png
    case webP = "webp"
}

private nonisolated struct CodexInspectedImage {
    let image: CGImage
    let pixelSize: PixelSize
}
