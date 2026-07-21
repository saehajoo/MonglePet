import Foundation

nonisolated struct PetPackageManifest: Codable, Equatable, Sendable {
    let formatVersion: Int
    let id: String
    let displayName: String
    let version: String
    let author: String
    let license: String
    let description: String?
    let previewPath: String
    let defaultMotion: String?
    let atlases: [Atlas]
    let motions: [Motion]

    nonisolated struct Atlas: Codable, Equatable, Sendable {
        let id: String
        let path: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    nonisolated struct Motion: Codable, Equatable, Sendable {
        let id: String
        let atlas: String
        let loop: Bool
        let frames: [Frame]
    }

    nonisolated struct Frame: Codable, Equatable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let durationMs: Int
    }
}

nonisolated enum PetPackageImageFormat: String, Equatable, Sendable {
    case png
    case webP
}

nonisolated struct PetPackageMetadata: Equatable, Sendable {
    let id: String
    let displayName: String
    let version: String
    let author: String
    let license: String
    let description: String?
}

nonisolated struct PetAtlasResource: Equatable, Identifiable, Sendable {
    let id: String
    let fileURL: URL
    let pixelSize: PixelSize
    let format: PetPackageImageFormat
}

nonisolated struct LoadedPetPackage: Equatable, Sendable {
    let packageRootURL: URL
    let metadata: PetPackageMetadata
    let previewURL: URL
    let atlases: [PetAtlasResource]
    let definition: PetDefinition
}

nonisolated struct PetPackageLimits: Equatable, Sendable {
    static let standard = PetPackageLimits(
        maximumExpandedByteCount: 100 * 1_024 * 1_024,
        maximumImageDimension: 8_192,
        maximumDecodedPixelCount: 64 * 1_024 * 1_024,
        maximumMotionCount: 100,
        maximumFrameCount: 1_000
    )

    let maximumExpandedByteCount: Int64
    let maximumImageDimension: Int
    let maximumDecodedPixelCount: Int64
    let maximumMotionCount: Int
    let maximumFrameCount: Int
}

nonisolated enum PetPackageLoadingError: Error, Equatable, Sendable {
    case invalidPackageRoot
    case missingManifest
    case unreadableManifest
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case emptyRequiredField(String)
    case invalidRelativePath(String)
    case symbolicLink(String)
    case unsupportedFileType(String)
    case packageTooLarge
    case limitExceeded(String)
    case duplicateIdentifier(kind: String, id: String)
    case duplicateResourcePath(String)
    case missingReferencedFile(String)
    case unsupportedImageFormat(String)
    case imageFormatMismatch(String)
    case animatedImage(String)
    case invalidImage(String)
    case imageMissingAlpha(String)
    case imageDimensionsMismatch(String)
    case missingAtlas(String)
    case missingDefaultMotion(String)
    case invalidFrame(motionID: String, index: Int)
}

extension PetPackageLoadingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPackageRoot:
            "읽을 수 있는 펫 패키지 디렉터리가 아닙니다."
        case .missingManifest:
            "패키지 루트에 pet.json이 없습니다."
        case .unreadableManifest:
            "pet.json을 읽을 수 없습니다."
        case .invalidManifest:
            "pet.json 형식이 올바르지 않습니다."
        case let .unsupportedFormatVersion(version):
            "지원하지 않는 패키지 스키마 버전입니다: \(version)"
        case let .emptyRequiredField(field):
            "필수 필드가 비어 있습니다: \(field)"
        case let .invalidRelativePath(path):
            "안전하지 않은 패키지 상대 경로입니다: \(path)"
        case let .symbolicLink(path):
            "패키지에 심볼릭 링크를 사용할 수 없습니다: \(path)"
        case let .unsupportedFileType(path):
            "패키지에서 허용하지 않는 파일 형식입니다: \(path)"
        case .packageTooLarge:
            "패키지의 전체 파일 크기가 제한을 초과합니다."
        case let .limitExceeded(limit):
            "패키지 제한을 초과했습니다: \(limit)"
        case let .duplicateIdentifier(kind, id):
            "중복된 \(kind) ID입니다: \(id)"
        case let .duplicateResourcePath(path):
            "같은 리소스 경로가 중복 사용되었습니다: \(path)"
        case let .missingReferencedFile(path):
            "manifest가 참조한 파일이 없습니다: \(path)"
        case let .unsupportedImageFormat(path):
            "지원하지 않는 이미지 형식입니다: \(path)"
        case let .imageFormatMismatch(path):
            "이미지 확장자와 실제 형식이 다릅니다: \(path)"
        case let .animatedImage(path):
            "단일 프레임 atlas만 지원합니다: \(path)"
        case let .invalidImage(path):
            "이미지를 디코딩할 수 없습니다: \(path)"
        case let .imageMissingAlpha(path):
            "atlas 이미지에 알파 채널이 없습니다: \(path)"
        case let .imageDimensionsMismatch(path):
            "manifest 크기와 실제 이미지 크기가 다릅니다: \(path)"
        case let .missingAtlas(atlasID):
            "모션이 존재하지 않는 atlas를 참조합니다: \(atlasID)"
        case let .missingDefaultMotion(motionID):
            "기본 모션이 존재하지 않습니다: \(motionID)"
        case let .invalidFrame(motionID, index):
            "모션 \(motionID)의 \(index)번 프레임이 올바르지 않습니다."
        }
    }
}
