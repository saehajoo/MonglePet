import Combine
import Foundation

@MainActor
final class AppSettingsSession: ObservableObject {
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var isWritingEnabled = true
    @Published private(set) var loadNotice: String?
    @Published private(set) var saveErrorMessage: String?

    var onChange: ((AppSettings) -> Void)?

    private let store: AppSettingsStore

    init(store: AppSettingsStore) {
        self.store = store
    }

    @discardableResult
    func load() -> AppSettingsLoadResult {
        let result = store.load()
        settings = result.settings
        isWritingEnabled = result.isWritingEnabled
        loadNotice = Self.loadNotice(for: result)
        saveErrorMessage = nil
        return result
    }

    func setUserPresentation(_ presentation: PetPresentation) {
        guard presentation == .awake || presentation == .tuckedAway else {
            return
        }

        update(
            AppSettings(
                selectedPetInstallationID: settings.selectedPetInstallationID,
                lastUserPresentation: presentation,
                behaviorMode: settings.behaviorMode,
                overlay: settings.overlay,
                manualSequenceID: settings.manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }

    func setBehaviorMode(_ mode: BehaviorMode) {
        update(
            AppSettings(
                selectedPetInstallationID: settings.selectedPetInstallationID,
                lastUserPresentation: settings.lastUserPresentation,
                behaviorMode: mode,
                overlay: settings.overlay,
                manualSequenceID: settings.manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }

    func installBuiltInBehaviorPresetsIfNeeded() {
        guard settings.sequences.isEmpty else {
            return
        }

        settings = AppSettings(
            selectedPetInstallationID: settings.selectedPetInstallationID,
            lastUserPresentation: settings.lastUserPresentation,
            behaviorMode: settings.behaviorMode,
            overlay: settings.overlay,
            manualSequenceID: BuiltInBehaviorPresets.defaultManualSequenceID,
            sequences: BuiltInBehaviorPresets.sequences,
            automaticRules: BuiltInBehaviorPresets.automaticRules
        )
    }

    func setManualSequenceID(_ sequenceID: String) {
        guard settings.sequences.contains(where: { $0.id == sequenceID }) else {
            return
        }

        update(
            AppSettings(
                selectedPetInstallationID: settings.selectedPetInstallationID,
                lastUserPresentation: settings.lastUserPresentation,
                behaviorMode: settings.behaviorMode,
                overlay: settings.overlay,
                manualSequenceID: sequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }

    func setOverlayWidth(_ width: Double, persist: Bool = true) {
        let normalizedWidth = min(
            max(width, AppSettingsLimits.minimumOverlayWidth),
            AppSettingsLimits.maximumOverlayWidth
        )
        replaceOverlay(
            OverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: normalizedWidth,
                clickThrough: settings.overlay.clickThrough
            ),
            persist: persist
        )
    }

    func setClickThrough(_ clickThrough: Bool) {
        replaceOverlay(
            OverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: settings.overlay.width,
                clickThrough: clickThrough
            )
        )
    }

    func setOverlayGeometry(_ overlay: OverlaySettings) {
        replaceOverlay(overlay)
    }

    func synchronizeOverlayGeometry(_ overlay: OverlaySettings) {
        let synchronizedSettings = settingsReplacingOverlay(overlay)
        guard synchronizedSettings != settings else {
            return
        }
        settings = synchronizedSettings
    }

    func persistCurrentSettings() {
        persist(settings)
    }

    private func replaceOverlay(_ overlay: OverlaySettings, persist: Bool = true) {
        update(settingsReplacingOverlay(overlay), persist: persist)
    }

    private func settingsReplacingOverlay(_ overlay: OverlaySettings) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: settings.selectedPetInstallationID,
            lastUserPresentation: settings.lastUserPresentation,
            behaviorMode: settings.behaviorMode,
            overlay: overlay,
            manualSequenceID: settings.manualSequenceID,
            sequences: settings.sequences,
            automaticRules: settings.automaticRules
        )
    }

    private func update(_ newSettings: AppSettings, persist shouldPersist: Bool = true) {
        guard newSettings != settings else {
            if shouldPersist {
                persistCurrentSettings()
            }
            return
        }

        settings = newSettings
        onChange?(newSettings)
        if shouldPersist {
            persist(settings)
        }
    }

    private func persist(_ settings: AppSettings) {
        guard isWritingEnabled else {
            return
        }

        do {
            try store.save(settings)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private static func loadNotice(for result: AppSettingsLoadResult) -> String? {
        switch result.source {
        case let .newerSchema(version):
            return "더 새로운 설정 형식(버전 \(version))을 보호하기 위해 설정 저장을 중단했습니다."
        case .defaults:
            return nil
        case .file:
            return nil
        case .recovered:
            if result.issues.contains(where: { issue in
                if case .corruptFileQuarantined = issue {
                    return true
                }
                return false
            }) {
                return "손상된 설정 파일을 별도로 보관하고 기본 설정으로 복구했습니다."
            }
            if !result.isWritingEnabled {
                return "기존 설정 파일을 보호하기 위해 설정 저장을 중단했습니다."
            }
            return result.issues.isEmpty
                ? nil
                : "일부 잘못된 설정을 안전한 값으로 복구했습니다."
        }
    }
}

extension AppSettingsLoadResult {
    var shouldRestoreOverlayPosition: Bool {
        switch source {
        case .file:
            return true
        case .defaults, .newerSchema:
            return false
        case .recovered:
            return !issues.contains(where: { issue in
                switch issue {
                case .corruptFileQuarantined:
                    return true
                case let .invalidField(field):
                    return field == "settingsFile"
                default:
                    return false
                }
            })
        }
    }
}
