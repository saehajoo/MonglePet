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
    let recommendedProfile: RecommendedPetProfile?
    let recommendedProfileWithApplicationRules: RecommendedPetProfile?
    let recommendedProfileIssue: String?
    let applicationRulesIssue: String?
    let applicationBundleIdentifiers: [String]
    let applicationRuleCount: Int

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
        metadata: PetPackageMetadata,
        recommendedProfile: RecommendedPetProfile? = nil,
        recommendedProfileWithApplicationRules: RecommendedPetProfile? = nil,
        recommendedProfileIssue: String? = nil,
        applicationRulesIssue: String? = nil,
        applicationBundleIdentifiers: [String] = [],
        applicationRuleCount: Int = 0
    ) -> PetPackageShareReview {
        PetPackageShareReview(
            packageID: metadata.id,
            displayName: metadata.displayName,
            version: metadata.version,
            author: metadata.author,
            license: metadata.license,
            blockingReason: blockingReason(for: metadata.license),
            recommendedProfile: recommendedProfile,
            recommendedProfileWithApplicationRules:
                recommendedProfileWithApplicationRules,
            recommendedProfileIssue: recommendedProfileIssue,
            applicationRulesIssue: applicationRulesIssue,
            applicationBundleIdentifiers: applicationBundleIdentifiers,
            applicationRuleCount: applicationRuleCount
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

nonisolated struct PetPackageShareOptions: Equatable, Sendable {
    let includesRecommendedProfile: Bool
    let includesApplicationRules: Bool

    static let petOnly = PetPackageShareOptions(
        includesRecommendedProfile: false,
        includesApplicationRules: false
    )

    init(
        includesRecommendedProfile: Bool,
        includesApplicationRules: Bool
    ) {
        self.includesRecommendedProfile = includesRecommendedProfile
        self.includesApplicationRules =
            includesRecommendedProfile && includesApplicationRules
    }
}

nonisolated enum PetPackageSharingError: Error, Equatable, Sendable {
    case confirmationRequired
    case blocked(PetPackageSharingBlockReason)
    case reviewOutdated
    case recommendedProfileUnavailable
    case applicationRulesUnavailable
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
        case .recommendedProfileUnavailable:
            "현재 펫 설정은 공유 가능한 권장 설정으로 만들 수 없습니다."
        case .applicationRulesUnavailable:
            "현재 앱별 자동 규칙은 공유 가능한 형식으로 만들 수 없습니다."
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
        _ installedPackage: InstalledPetPackage,
        behaviorProfile: BehaviorProfile? = nil
    ) throws -> PetPackageShareReview {
        let currentPackage = try loadCurrentPackage(installedPackage)
        let profiles = reviewedProfiles(
            behaviorProfile,
            installationID: installedPackage.installationID,
            definition: currentPackage.definition
        )
        let applicationRules = behaviorProfile?.automaticRules.filter {
            guard case .application = $0.condition else {
                return false
            }
            return true
        } ?? []
        return PetPackageSharingPolicy.review(
            metadata: currentPackage.metadata,
            recommendedProfile: profiles.recommended,
            recommendedProfileWithApplicationRules:
                profiles.withApplicationRules,
            recommendedProfileIssue: profiles.recommendedIssue,
            applicationRulesIssue: profiles.applicationRulesIssue,
            applicationBundleIdentifiers: Array(
                Set(
                    applicationRules.compactMap {
                        guard case let .application(bundleIdentifier) = $0.condition else {
                            return nil
                        }
                        return bundleIdentifier
                    }
                )
            ).sorted(),
            applicationRuleCount: applicationRules.count
        )
    }

    @discardableResult
    func export(
        _ installedPackage: InstalledPetPackage,
        reviewed review: PetPackageShareReview,
        options: PetPackageShareOptions = .petOnly,
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

        let recommendedProfile: RecommendedPetProfile?
        if options.includesApplicationRules {
            guard let profile = review.recommendedProfileWithApplicationRules else {
                throw PetPackageSharingError.applicationRulesUnavailable
            }
            recommendedProfile = profile
        } else if options.includesRecommendedProfile {
            guard let profile = review.recommendedProfile else {
                throw PetPackageSharingError.recommendedProfileUnavailable
            }
            recommendedProfile = profile
        } else {
            recommendedProfile = nil
        }

        return try exporter.export(
            InstalledPetPackage(
                installationID: installedPackage.installationID,
                rootURL: installedPackage.rootURL,
                package: currentPackage
            ),
            recommendedProfile: recommendedProfile,
            to: destinationURL
        )
    }

    private func reviewedProfiles(
        _ behaviorProfile: BehaviorProfile?,
        installationID: UUID,
        definition: PetDefinition
    ) -> (
        recommended: RecommendedPetProfile?,
        withApplicationRules: RecommendedPetProfile?,
        recommendedIssue: String?,
        applicationRulesIssue: String?
    ) {
        guard
            let behaviorProfile,
            behaviorProfile.petKey == .installed(installationID)
        else {
            return (nil, nil, nil, nil)
        }

        let recommended = recommendedProfile(
            from: behaviorProfile,
            automaticRules: behaviorProfile.automaticRules.filter {
                guard case .application = $0.condition else {
                    return true
                }
                return false
            }
        )
        do {
            _ = try RecommendedPetProfileCodec.encode(
                recommended,
                for: definition
            )
        } catch {
            return (
                nil,
                nil,
                error.localizedDescription,
                nil
            )
        }

        let withApplicationRules = recommendedProfile(
            from: behaviorProfile,
            automaticRules: behaviorProfile.automaticRules
        )
        do {
            _ = try RecommendedPetProfileCodec.encode(
                withApplicationRules,
                for: definition
            )
            return (recommended, withApplicationRules, nil, nil)
        } catch {
            return (
                recommended,
                nil,
                nil,
                error.localizedDescription
            )
        }
    }

    private func recommendedProfile(
        from profile: BehaviorProfile,
        automaticRules: [AutomaticRule]
    ) -> RecommendedPetProfile {
        RecommendedPetProfile(
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: profile.sequences,
            automaticRules: automaticRules,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID
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
