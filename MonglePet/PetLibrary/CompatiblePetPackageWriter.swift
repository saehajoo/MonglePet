import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum CompatiblePetPackageWritingError: Error, Equatable, Sendable {
    case destinationAlreadyExists
    case cannotCreatePackage
    case cannotWriteImage
    case cannotWriteManifest
    case generatedPackageInvalid
}

extension CompatiblePetPackageWritingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .destinationAlreadyExists:
            "가져오기 대상 경로가 이미 존재합니다."
        case .cannotCreatePackage:
            "변환된 펫 패키지를 만들 수 없습니다."
        case .cannotWriteImage:
            "변환된 펫 이미지를 저장할 수 없습니다."
        case .cannotWriteManifest:
            "변환된 펫 manifest를 저장할 수 없습니다."
        case .generatedPackageInvalid:
            "변환된 펫 패키지의 최종 검증에 실패했습니다."
        }
    }
}

nonisolated struct CompatiblePetPackageWriter {
    private let loader: PetPackageLoader
    private let fileManager: FileManager
    private let currentAppVersion: SemanticVersion

    init(
        loader: PetPackageLoader = PetPackageLoader(),
        fileManager: FileManager = .default,
        currentAppVersion: SemanticVersion = MonglePetAppVersion.current.semanticVersion
    ) {
        self.loader = loader
        self.fileManager = fileManager
        self.currentAppVersion = currentAppVersion
    }

    func writeCopiedAtlasPackage(
        manifest: PetPackageManifest,
        sourceAtlasURL: URL,
        previewImage: CGImage,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try writePackage(manifest: manifest, previewImage: previewImage, to: destinationURL) {
            stagingURL in
            guard let atlasPath = manifest.atlases.first?.path else {
                throw CompatiblePetPackageWritingError.cannotCreatePackage
            }
            let atlasURL = stagingURL.appendingPathComponent(atlasPath, isDirectory: false)
            do {
                try fileManager.copyItem(at: sourceAtlasURL, to: atlasURL)
            } catch {
                throw CompatiblePetPackageWritingError.cannotCreatePackage
            }
        }
    }

    func writePNGAtlasPackage(
        manifest: PetPackageManifest,
        atlasImage: CGImage,
        previewImage: CGImage,
        to destinationURL: URL
    ) throws -> LoadedPetPackage {
        try writePackage(manifest: manifest, previewImage: previewImage, to: destinationURL) {
            stagingURL in
            guard let atlasPath = manifest.atlases.first?.path else {
                throw CompatiblePetPackageWritingError.cannotCreatePackage
            }
            try writePNG(
                atlasImage,
                to: stagingURL.appendingPathComponent(atlasPath, isDirectory: false)
            )
        }
    }

    private func writePackage(
        manifest: PetPackageManifest,
        previewImage: CGImage,
        to destinationURL: URL,
        writeAtlas: (URL) throws -> Void
    ) throws -> LoadedPetPackage {
        let destinationURL = destinationURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw CompatiblePetPackageWritingError.destinationAlreadyExists
        }

        let parentURL = destinationURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".importing-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        do {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: stagingURL.appendingPathComponent("assets", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            throw CompatiblePetPackageWritingError.cannotCreatePackage
        }

        try writePNG(
            previewImage,
            to: stagingURL.appendingPathComponent(manifest.previewPath, isDirectory: false)
        )
        try writeManifest(manifest, to: stagingURL)
        try writeAtlas(stagingURL)

        do {
            _ = try loader.loadPackage(at: stagingURL)
        } catch {
            throw CompatiblePetPackageWritingError.generatedPackageInvalid
        }

        do {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            return try loader.loadPackage(at: destinationURL)
        } catch let error as CompatiblePetPackageWritingError {
            throw error
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw CompatiblePetPackageWritingError.generatedPackageInvalid
        }
    }

    private func writeManifest(_ manifest: PetPackageManifest, to packageURL: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(
                manifest.recordingCompatibility(with: currentAppVersion)
            )
            try data.write(
                to: packageURL.appendingPathComponent("pet.json", isDirectory: false),
                options: .atomic
            )
        } catch {
            throw CompatiblePetPackageWritingError.cannotWriteManifest
        }
    }

    private func writePNG(_ image: CGImage, to fileURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CompatiblePetPackageWritingError.cannotWriteImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CompatiblePetPackageWritingError.cannotWriteImage
        }
    }
}
