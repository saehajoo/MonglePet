import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct UserPetCreationRequest: Equatable, Sendable {
    let displayName: String
    let animationName: String
    let frameDurationMilliseconds: Int
    let loops: Bool
    let sourceURLs: [URL]
    let version: String
    let author: String
    let license: String
    let description: String?

    init(
        displayName: String,
        animationName: String,
        frameDurationMilliseconds: Int,
        loops: Bool,
        sourceURLs: [URL],
        version: String = "1.0.0",
        author: String = "MonglePet 사용자",
        license: String = "Private Use",
        description: String? = "MonglePet에서 사용자가 만든 펫입니다."
    ) {
        self.displayName = displayName
        self.animationName = animationName
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.loops = loops
        self.sourceURLs = sourceURLs
        self.version = version
        self.author = author
        self.license = license
        self.description = description
    }
}

nonisolated struct UserPetAnimationRequest: Equatable, Sendable {
    let animationName: String
    let frameDurationMilliseconds: Int
    let loops: Bool
    let sourceURLs: [URL]
}

nonisolated struct UserPetDetailsRequest: Equatable, Sendable {
    let displayName: String
    let version: String
    let author: String
    let license: String
    let description: String?
    let defaultMotionID: String
}

nonisolated struct UserPetAnimationDetailsRequest: Equatable, Sendable {
    let animationID: String
    let animationName: String
    let loops: Bool
}

nonisolated enum UserPetEditingError: Error, Equatable, Sendable {
    case invalidPetName
    case invalidVersion
    case invalidAuthor
    case invalidLicense
    case invalidAnimationName
    case invalidDefaultAnimation(String)
    case animationNotFound(String)
    case duplicateAnimationName(String)
    case cannotDeleteDefaultAnimation
    case cannotDeleteLastAnimation
    case importedPackageIsReadOnly
    case cannotWritePackage
}

extension UserPetEditingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPetName:
            "펫 이름을 입력해 주세요."
        case .invalidVersion:
            "펫 버전을 입력해 주세요."
        case .invalidAuthor:
            "제작자 이름을 입력해 주세요."
        case .invalidLicense:
            "라이선스를 입력해 주세요."
        case .invalidAnimationName:
            "펫 애니메이션 이름을 입력해 주세요."
        case let .invalidDefaultAnimation(name):
            "기본 애니메이션을 찾을 수 없습니다: \(name)"
        case let .animationNotFound(name):
            "펫 애니메이션을 찾을 수 없습니다: \(name)"
        case let .duplicateAnimationName(name):
            "같은 이름의 펫 애니메이션이 이미 있습니다: \(name)"
        case .cannotDeleteDefaultAnimation:
            "기본 애니메이션은 삭제할 수 없습니다. 먼저 다른 애니메이션을 기본으로 지정해 주세요."
        case .cannotDeleteLastAnimation:
            "마지막 남은 펫 애니메이션은 삭제할 수 없습니다."
        case .importedPackageIsReadOnly:
            "MonglePet에서 만든 펫만 직접 수정할 수 있습니다."
        case .cannotWritePackage:
            "사용자 펫 패키지를 저장하지 못했습니다."
        }
    }
}

nonisolated struct UserPetPackageEditor {
    static let markerFileName = "monglepet-editor.json"

    private let store: PetLibraryStore
    private let loader: PetPackageLoader
    private let animationAdapter: SimpleAnimationPetPackageAdapter
    private let writer: CompatiblePetPackageWriter
    private let fileManager: FileManager

    init(
        store: PetLibraryStore,
        loader: PetPackageLoader = PetPackageLoader(),
        animationAdapter: SimpleAnimationPetPackageAdapter = SimpleAnimationPetPackageAdapter(),
        writer: CompatiblePetPackageWriter = CompatiblePetPackageWriter(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.loader = loader
        self.animationAdapter = animationAdapter
        self.writer = writer
        self.fileManager = fileManager
    }

    func isEditable(_ installedPackage: InstalledPetPackage) -> Bool {
        let markerURL = installedPackage.rootURL.appendingPathComponent(
            Self.markerFileName,
            isDirectory: false
        )
        guard
            let data = try? Data(contentsOf: markerURL),
            let marker = try? JSONDecoder().decode(EditorMarker.self, from: data)
        else {
            return false
        }
        return marker.schemaVersion == 1
            && marker.packageID == installedPackage.package.metadata.id
    }

    func createPet(_ request: UserPetCreationRequest) throws -> InstalledPetPackage {
        let details = try validatedDetails(
            displayName: request.displayName,
            version: request.version,
            author: request.author,
            license: request.license,
            description: request.description
        )
        let animationName = try validatedAnimationName(request.animationName)
        let atlas = try animationAdapter.buildPNGSequenceAtlas(
            request.sourceURLs,
            frameDurationMilliseconds: request.frameDurationMilliseconds
        )
        let packageID = "kr.mapleroom.monglepet.user.\(UUID().uuidString.lowercased())"
        let manifest = PetPackageManifest(
            formatVersion: 1,
            id: packageID,
            displayName: details.displayName,
            version: details.version,
            author: details.author,
            license: details.license,
            description: details.description,
            previewPath: "preview.png",
            defaultMotion: animationName,
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
                    id: animationName,
                    atlas: "main",
                    loop: request.loops,
                    frames: atlas.frames
                )
            ]
        )

        return try withTemporaryPackage { packageURL in
            _ = try writer.writePNGAtlasPackage(
                manifest: manifest,
                atlasImage: atlas.atlasImage,
                previewImage: atlas.previewImage,
                to: packageURL
            )
            try writeMarker(packageID: packageID, to: packageURL)
            let validated = try loader.loadPackage(at: packageURL)
            return try store.install(
                packageAt: packageURL,
                validatedPackage: validated,
                mode: .rejectDuplicate
            )
        }
    }

    func addAnimation(
        _ request: UserPetAnimationRequest,
        to installedPackage: InstalledPetPackage
    ) throws -> InstalledPetPackage {
        guard isEditable(installedPackage) else {
            throw UserPetEditingError.importedPackageIsReadOnly
        }
        let animationName = try validatedAnimationName(request.animationName)
        guard !installedPackage.package.definition.motions.contains(where: {
            $0.id.localizedCaseInsensitiveCompare(animationName) == .orderedSame
        }) else {
            throw UserPetEditingError.duplicateAnimationName(animationName)
        }
        let atlas = try animationAdapter.buildPNGSequenceAtlas(
            request.sourceURLs,
            frameDurationMilliseconds: request.frameDurationMilliseconds
        )

        return try withTemporaryPackage { packageURL in
            do {
                try fileManager.copyItem(at: installedPackage.rootURL, to: packageURL)
            } catch {
                throw UserPetEditingError.cannotWritePackage
            }

            let currentManifest = try readManifest(from: packageURL)
            let resourceID = UUID().uuidString.lowercased()
            let atlasID = "user-\(resourceID)"
            let atlasPath = "assets/user-\(resourceID).png"
            try writePNG(
                atlas.atlasImage,
                to: packageURL.appendingPathComponent(atlasPath, isDirectory: false)
            )
            let updatedManifest = PetPackageManifest(
                formatVersion: currentManifest.formatVersion,
                id: currentManifest.id,
                displayName: currentManifest.displayName,
                version: currentManifest.version,
                author: currentManifest.author,
                license: currentManifest.license,
                description: currentManifest.description,
                previewPath: currentManifest.previewPath,
                defaultMotion: currentManifest.defaultMotion,
                atlases: currentManifest.atlases + [
                    PetPackageManifest.Atlas(
                        id: atlasID,
                        path: atlasPath,
                        pixelWidth: atlas.pixelSize.width,
                        pixelHeight: atlas.pixelSize.height
                    )
                ],
                motions: currentManifest.motions + [
                    PetPackageManifest.Motion(
                        id: animationName,
                        atlas: atlasID,
                        loop: request.loops,
                        frames: atlas.frames
                    )
                ]
            )
            try writeManifest(updatedManifest, to: packageURL)
            let validated = try loader.loadPackage(at: packageURL)
            return try store.install(
                packageAt: packageURL,
                validatedPackage: validated,
                mode: .replace(installationID: installedPackage.installationID)
            )
        }
    }

    func updateDetails(
        _ request: UserPetDetailsRequest,
        for installedPackage: InstalledPetPackage
    ) throws -> InstalledPetPackage {
        guard isEditable(installedPackage) else {
            throw UserPetEditingError.importedPackageIsReadOnly
        }
        let details = try validatedDetails(
            displayName: request.displayName,
            version: request.version,
            author: request.author,
            license: request.license,
            description: request.description
        )
        let defaultMotionID = request.defaultMotionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard installedPackage.package.definition.motion(id: defaultMotionID) != nil else {
            throw UserPetEditingError.invalidDefaultAnimation(defaultMotionID)
        }

        return try withTemporaryPackage { packageURL in
            do {
                try fileManager.copyItem(at: installedPackage.rootURL, to: packageURL)
            } catch {
                throw UserPetEditingError.cannotWritePackage
            }

            let currentManifest = try readManifest(from: packageURL)
            let updatedManifest = PetPackageManifest(
                formatVersion: currentManifest.formatVersion,
                id: currentManifest.id,
                displayName: details.displayName,
                version: details.version,
                author: details.author,
                license: details.license,
                description: details.description,
                previewPath: currentManifest.previewPath,
                defaultMotion: defaultMotionID,
                atlases: currentManifest.atlases,
                motions: currentManifest.motions
            )
            try writeManifest(updatedManifest, to: packageURL)
            let validated = try loader.loadPackage(at: packageURL)
            return try store.install(
                packageAt: packageURL,
                validatedPackage: validated,
                mode: .replace(installationID: installedPackage.installationID)
            )
        }
    }

    func updateAnimation(
        _ request: UserPetAnimationDetailsRequest,
        for installedPackage: InstalledPetPackage
    ) throws -> InstalledPetPackage {
        guard isEditable(installedPackage) else {
            throw UserPetEditingError.importedPackageIsReadOnly
        }
        guard installedPackage.package.definition.motion(id: request.animationID) != nil else {
            throw UserPetEditingError.animationNotFound(request.animationID)
        }
        let animationName = try validatedAnimationName(request.animationName)
        guard !installedPackage.package.definition.motions.contains(where: {
            $0.id != request.animationID
                && $0.id.localizedCaseInsensitiveCompare(animationName) == .orderedSame
        }) else {
            throw UserPetEditingError.duplicateAnimationName(animationName)
        }

        return try editingPackage(installedPackage) { currentManifest in
            let motions = currentManifest.motions.map { motion in
                guard motion.id == request.animationID else {
                    return motion
                }
                return PetPackageManifest.Motion(
                    id: animationName,
                    atlas: motion.atlas,
                    loop: request.loops,
                    frames: motion.frames
                )
            }
            return PetPackageManifest(
                formatVersion: currentManifest.formatVersion,
                id: currentManifest.id,
                displayName: currentManifest.displayName,
                version: currentManifest.version,
                author: currentManifest.author,
                license: currentManifest.license,
                description: currentManifest.description,
                previewPath: currentManifest.previewPath,
                defaultMotion: installedPackage.package.definition.defaultMotionID
                    == request.animationID
                    ? animationName
                    : currentManifest.defaultMotion,
                atlases: currentManifest.atlases,
                motions: motions
            )
        }
    }

    func removeAnimation(
        id animationID: String,
        from installedPackage: InstalledPetPackage
    ) throws -> InstalledPetPackage {
        guard isEditable(installedPackage) else {
            throw UserPetEditingError.importedPackageIsReadOnly
        }
        guard installedPackage.package.definition.motion(id: animationID) != nil else {
            throw UserPetEditingError.animationNotFound(animationID)
        }
        guard installedPackage.package.definition.motions.count > 1 else {
            throw UserPetEditingError.cannotDeleteLastAnimation
        }
        guard installedPackage.package.definition.defaultMotionID != animationID else {
            throw UserPetEditingError.cannotDeleteDefaultAnimation
        }

        return try editingPackage(installedPackage) { currentManifest in
            guard let removedMotion = currentManifest.motions.first(where: {
                $0.id == animationID
            }) else {
                throw UserPetEditingError.animationNotFound(animationID)
            }
            let remainingMotions = currentManifest.motions.filter { $0.id != animationID }
            let atlasIsStillUsed = remainingMotions.contains { $0.atlas == removedMotion.atlas }
            let remainingAtlases = atlasIsStillUsed
                ? currentManifest.atlases
                : currentManifest.atlases.filter { $0.id != removedMotion.atlas }
            return PetPackageManifest(
                formatVersion: currentManifest.formatVersion,
                id: currentManifest.id,
                displayName: currentManifest.displayName,
                version: currentManifest.version,
                author: currentManifest.author,
                license: currentManifest.license,
                description: currentManifest.description,
                previewPath: currentManifest.previewPath,
                defaultMotion: currentManifest.defaultMotion,
                atlases: remainingAtlases,
                motions: remainingMotions
            )
        } beforeValidation: { packageURL, originalManifest, updatedManifest in
            let removedAtlases = originalManifest.atlases.filter { original in
                !updatedManifest.atlases.contains { $0.id == original.id }
            }
            for atlas in removedAtlases {
                do {
                    try fileManager.removeItem(
                        at: packageURL.appendingPathComponent(atlas.path, isDirectory: false)
                    )
                } catch {
                    throw UserPetEditingError.cannotWritePackage
                }
            }
        }
    }

    private func validatedAnimationName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw UserPetEditingError.invalidAnimationName
        }
        return name
    }

    private func validatedDetails(
        displayName: String,
        version: String,
        author: String,
        license: String,
        description: String?
    ) throws -> (
        displayName: String,
        version: String,
        author: String,
        license: String,
        description: String?
    ) {
        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            throw UserPetEditingError.invalidPetName
        }
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw UserPetEditingError.invalidVersion
        }
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty else {
            throw UserPetEditingError.invalidAuthor
        }
        let license = license.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !license.isEmpty else {
            throw UserPetEditingError.invalidLicense
        }
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            displayName,
            version,
            author,
            license,
            description?.isEmpty == true ? nil : description
        )
    }

    private func editingPackage(
        _ installedPackage: InstalledPetPackage,
        updateManifest: (PetPackageManifest) throws -> PetPackageManifest,
        beforeValidation: (
            URL,
            PetPackageManifest,
            PetPackageManifest
        ) throws -> Void = { _, _, _ in }
    ) throws -> InstalledPetPackage {
        try withTemporaryPackage { packageURL in
            do {
                try fileManager.copyItem(at: installedPackage.rootURL, to: packageURL)
            } catch {
                throw UserPetEditingError.cannotWritePackage
            }
            let currentManifest = try readManifest(from: packageURL)
            let updatedManifest = try updateManifest(currentManifest)
            try writeManifest(updatedManifest, to: packageURL)
            try beforeValidation(packageURL, currentManifest, updatedManifest)
            let validated = try loader.loadPackage(at: packageURL)
            return try store.install(
                packageAt: packageURL,
                validatedPackage: validated,
                mode: .replace(installationID: installedPackage.installationID)
            )
        }
    }

    private func withTemporaryPackage<Result>(
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        let packageURL = fileManager.temporaryDirectory.appendingPathComponent(
            "MonglePet-UserPet-\(UUID().uuidString).monglepet",
            isDirectory: true
        )
        defer {
            if fileManager.fileExists(atPath: packageURL.path) {
                try? fileManager.removeItem(at: packageURL)
            }
        }
        return try operation(packageURL)
    }

    private func readManifest(from packageURL: URL) throws -> PetPackageManifest {
        do {
            let data = try Data(
                contentsOf: packageURL.appendingPathComponent("pet.json", isDirectory: false)
            )
            return try JSONDecoder().decode(PetPackageManifest.self, from: data)
        } catch {
            throw UserPetEditingError.cannotWritePackage
        }
    }

    private func writeManifest(
        _ manifest: PetPackageManifest,
        to packageURL: URL
    ) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(manifest)
            try data.write(
                to: packageURL.appendingPathComponent("pet.json", isDirectory: false),
                options: .atomic
            )
        } catch {
            throw UserPetEditingError.cannotWritePackage
        }
    }

    private func writeMarker(packageID: String, to packageURL: URL) throws {
        do {
            let data = try JSONEncoder().encode(
                EditorMarker(schemaVersion: 1, packageID: packageID)
            )
            try data.write(
                to: packageURL.appendingPathComponent(Self.markerFileName, isDirectory: false),
                options: .atomic
            )
        } catch {
            throw UserPetEditingError.cannotWritePackage
        }
    }

    private func writePNG(_ image: CGImage, to fileURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw UserPetEditingError.cannotWritePackage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UserPetEditingError.cannotWritePackage
        }
    }
}

private nonisolated struct EditorMarker: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let packageID: String
}
