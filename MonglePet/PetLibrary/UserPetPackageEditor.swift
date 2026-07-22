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
}

nonisolated struct UserPetAnimationRequest: Equatable, Sendable {
    let animationName: String
    let frameDurationMilliseconds: Int
    let loops: Bool
    let sourceURLs: [URL]
}

nonisolated enum UserPetEditingError: Error, Equatable, Sendable {
    case invalidPetName
    case invalidAnimationName
    case duplicateAnimationName(String)
    case importedPackageIsReadOnly
    case cannotWritePackage
}

extension UserPetEditingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPetName:
            "펫 이름을 입력해 주세요."
        case .invalidAnimationName:
            "펫 애니메이션 이름을 입력해 주세요."
        case let .duplicateAnimationName(name):
            "같은 이름의 펫 애니메이션이 이미 있습니다: \(name)"
        case .importedPackageIsReadOnly:
            "MonglePet에서 만든 펫만 애니메이션을 추가할 수 있습니다."
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
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            throw UserPetEditingError.invalidPetName
        }
        let animationName = try validatedAnimationName(request.animationName)
        let atlas = try animationAdapter.buildPNGSequenceAtlas(
            request.sourceURLs,
            frameDurationMilliseconds: request.frameDurationMilliseconds
        )
        let packageID = "kr.mapleroom.monglepet.user.\(UUID().uuidString.lowercased())"
        let manifest = PetPackageManifest(
            formatVersion: 1,
            id: packageID,
            displayName: displayName,
            version: "1.0.0",
            author: "MonglePet 사용자",
            license: "Private Use",
            description: "MonglePet에서 사용자가 만든 펫입니다.",
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

    private func validatedAnimationName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw UserPetEditingError.invalidAnimationName
        }
        return name
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
