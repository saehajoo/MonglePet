import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PetPackageLoader {
    private static let supportedFileExtensions: Set<String> = ["json", "png", "webp"]
    private static let minimumFrameDurationMilliseconds = 16
    private static let maximumFrameDurationMilliseconds = 60_000

    let limits: PetPackageLimits
    private let fileManager: FileManager

    init(
        limits: PetPackageLimits = .standard,
        fileManager: FileManager = .default
    ) {
        self.limits = limits
        self.fileManager = fileManager
    }

    func loadPackage(at packageRootURL: URL) throws -> LoadedPetPackage {
        let suppliedRootURL = packageRootURL.standardizedFileURL
        try validatePackageRoot(suppliedRootURL)
        let rootURL = suppliedRootURL.resolvingSymlinksInPath().standardizedFileURL
        try validatePackageContents(rootURL)

        let manifestURL = rootURL.appendingPathComponent("pet.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PetPackageLoadingError.missingManifest
        }

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        } catch {
            throw PetPackageLoadingError.unreadableManifest
        }

        let manifest: PetPackageManifest
        do {
            manifest = try JSONDecoder().decode(PetPackageManifest.self, from: manifestData)
        } catch {
            throw PetPackageLoadingError.invalidManifest
        }

        return try validate(manifest: manifest, in: rootURL)
    }

    private func validatePackageRoot(_ rootURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw PetPackageLoadingError.invalidPackageRoot
        }

        do {
            let values = try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw PetPackageLoadingError.symbolicLink(rootURL.lastPathComponent)
            }
        } catch let error as PetPackageLoadingError {
            throw error
        } catch {
            throw PetPackageLoadingError.invalidPackageRoot
        }
    }

    private func validatePackageContents(_ rootURL: URL) throws {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw PetPackageLoadingError.invalidPackageRoot
        }

        var expandedByteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            let relativePath = relativePath(for: fileURL, rootURL: rootURL)
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: keys)
            } catch {
                throw PetPackageLoadingError.missingReferencedFile(relativePath)
            }

            if values.isSymbolicLink == true {
                throw PetPackageLoadingError.symbolicLink(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw PetPackageLoadingError.unsupportedFileType(relativePath)
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            guard Self.supportedFileExtensions.contains(fileExtension) else {
                throw PetPackageLoadingError.unsupportedFileType(relativePath)
            }

            expandedByteCount += Int64(values.fileSize ?? 0)
            guard expandedByteCount <= limits.maximumExpandedByteCount else {
                throw PetPackageLoadingError.packageTooLarge
            }
        }
        guard !enumerationFailed else {
            throw PetPackageLoadingError.invalidPackageRoot
        }
    }

    private func validate(
        manifest: PetPackageManifest,
        in rootURL: URL
    ) throws -> LoadedPetPackage {
        guard manifest.formatVersion == 1 else {
            throw PetPackageLoadingError.unsupportedFormatVersion(manifest.formatVersion)
        }

        try requireText(manifest.id, field: "id")
        try requireText(manifest.displayName, field: "displayName")
        try requireText(manifest.version, field: "version")
        try requireText(manifest.author, field: "author")
        try requireText(manifest.license, field: "license")
        try requireText(manifest.previewPath, field: "previewPath")
        let compatibility = try validateCompatibility(manifest.compatibility)

        guard !manifest.atlases.isEmpty else {
            throw PetPackageLoadingError.limitExceeded("atlas가 없습니다")
        }
        guard !manifest.motions.isEmpty else {
            throw PetPackageLoadingError.limitExceeded("모션이 없습니다")
        }
        guard manifest.motions.count <= limits.maximumMotionCount else {
            throw PetPackageLoadingError.limitExceeded("모션 수")
        }

        let previewURL = try resolveFile(
            relativePath: manifest.previewPath,
            in: rootURL
        )
        let previewImage = try inspectImage(
            at: previewURL,
            relativePath: manifest.previewPath,
            expectedFormat: .png,
            requiresAlpha: false
        )

        var decodedPixelCount = previewImage.pixelCount
        var atlasIDs = Set<String>()
        var atlasPaths = Set<String>()
        var atlasSizes: [String: PixelSize] = [:]
        var atlasResources: [PetAtlasResource] = []
        let normalizedPreviewPath = try normalizedRelativePath(manifest.previewPath).lowercased()

        for atlas in manifest.atlases {
            try requireText(atlas.id, field: "atlases.id")
            try requireText(atlas.path, field: "atlases.path")
            guard atlasIDs.insert(atlas.id).inserted else {
                throw PetPackageLoadingError.duplicateIdentifier(kind: "atlas", id: atlas.id)
            }

            let normalizedPath = try normalizedRelativePath(atlas.path)
            guard atlasPaths.insert(normalizedPath.lowercased()).inserted else {
                throw PetPackageLoadingError.duplicateResourcePath(atlas.path)
            }
            guard normalizedPath.lowercased() != normalizedPreviewPath else {
                throw PetPackageLoadingError.duplicateResourcePath(atlas.path)
            }

            guard
                atlas.pixelWidth > 0,
                atlas.pixelHeight > 0,
                atlas.pixelWidth <= limits.maximumImageDimension,
                atlas.pixelHeight <= limits.maximumImageDimension
            else {
                throw PetPackageLoadingError.limitExceeded("atlas 이미지 크기")
            }

            let format = try imageFormat(for: atlas.path)
            let atlasURL = try resolveFile(relativePath: atlas.path, in: rootURL)
            let inspectedImage = try inspectImage(
                at: atlasURL,
                relativePath: atlas.path,
                expectedFormat: format,
                requiresAlpha: true
            )
            let declaredSize = PixelSize(width: atlas.pixelWidth, height: atlas.pixelHeight)
            guard inspectedImage.pixelSize == declaredSize else {
                throw PetPackageLoadingError.imageDimensionsMismatch(atlas.path)
            }

            decodedPixelCount += inspectedImage.pixelCount
            guard decodedPixelCount <= limits.maximumDecodedPixelCount else {
                throw PetPackageLoadingError.limitExceeded("전체 디코딩 픽셀")
            }

            atlasSizes[atlas.id] = declaredSize
            atlasResources.append(
                PetAtlasResource(
                    id: atlas.id,
                    fileURL: atlasURL,
                    pixelSize: declaredSize,
                    format: format
                )
            )
        }

        let motions = try validateMotions(manifest.motions, atlasSizes: atlasSizes)
        let defaultMotionID: String
        if let declaredDefault = manifest.defaultMotion {
            try requireText(declaredDefault, field: "defaultMotion")
            defaultMotionID = declaredDefault
        } else {
            defaultMotionID = "idle"
        }
        guard motions.contains(where: { $0.id == defaultMotionID }) else {
            throw PetPackageLoadingError.missingDefaultMotion(defaultMotionID)
        }

        return LoadedPetPackage(
            packageRootURL: rootURL,
            metadata: PetPackageMetadata(
                id: manifest.id,
                displayName: manifest.displayName,
                version: manifest.version,
                author: manifest.author,
                license: manifest.license,
                description: manifest.description
            ),
            previewURL: previewURL,
            atlases: atlasResources,
            definition: PetDefinition(
                id: manifest.id,
                displayName: manifest.displayName,
                defaultMotionID: defaultMotionID,
                motions: motions
            ),
            compatibility: compatibility
        )
    }

    private func validateCompatibility(
        _ compatibility: PetPackageManifest.Compatibility?
    ) throws -> PetPackageCompatibility? {
        guard let compatibility else {
            return nil
        }

        let createdWithVersion = try parseCompatibilityVersion(
            compatibility.createdWithMonglePetVersion,
            field: "createdWithMonglePetVersion"
        )
        let minimumVersion = try parseCompatibilityVersion(
            compatibility.minimumMonglePetVersion,
            field: "minimumMonglePetVersion"
        )
        return PetPackageCompatibility(
            createdWithMonglePetVersion: createdWithVersion,
            minimumMonglePetVersion: minimumVersion
        )
    }

    private func parseCompatibilityVersion(
        _ value: String?,
        field: String
    ) throws -> SemanticVersion? {
        guard let value else {
            return nil
        }
        guard let version = SemanticVersion(value) else {
            throw PetPackageLoadingError.invalidCompatibilityVersion(
                field: field,
                value: value
            )
        }
        return version
    }

    private func validateMotions(
        _ manifests: [PetPackageManifest.Motion],
        atlasSizes: [String: PixelSize]
    ) throws -> [PetMotion] {
        var motionIDs = Set<String>()
        var totalFrameCount = 0
        var motions: [PetMotion] = []

        for motion in manifests {
            try requireText(motion.id, field: "motions.id")
            try requireText(motion.atlas, field: "motions.atlas")
            guard motionIDs.insert(motion.id).inserted else {
                throw PetPackageLoadingError.duplicateIdentifier(kind: "motion", id: motion.id)
            }
            guard let atlasSize = atlasSizes[motion.atlas] else {
                throw PetPackageLoadingError.missingAtlas(motion.atlas)
            }
            guard !motion.frames.isEmpty else {
                throw PetPackageLoadingError.invalidFrame(motionID: motion.id, index: 0)
            }

            totalFrameCount += motion.frames.count
            guard totalFrameCount <= limits.maximumFrameCount else {
                throw PetPackageLoadingError.limitExceeded("전체 프레임 수")
            }

            let frames = try motion.frames.enumerated().map { index, frame in
                let rect = PixelRect(
                    x: frame.x,
                    y: frame.y,
                    width: frame.width,
                    height: frame.height
                )
                guard
                    rect.isContained(in: atlasSize),
                    Self.minimumFrameDurationMilliseconds...Self.maximumFrameDurationMilliseconds ~= frame.durationMs
                else {
                    throw PetPackageLoadingError.invalidFrame(motionID: motion.id, index: index)
                }

                return MotionFrame(
                    atlasID: motion.atlas,
                    sourceRect: rect,
                    duration: .milliseconds(frame.durationMs)
                )
            }
            motions.append(PetMotion(id: motion.id, loops: motion.loop, frames: frames))
        }

        return motions
    }

    private func inspectImage(
        at fileURL: URL,
        relativePath: String,
        expectedFormat: PetPackageImageFormat,
        requiresAlpha: Bool
    ) throws -> InspectedImage {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw PetPackageLoadingError.invalidImage(relativePath)
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw PetPackageLoadingError.animatedImage(relativePath)
        }

        let expectedTypeIdentifier = switch expectedFormat {
        case .png: UTType.png.identifier
        case .webP: UTType.webP.identifier
        }
        guard let actualTypeIdentifier = CGImageSourceGetType(source) as String? else {
            throw PetPackageLoadingError.invalidImage(relativePath)
        }
        guard actualTypeIdentifier == expectedTypeIdentifier else {
            throw PetPackageLoadingError.imageFormatMismatch(relativePath)
        }

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0
        else {
            throw PetPackageLoadingError.invalidImage(relativePath)
        }
        guard
            width <= limits.maximumImageDimension,
            height <= limits.maximumImageDimension
        else {
            throw PetPackageLoadingError.limitExceeded("이미지 한 변")
        }

        if requiresAlpha {
            let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
            guard hasAlpha else {
                throw PetPackageLoadingError.imageMissingAlpha(relativePath)
            }
        }

        return InspectedImage(
            pixelSize: PixelSize(width: width, height: height),
            pixelCount: Int64(width) * Int64(height)
        )
    }

    private func imageFormat(for path: String) throws -> PetPackageImageFormat {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": .png
        case "webp": .webP
        default: throw PetPackageLoadingError.unsupportedImageFormat(path)
        }
    }

    private func resolveFile(relativePath: String, in rootURL: URL) throws -> URL {
        let normalizedPath = try normalizedRelativePath(relativePath)
        let fileURL = rootURL.appendingPathComponent(normalizedPath, isDirectory: false)
        var currentURL = rootURL

        for component in normalizedPath.split(separator: "/") {
            currentURL.appendPathComponent(String(component))
            guard fileManager.fileExists(atPath: currentURL.path) else {
                throw PetPackageLoadingError.missingReferencedFile(relativePath)
            }
            do {
                if try currentURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw PetPackageLoadingError.symbolicLink(relativePath)
                }
            } catch let error as PetPackageLoadingError {
                throw error
            } catch {
                throw PetPackageLoadingError.missingReferencedFile(relativePath)
            }
        }

        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw PetPackageLoadingError.missingReferencedFile(relativePath)
        }
        return fileURL
    }

    private func normalizedRelativePath(_ path: String) throws -> String {
        guard
            !path.isEmpty,
            !(path as NSString).isAbsolutePath,
            !path.contains("\\"),
            !path.contains("\0")
        else {
            throw PetPackageLoadingError.invalidRelativePath(path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PetPackageLoadingError.invalidRelativePath(path)
        }
        return components.joined(separator: "/")
    }

    private func requireText(_ text: String, field: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetPackageLoadingError.emptyRequiredField(field)
        }
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let fileComponents = fileURL.pathComponents
        guard
            let rootIndex = fileComponents.firstIndex(of: rootURL.lastPathComponent),
            rootIndex < fileComponents.index(before: fileComponents.endIndex)
        else {
            return fileURL.lastPathComponent
        }
        return fileComponents[fileComponents.index(after: rootIndex)...]
            .joined(separator: "/")
    }
}

private nonisolated struct InspectedImage {
    let pixelSize: PixelSize
    let pixelCount: Int64
}
