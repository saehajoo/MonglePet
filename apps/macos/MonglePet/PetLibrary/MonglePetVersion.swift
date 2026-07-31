import Foundation

nonisolated struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        precondition(major >= 0 && minor >= 0 && patch >= 0)
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return nil
        }

        var numbers: [Int] = []
        numbers.reserveCapacity(3)
        for component in components {
            guard
                !component.isEmpty,
                component.allSatisfy(\.isASCIIWholeNumber),
                component.count == 1 || component.first != "0",
                let number = Int(component)
            else {
                return nil
            }
            numbers.append(number)
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

private extension Character {
    nonisolated var isASCIIWholeNumber: Bool {
        isASCII && isWholeNumber
    }
}

nonisolated struct MonglePetAppVersionInfo: Equatable, Sendable {
    let semanticVersion: SemanticVersion
    let buildNumber: String

    var displayText: String {
        "MonglePet \(semanticVersion) (\(buildNumber))"
    }
}

nonisolated enum MonglePetAppVersion {
    static let fallbackVersion = SemanticVersion(major: 0, minor: 1, patch: 0)
    static let fallbackBuildNumber = "1"

    static var current: MonglePetAppVersionInfo {
        info(from: .main)
    }

    static func info(from bundle: Bundle) -> MonglePetAppVersionInfo {
        let semanticVersion = (
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ).flatMap(SemanticVersion.init) ?? fallbackVersion
        let buildNumber = (
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBuildNumber

        return MonglePetAppVersionInfo(
            semanticVersion: semanticVersion,
            buildNumber: buildNumber
        )
    }
}

nonisolated struct PetPackageCompatibility: Equatable, Sendable {
    let createdWithMonglePetVersion: SemanticVersion?
    let minimumMonglePetVersion: SemanticVersion?
}

nonisolated enum PetPackageCompatibilityAssessment: Equatable, Sendable {
    case compatible
    case createdWithNewerVersion(SemanticVersion)
    case requiresNewerVersion(SemanticVersion)

    var canInstall: Bool {
        if case .requiresNewerVersion = self {
            return false
        }
        return true
    }
}

nonisolated enum PetPackageCompatibilityPolicy {
    static func assess(
        _ compatibility: PetPackageCompatibility?,
        currentVersion: SemanticVersion
    ) -> PetPackageCompatibilityAssessment {
        if let minimumVersion = compatibility?.minimumMonglePetVersion,
           currentVersion < minimumVersion {
            return .requiresNewerVersion(minimumVersion)
        }
        if let createdWithVersion = compatibility?.createdWithMonglePetVersion,
           currentVersion < createdWithVersion {
            return .createdWithNewerVersion(createdWithVersion)
        }
        return .compatible
    }
}
