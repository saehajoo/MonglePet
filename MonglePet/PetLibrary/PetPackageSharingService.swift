import Foundation

nonisolated enum PetPackageSharingBlockReason: Equatable, Sendable {
    case privateOrPersonalUse
    case allRightsReserved
    case unknownLicense

    var message: String {
        switch self {
        case .privateOrPersonalUse:
            "개인 용도로 제한된 라이선스는 다른 사용자에게 공유할 수 없습니다."
        case .allRightsReserved:
            "All Rights Reserved는 재배포 권한을 제공하지 않으므로 공유할 수 없습니다."
        case .unknownLicense:
            "공유 권한을 확인할 수 없는 라이선스입니다. 라이선스를 먼저 수정해 주세요."
        }
    }
}

nonisolated struct PetPackageShareReview: Equatable, Identifiable, Sendable {
    let packageID: String
    let displayName: String
    let version: String
    let author: String
    let license: String
    let blockingReason: PetPackageSharingBlockReason?

    var id: String {
        packageID
    }

    var canExport: Bool {
        blockingReason == nil
    }

    var suggestedFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        let components = displayName.components(separatedBy: invalidCharacters)
        let sanitizedName = components
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(sanitizedName.isEmpty ? "MonglePet" : sanitizedName).monglepet"
    }

    func matches(_ metadata: PetPackageMetadata) -> Bool {
        packageID == metadata.id
            && displayName == metadata.displayName
            && version == metadata.version
            && author == metadata.author
            && license == metadata.license
    }
}

nonisolated enum PetPackageSharingPolicy {
    static func review(
        metadata: PetPackageMetadata
    ) -> PetPackageShareReview {
        PetPackageShareReview(
            packageID: metadata.id,
            displayName: metadata.displayName,
            version: metadata.version,
            author: metadata.author,
            license: metadata.license,
            blockingReason: blockingReason(for: metadata.license)
        )
    }

    private static func blockingReason(
        for license: String
    ) -> PetPackageSharingBlockReason? {
        let normalized = normalizedLicense(license)
        switch normalized {
        case "private use", "private use only", "personal use", "personal use only":
            return .privateOrPersonalUse
        case "all rights reserved":
            return .allRightsReserved
        case "unknown", "unspecified", "no license", "none":
            return .unknownLicense
        default:
            return nil
        }
    }

    private static func normalizedLicense(_ license: String) -> String {
        license
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

nonisolated enum PetPackageSharingError: Error, Equatable, Sendable {
    case confirmationRequired
    case blocked(PetPackageSharingBlockReason)
    case reviewOutdated
}

extension PetPackageSharingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "제작자와 라이선스 정보를 확인하고 공유 권한을 확인해 주세요."
        case let .blocked(reason):
            reason.message
        case .reviewOutdated:
            "펫 정보가 변경되었습니다. 최신 제작자와 라이선스 정보를 다시 확인해 주세요."
        }
    }
}

nonisolated struct PetPackageSharingService {
    private let loader: PetPackageLoader
    private let exporter: PetPackageExporter

    init(
        loader: PetPackageLoader = PetPackageLoader(),
        exporter: PetPackageExporter = PetPackageExporter()
    ) {
        self.loader = loader
        self.exporter = exporter
    }

    func review(
        _ installedPackage: InstalledPetPackage
    ) throws -> PetPackageShareReview {
        let currentPackage = try loadCurrentPackage(installedPackage)
        return PetPackageSharingPolicy.review(metadata: currentPackage.metadata)
    }

    @discardableResult
    func export(
        _ installedPackage: InstalledPetPackage,
        reviewed review: PetPackageShareReview,
        isConfirmed: Bool,
        to destinationURL: URL
    ) throws -> URL {
        let currentPackage = try loadCurrentPackage(installedPackage)
        guard review.matches(currentPackage.metadata) else {
            throw PetPackageSharingError.reviewOutdated
        }
        if let blockingReason = review.blockingReason {
            throw PetPackageSharingError.blocked(blockingReason)
        }
        guard isConfirmed else {
            throw PetPackageSharingError.confirmationRequired
        }

        return try exporter.export(
            InstalledPetPackage(
                installationID: installedPackage.installationID,
                rootURL: installedPackage.rootURL,
                package: currentPackage
            ),
            to: destinationURL
        )
    }

    private func loadCurrentPackage(
        _ installedPackage: InstalledPetPackage
    ) throws -> LoadedPetPackage {
        let currentPackage: LoadedPetPackage
        do {
            currentPackage = try loader.loadPackage(at: installedPackage.rootURL)
        } catch let error as PetPackageLoadingError {
            throw PetPackageExportError.packageValidationFailed(error)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
        guard
            currentPackage.metadata == installedPackage.package.metadata,
            currentPackage.definition == installedPackage.package.definition
        else {
            throw PetPackageSharingError.reviewOutdated
        }
        return currentPackage
    }
}
