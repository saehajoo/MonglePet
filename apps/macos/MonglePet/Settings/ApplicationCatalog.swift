import AppKit
import Combine
import Foundation

nonisolated struct ApplicationChoice: Equatable, Identifiable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL?
    let iconData: Data?

    init(
        bundleIdentifier: String,
        displayName: String,
        bundleURL: URL?,
        iconData: Data? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.iconData = iconData
    }

    var id: String {
        bundleIdentifier
    }
}

nonisolated struct RunningApplicationCandidate: Equatable, Sendable {
    let bundleIdentifier: String?
    let displayName: String?
    let bundleURL: URL?
    let isUserFacing: Bool
    let iconData: Data?

    init(
        bundleIdentifier: String?,
        displayName: String?,
        bundleURL: URL?,
        isUserFacing: Bool,
        iconData: Data? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.isUserFacing = isUserFacing
        self.iconData = iconData
    }
}

nonisolated enum ApplicationCatalogNormalizer {
    static func choices(
        from candidates: [RunningApplicationCandidate],
        excluding excludedBundleIdentifier: String?
    ) -> [ApplicationChoice] {
        var choicesByIdentifier: [String: ApplicationChoice] = [:]

        for candidate in candidates where candidate.isUserFacing {
            guard let bundleIdentifier = normalizedIdentifier(
                candidate.bundleIdentifier
            ), bundleIdentifier != excludedBundleIdentifier else {
                continue
            }

            let displayName = normalizedDisplayName(
                candidate.displayName,
                fallback: candidate.bundleURL?
                    .deletingPathExtension()
                    .lastPathComponent,
                bundleIdentifier: bundleIdentifier
            )
            let choice = ApplicationChoice(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                bundleURL: candidate.bundleURL,
                iconData: candidate.iconData
            )

            if let existing = choicesByIdentifier[bundleIdentifier] {
                choicesByIdentifier[bundleIdentifier] = preferredChoice(
                    existing,
                    choice
                )
            } else {
                choicesByIdentifier[bundleIdentifier] = choice
            }
        }

        return choicesByIdentifier.values.sorted {
            let nameComparison = $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            )
            if nameComparison == .orderedSame {
                return $0.bundleIdentifier.localizedCaseInsensitiveCompare(
                    $1.bundleIdentifier
                ) == .orderedAscending
            }
            return nameComparison == .orderedAscending
        }
    }

    static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              !normalized.contains(where: \.isWhitespace) else {
            return nil
        }
        return normalized
    }

    static func normalizedDisplayName(
        _ value: String?,
        fallback: String?,
        bundleIdentifier: String
    ) -> String {
        for candidate in [value, fallback] {
            let normalized = candidate?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            if !normalized.isEmpty {
                return normalized
            }
        }
        return bundleIdentifier
    }

    private static func preferredChoice(
        _ lhs: ApplicationChoice,
        _ rhs: ApplicationChoice
    ) -> ApplicationChoice {
        if lhs.bundleURL == nil, rhs.bundleURL != nil {
            return rhs
        }
        if lhs.iconData == nil, rhs.iconData != nil {
            return rhs
        }
        if lhs.displayName == lhs.bundleIdentifier,
           rhs.displayName != rhs.bundleIdentifier {
            return rhs
        }
        return lhs
    }
}

@MainActor
protocol ApplicationCatalogProviding: AnyObject {
    func runningApplications() -> [ApplicationChoice]
    func application(at url: URL) throws -> ApplicationChoice
}

@MainActor
final class ApplicationCatalogSession: ObservableObject {
    @Published private(set) var runningApplications: [ApplicationChoice] = []

    private let provider: any ApplicationCatalogProviding

    init(
        provider: any ApplicationCatalogProviding = SystemApplicationCatalog()
    ) {
        self.provider = provider
    }

    func refresh() {
        runningApplications = provider.runningApplications()
    }

    func application(at url: URL) throws -> ApplicationChoice {
        try provider.application(at: url)
    }
}

enum ApplicationCatalogError: LocalizedError, Equatable {
    case notApplicationBundle
    case missingBundleIdentifier
    case monglePetCannotBeSelected

    var errorDescription: String? {
        switch self {
        case .notApplicationBundle:
            "선택한 항목은 macOS 앱(.app)이 아닙니다."
        case .missingBundleIdentifier:
            "선택한 앱에서 Bundle Identifier를 찾을 수 없습니다."
        case .monglePetCannotBeSelected:
            "MonglePet 자체는 앱 사용 규칙으로 선택할 수 없습니다."
        }
    }
}

@MainActor
final class SystemApplicationCatalog: ApplicationCatalogProviding {
    private let workspace: NSWorkspace
    private let excludedBundleIdentifier: String?

    init(
        workspace: NSWorkspace = .shared,
        excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.excludedBundleIdentifier = excludedBundleIdentifier
    }

    func runningApplications() -> [ApplicationChoice] {
        let candidates = workspace.runningApplications.map {
            RunningApplicationCandidate(
                bundleIdentifier: $0.bundleIdentifier,
                displayName: $0.localizedName,
                bundleURL: $0.bundleURL,
                isUserFacing: $0.activationPolicy == .regular
            )
        }
        return ApplicationCatalogNormalizer.choices(
            from: candidates,
            excluding: excludedBundleIdentifier
        )
    }

    func application(at url: URL) throws -> ApplicationChoice {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw ApplicationCatalogError.notApplicationBundle
        }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let bundle = Bundle(url: url) else {
            throw ApplicationCatalogError.notApplicationBundle
        }
        guard let bundleIdentifier =
                ApplicationCatalogNormalizer.normalizedIdentifier(
                    bundle.bundleIdentifier
                ) else {
            throw ApplicationCatalogError.missingBundleIdentifier
        }
        guard bundleIdentifier != excludedBundleIdentifier else {
            throw ApplicationCatalogError.monglePetCannotBeSelected
        }

        let displayName = ApplicationCatalogNormalizer.normalizedDisplayName(
            bundle.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String ?? bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String,
            fallback: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleIdentifier
        )

        return ApplicationChoice(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: url,
            iconData: workspace.icon(forFile: url.path).tiffRepresentation
        )
    }
}
