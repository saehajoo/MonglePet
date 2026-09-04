import Foundation

nonisolated struct PetPackageShareReview: Equatable, Identifiable, Sendable {
    let packageID: String
    let displayName: String
    let version: String
    let author: String
    let recommendedProfile: RecommendedPetProfile?
    let recommendedProfileWithApplicationRules: RecommendedPetProfile?
    let recommendedProfileIssue: String?
    let applicationRulesIssue: String?
    let applicationBundleIdentifiers: [String]
    let applicationRuleCount: Int

    var id: String {
        packageID
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
            recommendedProfile: recommendedProfile,
            recommendedProfileWithApplicationRules:
                recommendedProfileWithApplicationRules,
            recommendedProfileIssue: recommendedProfileIssue,
            applicationRulesIssue: applicationRulesIssue,
            applicationBundleIdentifiers: applicationBundleIdentifiers,
            applicationRuleCount: applicationRuleCount
        )
    }

}

nonisolated struct PetPackageShareOptions: Equatable, Sendable {
    let includesApplicationRules: Bool

    static let standard = PetPackageShareOptions(
        includesApplicationRules: false
    )

    init(includesApplicationRules: Bool) {
        self.includesApplicationRules = includesApplicationRules
    }
}

nonisolated enum PetPackageSharingError: Error, Equatable, Sendable {
    case confirmationRequired
    case reviewOutdated
    case recommendedProfileUnavailable
    case applicationRulesUnavailable
}

extension PetPackageSharingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "펫 정보와 게시 권한을 확인해 주세요."
        case .reviewOutdated:
            "펫 정보가 변경되었습니다. 최신 정보를 다시 확인해 주세요."
        case .recommendedProfileUnavailable:
            "현재 펫 설정은 공유 가능한 제작자 설정으로 만들 수 없습니다."
        case .applicationRulesUnavailable:
            "현재 앱 사용 규칙은 공유 가능한 형식으로 만들 수 없습니다."
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
        behaviorProfile: BehaviorProfile? = nil,
        overlay: OverlaySettings? = nil
    ) throws -> PetPackageShareReview {
        let currentPackage = try loadCurrentPackage(installedPackage)
        let profiles = reviewedProfiles(
            behaviorProfile,
            overlay: overlay,
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
        options: PetPackageShareOptions = .standard,
        isConfirmed: Bool,
        to destinationURL: URL
    ) throws -> URL {
        let currentPackage = try loadCurrentPackage(installedPackage)
        guard review.matches(currentPackage.metadata) else {
            throw PetPackageSharingError.reviewOutdated
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
        } else {
            guard let profile = review.recommendedProfile else {
                throw PetPackageSharingError.recommendedProfileUnavailable
            }
            recommendedProfile = profile
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
        overlay: OverlaySettings?,
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
            overlay: overlay,
            automaticRules: behaviorProfile.automaticRules.filter {
                guard case .application = $0.condition else {
                    return true
                }
                return false
            }
        )
        let canonicalRecommended: RecommendedPetProfile
        do {
            let data = try RecommendedPetProfileCodec.encode(
                recommended,
                for: definition
            )
            canonicalRecommended = try RecommendedPetProfileCodec.decode(
                data,
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
            overlay: overlay,
            automaticRules: behaviorProfile.automaticRules
        )
        do {
            let data = try RecommendedPetProfileCodec.encode(
                withApplicationRules,
                for: definition
            )
            let canonicalWithApplicationRules =
                try RecommendedPetProfileCodec.decode(
                    data,
                    for: definition
                )
            return (
                canonicalRecommended,
                canonicalWithApplicationRules,
                nil,
                nil
            )
        } catch {
            return (
                canonicalRecommended,
                nil,
                nil,
                error.localizedDescription
            )
        }
    }

    private func recommendedProfile(
        from profile: BehaviorProfile,
        overlay: OverlaySettings?,
        automaticRules: [AutomaticRule]
    ) -> RecommendedPetProfile {
        RecommendedPetProfile(
            stationaryBehaviorMode: profile.stationaryBehaviorMode,
            stationarySequenceID: profile.stationarySequenceID,
            randomSequenceIDs: profile.randomSequenceIDs,
            sequences: profile.sequences,
            automaticRules: automaticRules,
            automaticRulePriorityOrder:
                profile.automaticRulePriorityOrder,
            movement: profile.movement,
            pettingMotionID: profile.pettingMotionID,
            speech: profile.speech,
            display: overlay.map { PortablePetDisplaySettings(overlay: $0) }
                ?? .default
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
