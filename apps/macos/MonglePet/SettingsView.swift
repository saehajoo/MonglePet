import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var loginLaunchSettings: LoginLaunchSettings
    @ObservedObject var runtimeControlSession: PetRuntimeControlSession
    @ObservedObject var remotePetImportRequestCenter: RemotePetImportRequestCenter
    let remotePetImportService: RemotePetImportService
    @State private var destination = SettingsDestination.myPets

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("데스크톱") {
                    navigationRow(
                        "내 펫",
                        systemImage: "pawprint.fill",
                        destination: .myPets
                    )
                    navigationRow(
                        "일반",
                        systemImage: "gearshape",
                        destination: .general
                    )
                }

                Section("선택한 펫") {
                    navigationRow(
                        "펫 정보·애니메이션",
                        systemImage: "photo.on.rectangle.angled",
                        destination: .petContent
                    )
                    navigationRow(
                        "화면 표시",
                        systemImage: "rectangle.on.rectangle",
                        destination: .display
                    )
                    navigationRow(
                        "평상시 행동",
                        systemImage: "play.square.stack",
                        destination: .stationaryBehavior
                    )
                    navigationRow(
                        "이동",
                        systemImage: "location",
                        destination: .movement
                    )
                    navigationRow(
                        "상호작용",
                        systemImage: "hand.point.up.left",
                        destination: .interaction
                    )
                    navigationRow(
                        "행동 편집",
                        systemImage: "list.bullet.rectangle",
                        destination: .behavior
                    )
                    navigationRow(
                        "말풍선",
                        systemImage: "text.bubble",
                        destination: .speech
                    )
                    navigationRow(
                        "규칙 설정",
                        systemImage: "bolt.badge.clock",
                        destination: .automaticRules
                    )
                }

            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 210,
                max: 250
            )
            .accessibilityIdentifier("monglepet.settings.sidebar")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 620)
        .accessibilityIdentifier("monglepet.settings.root")
        .onAppear(perform: synchronizeRemoteImportDestination)
        .onChange(of: remotePetImportRequestCenter.request?.id) {
            _, requestID in
            if requestID != nil {
                destination = .myPets
            }
        }
        .onChange(of: remotePetImportRequestCenter.errorMessage) {
            _, errorMessage in
            if errorMessage != nil {
                destination = .myPets
            }
        }
    }

    private func synchronizeRemoteImportDestination() {
        if remotePetImportRequestCenter.request != nil
            || remotePetImportRequestCenter.errorMessage != nil {
            destination = .myPets
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination {
        case .myPets:
            MyPetsSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                runtimeControlSession: runtimeControlSession,
                remotePetImportRequestCenter: remotePetImportRequestCenter,
                remotePetImportService: remotePetImportService
            )
        case .general:
            GeneralSettingsView(
                settingsSession: settingsSession,
                loginLaunchSettings: loginLaunchSettings
            )
        case .petContent:
            PetSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                remotePetImportRequestCenter:
                    remotePetImportRequestCenter,
                remotePetImportService: remotePetImportService
            )
        case .display:
            PetDisplaySettingsView(
                settingsSession: settingsSession,
                petDisplayName: selectedPetDisplayName
            )
        case .stationaryBehavior:
            MovementSettingsView(
                settingsSession: settingsSession,
                petDefinition: selectedActivePetItem.definition,
                content: .stationaryBehavior
            )
        case .movement:
            MovementSettingsView(
                settingsSession: settingsSession,
                petDefinition: selectedActivePetItem.definition,
                content: .movement
            )
        case .interaction:
            MovementSettingsView(
                settingsSession: settingsSession,
                petDefinition: selectedActivePetItem.definition,
                content: .interaction
            )
        case .behavior:
            BehaviorSequencesSettingsView(
                settingsSession: settingsSession,
                petDefinition: selectedActivePetItem.definition,
                petDisplayName: selectedPetDisplayName
            )
        case .speech:
            SpeechBubbleSettingsView(
                settingsSession: settingsSession,
                petItem: selectedActivePetItem,
                petDisplayName: selectedPetDisplayName
            )
        case .automaticRules:
            AutomaticRulesSettingsView(
                settingsSession: settingsSession,
                petDisplayName: selectedPetDisplayName
            )
        }
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        destination: SettingsDestination
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(destination)
            .accessibilityIdentifier(destination.accessibilityIdentifier)
    }

    private var selectedPetDisplayName: String {
        settingsSession.settings.selectedPetInstance?.nickname
            ?? selectedActivePetItem.metadata.displayName
    }

    private var selectedActivePetItem: PetLibraryItem {
        petLibrarySession.item(
            for: settingsSession.settings.selectedPetKey
        ) ?? petLibrarySession.items.first(where: \.isBuiltIn)
            ?? petLibrarySession.selectedItem
    }
}

private enum SettingsDestination: Hashable {
    case myPets
    case general
    case petContent
    case display
    case stationaryBehavior
    case movement
    case interaction
    case behavior
    case speech
    case automaticRules

    var accessibilityIdentifier: String {
        switch self {
        case .myPets:
            "monglepet.settings.navigation.activePets"
        case .general:
            "monglepet.settings.navigation.general"
        case .petContent:
            "monglepet.settings.navigation.petContent"
        case .display:
            "monglepet.settings.navigation.display"
        case .stationaryBehavior:
            "monglepet.settings.navigation.stationaryBehavior"
        case .movement:
            "monglepet.settings.navigation.movement"
        case .interaction:
            "monglepet.settings.navigation.interaction"
        case .behavior:
            "monglepet.settings.navigation.behavior"
        case .speech:
            "monglepet.settings.navigation.speech"
        case .automaticRules:
            "monglepet.settings.navigation.automaticRules"
        }
    }
}

private struct MyPetsSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var runtimeControlSession: PetRuntimeControlSession
    @ObservedObject var remotePetImportRequestCenter: RemotePetImportRequestCenter
    let remotePetImportService: RemotePetImportService
    @State private var isCreatingPet = false
    @State private var isImportingPet = false
    @State private var isCreatingPetCopy = false
    @State private var shareReview: PetPackageShareReview?
    @State private var pendingSharingFollowUp: PetSharingFollowUp?
    @State private var petPackageExportDocument: MonglePetPackageDocument?
    @State private var petPackageExportFileName = "MonglePet.monglepet"
    @State private var isPresentingPetPackageExporter = false
    @State private var petPackageExportErrorMessage: String?
    @State private var exportedPackageFileName: String?

    var body: some View {
        ActivePetsSettingsView(
            settingsSession: settingsSession,
            petLibrarySession: petLibrarySession,
            runtimeControlSession: runtimeControlSession,
            onCreatePet: { isCreatingPet = true },
            onImportPet: { isImportingPet = true },
            onCreateCopy: preparePetCopy,
            onExport: preparePetExport,
            onDelete: deletePet
        )
        .navigationTitle("내 펫")
        .sheet(isPresented: $isCreatingPet) {
            UserPetAnimationEditorView(
                mode: .create,
                petLibrarySession: petLibrarySession,
                settingsSession: settingsSession,
                prepareForSaving: { true }
            )
        }
        .sheet(isPresented: $isImportingPet) {
            PetImportSheetView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                remotePetImportRequestCenter:
                    remotePetImportRequestCenter,
                remotePetImportService: remotePetImportService
            )
        }
        .sheet(isPresented: $isCreatingPetCopy) {
            PetCopyEditorView(
                item: petLibrarySession.selectedItem,
                petLibrarySession: petLibrarySession
            )
        }
        .sheet(
            item: $shareReview,
            onDismiss: performPendingSharingFollowUp
        ) { review in
            PetPackageShareReviewView(
                review: review,
                onExport: { options in
                    pendingSharingFollowUp = .export(review, options)
                }
            )
        }
        .fileExporter(
            isPresented: $isPresentingPetPackageExporter,
            document: petPackageExportDocument,
            contentType: MonglePetPackageDocument.contentType,
            defaultFilename: petPackageExportFileName,
            onCompletion: handlePetPackageExportResult
        )
        .alert(
            "펫 내보내기 완료",
            isPresented: exportSuccessAlertBinding
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(exportedPackageFileName ?? "펫 패키지") 파일을 저장했습니다.")
        }
        .alert(
            "펫을 내보내지 못했습니다",
            isPresented: exportErrorAlertBinding
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(petPackageExportErrorMessage ?? "펫 공유 파일을 준비하지 못했습니다.")
        }
        .alert(
            "펫 추가 완료",
            isPresented: importNoticeAlertBinding
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(petLibrarySession.importNoticeMessage ?? "")
        }
        .onAppear(perform: presentImportIfNeeded)
        .onChange(of: remotePetImportRequestCenter.request?.id) {
            _, _ in presentImportIfNeeded()
        }
        .onChange(of: remotePetImportRequestCenter.errorMessage) {
            _, _ in presentImportIfNeeded()
        }
        .accessibilityIdentifier("monglepet.settings.myPets")
    }

    private func preparePetCopy(_ instanceID: UUID) {
        guard select(instanceID) else { return }
        isCreatingPetCopy = true
    }

    private func preparePetExport(_ instanceID: UUID) {
        guard select(instanceID),
              let runtimeSettings = settingsSession.settings.runtimeSettings(
                  for: instanceID
              ) else {
            return
        }
        shareReview = petLibrarySession.reviewSelectedPetForSharing(
            behaviorProfile: runtimeSettings.activeBehaviorProfile,
            overlay: runtimeSettings.overlay
        )
    }

    private func deletePet(_ instanceID: UUID) {
        guard let instance = settingsSession.settings.activePetInstances
            .first(where: { $0.instanceID == instanceID }) else {
            return
        }
        let installationID = instance.petKey.installationID
        let referenceCount = settingsSession.settings.activePetInstances
            .filter { $0.petKey == instance.petKey }
            .count
        let removesInstallation = installationID != nil && referenceCount == 1

        _ = settingsSession.removePetInstance(
            instanceID,
            removingInstallation: removesInstallation ? {
                guard let installationID else { return }
                try petLibrarySession.removeInstallationForDeletedPet(
                    installationID
                )
            } : nil
        )
    }

    private func select(_ instanceID: UUID) -> Bool {
        guard let instance = settingsSession.settings.activePetInstances
            .first(where: { $0.instanceID == instanceID }),
              let item = petLibrarySession.item(for: instance.petKey) else {
            return false
        }
        settingsSession.selectPetInstance(instanceID)
        return petLibrarySession.select(item.selection)
    }

    private func preparePetPackageExport(
        for review: PetPackageShareReview,
        options: PetPackageShareOptions
    ) {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MonglePetShareUI-\(UUID().uuidString)",
                isDirectory: true
            )
        let archiveURL = workspaceURL.appendingPathComponent(
            review.suggestedFileName,
            isDirectory: false
        )

        do {
            try FileManager.default.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false
            )
        } catch {
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
            return
        }
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        guard petLibrarySession.exportSelectedPet(
            reviewed: review,
            options: options,
            isConfirmed: true,
            to: archiveURL
        ) else {
            return
        }

        do {
            petPackageExportDocument = MonglePetPackageDocument(
                data: try Data(contentsOf: archiveURL)
            )
            petPackageExportFileName = review.suggestedFileName
            petPackageExportErrorMessage = nil
            isPresentingPetPackageExporter = true
        } catch {
            petPackageExportDocument = nil
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
        }
    }

    private func performPendingSharingFollowUp() {
        guard let followUp = pendingSharingFollowUp else { return }
        pendingSharingFollowUp = nil
        switch followUp {
        case let .export(review, options):
            preparePetPackageExport(for: review, options: options)
        }
    }

    private func handlePetPackageExportResult(
        _ result: Result<URL, Error>
    ) {
        switch result {
        case let .success(destinationURL):
            petPackageExportErrorMessage = nil
            exportedPackageFileName = destinationURL.lastPathComponent
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                petPackageExportErrorMessage = error.localizedDescription
            }
        }
    }

    private var exportSuccessAlertBinding: Binding<Bool> {
        Binding(
            get: { exportedPackageFileName != nil },
            set: { if !$0 { exportedPackageFileName = nil } }
        )
    }

    private var exportErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { petPackageExportErrorMessage != nil },
            set: { if !$0 { petPackageExportErrorMessage = nil } }
        )
    }

    private var importNoticeAlertBinding: Binding<Bool> {
        Binding(
            get: { petLibrarySession.importNoticeMessage != nil },
            set: { if !$0 { petLibrarySession.clearImportNotice() } }
        )
    }

    private func presentImportIfNeeded() {
        if remotePetImportRequestCenter.request != nil
            || remotePetImportRequestCenter.errorMessage != nil {
            isImportingPet = true
        }
    }
}

private struct PetImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var remotePetImportRequestCenter:
        RemotePetImportRequestCenter
    let remotePetImportService: RemotePetImportService
    @State private var importReview: PetPackageImportReview?
    @State private var pendingImportAction: PetImportAction?
    @State private var remotePetURLText = ""
    @State private var isImportingRemotePet = false
    @State private var remoteImportErrorMessage: String?
    @State private var remoteImportTemporaryDirectoryURL: URL?
    @State private var remoteImportTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("펫 가져오기")
                        .font(.title2.weight(.semibold))
                    Text("웹 주소 또는 Mac에 저장된 패키지에서 새 펫을 추가합니다.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기", role: .cancel) { dismiss() }
            }
            .padding(20)

            Divider()

            Form {
                if let error = petLibrarySession.errorMessage {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                }

                Section("웹에서 가져오기") {
                    RemotePetImportControls(
                        urlText: $remotePetURLText,
                        isImporting: isImportingRemotePet,
                        isBusy: isBusy,
                        errorMessage: remoteImportErrorMessage
                            ?? remotePetImportRequestCenter.errorMessage,
                        catalogURL: webPetCatalogURL,
                        onInputChange: clearRemoteImportErrors,
                        onImport: { startRemotePetImport() }
                    )
                }

                Section("Mac의 패키지 파일") {
                    Text(".monglepet 파일을 선택하면 펫 정보와 제작자가 구성한 설정을 먼저 보여드립니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("패키지 파일 선택…", systemImage: "doc.badge.plus") {
                        choosePetPackage()
                    }
                    .disabled(isBusy)
                    .accessibilityIdentifier("monglepet.settings.importPackage")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 620, minHeight: 620)
        .sheet(
            item: $importReview,
            onDismiss: performPendingImportAction
        ) { review in
            PetPackageImportReviewView(
                review: review,
                allowsInstallation: settingsSession.isWritingEnabled,
                onInstall: {
                    pendingImportAction = PetImportAction(review: review)
                }
            )
        }
        .onAppear(perform: performPendingRemoteImportRequest)
        .onDisappear {
            remoteImportTask?.cancel()
            remoteImportTask = nil
            cleanupRemoteImportIfFinished()
        }
    }

    private var isBusy: Bool {
        petLibrarySession.isImporting
            || petLibrarySession.isExporting
            || isImportingRemotePet
    }

    private var webPetCatalogURL: URL {
#if DEBUG
        URL(string: "https://dev.mapleroom.kr/monglepet/pets")!
#else
        URL(string: "https://mapleroom.kr/monglepet/pets")!
#endif
    }

    private func choosePetPackage() {
        let panel = NSOpenPanel()
        panel.title = "MonglePet 패키지 가져오기"
        panel.prompt = "가져오기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if let packageType = UTType(filenameExtension: "monglepet") {
            panel.allowedContentTypes = [packageType]
        }
        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        importReview = petLibrarySession.reviewPackageForImport(
            from: sourceURL
        )
    }

    private func performPendingRemoteImportRequest() {
        guard let request = remotePetImportRequestCenter.request else {
            return
        }
        remotePetImportRequestCenter.consume(request.id)
        remotePetImportRequestCenter.clearError()
        remotePetURLText = request.source.canonicalWebURL.absoluteString
        startRemotePetImport(source: request.source)
    }

    private func startRemotePetImport(source: RemotePetImportSource? = nil) {
        guard !isBusy else { return }
        remoteImportTask?.cancel()
        remoteImportErrorMessage = nil
        remotePetImportRequestCenter.clearError()
        isImportingRemotePet = true
        let input = remotePetURLText
        remoteImportTask = Task {
            do {
                let prepared: RemotePetPreparedPackage
                if let source {
                    prepared = try await remotePetImportService.preparePackage(
                        from: source
                    )
                } else {
                    prepared = try await remotePetImportService.preparePackage(
                        from: input
                    )
                }
                do {
                    try Task.checkCancellation()
                } catch {
                    try? FileManager.default.removeItem(
                        at: prepared.temporaryDirectoryURL
                    )
                    throw error
                }
                cleanupRemoteImportTemporaryDirectory()
                remoteImportTemporaryDirectoryURL =
                    prepared.temporaryDirectoryURL
                importReview = petLibrarySession.reviewPackageForImport(
                    from: prepared.packageURL
                )?.withPublishedMinimumMonglePetVersion(
                    prepared.publishedMinimumMonglePetVersion
                )
                if importReview == nil {
                    cleanupRemoteImportTemporaryDirectory()
                }
            } catch is CancellationError {
                // Closing the sheet cancels an unfinished request.
            } catch {
                remoteImportErrorMessage = messageForRemoteImportError(error)
            }
            isImportingRemotePet = false
            remoteImportTask = nil
        }
    }

    private func clearRemoteImportErrors() {
        remoteImportErrorMessage = nil
        remotePetImportRequestCenter.clearError()
    }

    private func messageForRemoteImportError(_ error: Error) -> String {
        if let importError = error as? RemotePetImportError {
            return importError.localizedDescription
        }
        guard let urlError = error as? URLError else {
            return "펫을 가져오지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        }
        switch urlError.code {
        case .notConnectedToInternet:
            return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        case .timedOut, .networkConnectionLost:
            return "서버 응답이 늦거나 연결이 끊겼습니다. 잠시 뒤 다시 시도해 주세요."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "MonglePet 서버에 연결할 수 없습니다. 주소를 확인하거나 잠시 뒤 다시 시도해 주세요."
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted:
            return "MonglePet 서버와 안전하게 연결할 수 없어 가져오기를 중단했습니다."
        default:
            return "펫을 가져오지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        }
    }

    private func performPendingImportAction() {
        guard let action = pendingImportAction else {
            cleanupRemoteImportTemporaryDirectory()
            return
        }
        pendingImportAction = nil
        let succeeded = petLibrarySession.installReviewedPackage(
            action.review
        )
        cleanupRemoteImportIfFinished()
        if succeeded {
            dismiss()
        }
    }

    private func cleanupRemoteImportIfFinished() {
        guard importReview == nil, pendingImportAction == nil else { return }
        cleanupRemoteImportTemporaryDirectory()
    }

    private func cleanupRemoteImportTemporaryDirectory() {
        guard let remoteImportTemporaryDirectoryURL else { return }
        try? FileManager.default.removeItem(
            at: remoteImportTemporaryDirectoryURL
        )
        self.remoteImportTemporaryDirectoryURL = nil
    }
}

private struct PetSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var remotePetImportRequestCenter: RemotePetImportRequestCenter
    let remotePetImportService: RemotePetImportService
    @State private var isConfirmingAnimationRemoval = false
    @State private var isEditingPetDetails = false
    @State private var userPetEditorMode: UserPetEditorMode?
    @State private var editingAnimation: PetMotion?
    @State private var duplicatingAnimation: PetMotion?
    @State private var previewMotionID: String?
    @State private var importReview: PetPackageImportReview?
    @State private var pendingImportAction: PetImportAction?
    @State private var shareReview: PetPackageShareReview?
    @State private var pendingSharingFollowUp: PetSharingFollowUp?
    @State private var petPackageExportDocument: MonglePetPackageDocument?
    @State private var petPackageExportFileName = "MonglePet.monglepet"
    @State private var isPresentingPetPackageExporter = false
    @State private var petPackageExportErrorMessage: String?
    @State private var exportedPackageFileName: String?
    @State private var remotePetURLText = ""
    @State private var isImportingRemotePet = false
    @State private var remoteImportErrorMessage: String?
    @State private var remoteImportTemporaryDirectoryURL: URL?
    @State private var remoteImportTask: Task<Void, Never>?
    @State private var isConfirmingDesktopAddition = false
    @State private var desktopAdditionRecommendedProfile:
        RecommendedPetProfile?

    var body: some View {
        Form {
            if let loadNotice = settingsSession.loadNotice {
                noticeLabel(loadNotice, systemImage: "exclamationmark.triangle.fill")
            }
            if let saveErrorMessage = settingsSession.saveErrorMessage {
                noticeLabel(saveErrorMessage, systemImage: "xmark.circle.fill")
            }
            if let libraryErrorMessage = petLibrarySession.errorMessage {
                noticeLabel(libraryErrorMessage, systemImage: "xmark.circle.fill")
            }
            if let petPackageExportErrorMessage {
                noticeLabel(
                    petPackageExportErrorMessage,
                    systemImage: "xmark.circle.fill"
                )
            }
            Section("펫 정보") {
                HStack(alignment: .top, spacing: 16) {
                    PetAnimationPreviewView(
                        item: petLibrarySession.selectedItem,
                        motionID: effectivePreviewMotionID
                    )
                    .frame(width: 160, height: 160)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityLabel("선택한 펫 애니메이션 미리보기")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            petLibrarySession.selectedItem.metadata.displayName
                        )
                        .font(.title3.weight(.semibold))

                        LabeledContent(
                            "버전",
                            value: petLibrarySession.selectedItem.metadata.version
                        )
                        LabeledContent(
                            "제작자",
                            value: petLibrarySession.selectedItem.metadata.author
                        )
                        if let description = petLibrarySession.selectedItem.metadata.description {
                            LabeledContent("설명", value: description)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    isEditingPetDetails = true
                } label: {
                    Label("펫 정보 수정", systemImage: "pencil")
                }
                .disabled(petLibrarySession.isImporting)
                .accessibilityIdentifier(
                    "monglepet.settings.editPetDetails"
                )

                Text("내장 펫이나 여러 펫이 같은 이미지를 공유하는 경우에도 선택한 펫만 안전하게 분리해 수정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("애니메이션") {
                PetAnimationListView(
                    motions: petLibrarySession.selectedItem.definition.motions,
                    defaultMotionID: petLibrarySession.selectedItem.definition
                        .defaultMotionID,
                    selectedMotionID: effectivePreviewMotionID,
                    height: animationListHeight
                ) { motionID in
                    previewMotionID = motionID
                }

                if let motion = selectedPreviewMotion {
                    LabeledContent("선택한 애니메이션") {
                        Text(motionSummary(motion))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityIdentifier(
                                "monglepet.settings.petAnimationSummary"
                            )
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 160), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    Button {
                        userPetEditorMode = .addAnimation
                    } label: {
                        Label(
                            "애니메이션 추가",
                            systemImage: "photo.badge.plus"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(petLibrarySession.isImporting)
                    .accessibilityIdentifier(
                        "monglepet.settings.addPetAnimation"
                    )

                    Button {
                        editingAnimation = selectedPreviewMotion
                    } label: {
                        Label(
                            "애니메이션 수정",
                            systemImage: "slider.horizontal.3"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(
                        selectedPreviewMotion == nil
                            || petLibrarySession.isImporting
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.editPetAnimation"
                    )

                    Button {
                        duplicatingAnimation = selectedPreviewMotion
                    } label: {
                        Label(
                            "애니메이션 복제…",
                            systemImage: "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(
                        selectedPreviewMotion == nil
                            || petLibrarySession.isImporting
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.duplicatePetAnimation"
                    )

                    Button(role: .destructive) {
                        isConfirmingAnimationRemoval = true
                    } label: {
                        Label(
                            "애니메이션 삭제",
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(
                        !canDeleteSelectedAnimation
                            || petLibrarySession.isImporting
                    )
                    .help(animationDeletionHelp)
                    .accessibilityIdentifier(
                        "monglepet.settings.removePetAnimation"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "선택한 애니메이션을 삭제할까요?",
            isPresented: $isConfirmingAnimationRemoval
        ) {
            Button("삭제", role: .destructive) {
                removeSelectedAnimation()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 애니메이션을 사용하던 행동 단계는 현재 펫의 기본 애니메이션으로 복구됩니다.")
        }
        .sheet(item: $userPetEditorMode) { mode in
            UserPetAnimationEditorView(
                mode: mode,
                petLibrarySession: petLibrarySession,
                settingsSession: settingsSession,
                prepareForSaving: {
                    mode == .create || ensureSelectedPetIsEditable()
                }
            )
        }
        .sheet(item: $duplicatingAnimation) { motion in
            UserPetAnimationEditorView(
                mode: .addAnimation,
                petLibrarySession: petLibrarySession,
                settingsSession: settingsSession,
                prepareForSaving: ensureSelectedPetIsEditable,
                duplicating: motion
            )
        }
        .sheet(isPresented: $isEditingPetDetails) {
            UserPetDetailsEditorView(
                item: petLibrarySession.selectedItem,
                petLibrarySession: petLibrarySession,
                prepareForSaving: ensureSelectedPetIsEditable
            )
        }
        .sheet(item: $editingAnimation) { motion in
            UserPetAnimationDetailsEditorView(
                item: petLibrarySession.selectedItem,
                motion: motion,
                petLibrarySession: petLibrarySession,
                settingsSession: settingsSession,
                prepareForSaving: ensureSelectedPetIsEditable,
                duplicationSourceAnimationID: nil,
                onSaved: { animationID in
                    previewMotionID = animationID
                }
            )
        }
        .onAppear(perform: synchronizeSelectedPetContent)
        .onChange(of: settingsSession.settings.selectedPetInstanceID) {
            _, _ in synchronizeSelectedPetContent()
        }
        .onChange(of: petLibrarySession.selection) {
            synchronizePreviewMotion()
        }
    }

    private var effectivePreviewMotionID: String {
        if let previewMotionID,
           petLibrarySession.selectedItem.definition.motion(id: previewMotionID) != nil {
            return previewMotionID
        }
        return petLibrarySession.selectedItem.definition.defaultMotion?.id ?? ""
    }

    @ViewBuilder
    private var petPackageSection: some View {
        Section("웹에서 펫 가져오기") {
            RemotePetImportControls(
                urlText: $remotePetURLText,
                isImporting: isImportingRemotePet,
                isBusy: isPetLibraryBusy,
                errorMessage: remoteImportErrorMessage
                    ?? remotePetImportRequestCenter.errorMessage,
                catalogURL: webPetCatalogURL,
                onInputChange: clearRemoteImportErrors,
                onImport: { startRemotePetImport() }
            )
        }

        Section("Mac의 패키지 가져오기") {
            Text("Mac에 저장된 .monglepet 파일을 선택해 설치 내용을 확인합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                choosePetPackage()
            } label: {
                Label(
                    "패키지 파일 선택…",
                    systemImage: "doc.badge.plus"
                )
            }
            .disabled(isPetLibraryBusy)
            .accessibilityIdentifier("monglepet.settings.importPackage")
        }

        Section("선택한 설치 펫 내보내기") {
            if petLibrarySession.selectedItem.isBuiltIn {
                Label(
                    "내장 몽글이는 패키지 파일로 내보낼 수 없습니다.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("선택한 펫의 이미지와 모든 공유 가능한 설정을 .monglepet 파일로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    shareReview = petLibrarySession
                        .reviewSelectedPetForSharing(
                            behaviorProfile: selectedContentRuntimeSettings?
                                .activeBehaviorProfile,
                            overlay: selectedContentRuntimeSettings?.overlay
                        )
                } label: {
                    Label(
                        "패키지 파일로 저장…",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isPetLibraryBusy)
                .accessibilityIdentifier(
                    "monglepet.settings.exportPackage"
                )
            }
        }
    }

    private var webPetCatalogURL: URL {
#if DEBUG
        URL(string: "https://dev.mapleroom.kr/monglepet/pets")!
#else
        URL(string: "https://mapleroom.kr/monglepet/pets")!
#endif
    }

    private var selectedPreviewMotion: PetMotion? {
        petLibrarySession.selectedItem.definition.motion(id: effectivePreviewMotionID)
    }

    private var animationListHeight: CGFloat {
        let visibleRowCount = min(
            petLibrarySession.selectedItem.definition.motions.count,
            7
        )
        return max(112, CGFloat(visibleRowCount) * 34 + 8)
    }

    private var isPetLibraryBusy: Bool {
        petLibrarySession.isImporting
            || petLibrarySession.isExporting
            || isImportingRemotePet
    }

    private var canDeleteSelectedAnimation: Bool {
        guard let motion = selectedPreviewMotion else {
            return false
        }
        return petLibrarySession.selectedItem.definition.motions.count > 1
            && motion.id != petLibrarySession.selectedItem.definition.defaultMotionID
    }

    private var animationDeletionHelp: String {
        guard petLibrarySession.selectedItem.definition.motions.count > 1 else {
            return "마지막 남은 애니메이션은 삭제할 수 없습니다."
        }
        guard selectedPreviewMotion?.id
                != petLibrarySession.selectedItem.definition.defaultMotionID else {
            return "기본 애니메이션은 펫 정보 수정에서 다른 기본값을 선택한 뒤 삭제할 수 있습니다."
        }
        return "선택한 애니메이션을 삭제합니다."
    }

    private func synchronizePreviewMotion() {
        previewMotionID = petLibrarySession.selectedItem.definition.defaultMotion?.id
    }

    private func synchronizeSelectedPetContent() {
        guard let instance = settingsSession.settings.selectedPetInstance,
              let item = petLibrarySession.item(for: instance.petKey) else {
            synchronizePreviewMotion()
            return
        }
        _ = petLibrarySession.select(item.selection)
        synchronizePreviewMotion()
    }

    private func ensureSelectedPetIsEditable() -> Bool {
        synchronizeSelectedPetContent()
        guard let instance = settingsSession.settings.selectedPetInstance else {
            return false
        }
        let referenceCount = settingsSession.settings.activePetInstances
            .filter { $0.petKey == instance.petKey }
            .count
        let displayName = instance.nickname
            ?? petLibrarySession.selectedItem.metadata.displayName
        guard petLibrarySession.prepareSelectedPetForEditing(
            displayName: displayName,
            instanceID: instance.instanceID,
            requiresIndependentCopy: referenceCount > 1
        ) else {
            return false
        }
        synchronizeSelectedPetContent()
        return true
    }

    private func removeSelectedAnimation() {
        guard let motionID = selectedPreviewMotion?.id else {
            return
        }
        guard ensureSelectedPetIsEditable() else { return }
        if petLibrarySession.removeSelectedPetAnimation(id: motionID) {
            synchronizePreviewMotion()
        }
    }

    private func motionSummary(_ motion: PetMotion) -> String {
        let duration = motion.frames.reduce(Int64.zero) {
            $0 + durationMilliseconds($1.duration)
        }
        let playback = motion.loops ? "반복" : "1회"
        return "\(motion.frames.count)프레임 · \(duration)ms · \(playback)"
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
    }

    private var petSelectionBinding: Binding<PetLibrarySelection> {
        Binding(
            get: { petLibrarySession.selection },
            set: { _ = petLibrarySession.select($0) }
        )
    }

    private var selectedInstallationActiveReferenceCount: Int {
        let selectedKey = PetBehaviorKey(
            installationID: petLibrarySession.selectedInstallationID
        )
        guard selectedKey != .builtIn else { return 0 }
        return settingsSession.settings.activePetInstances.filter {
            $0.petKey == selectedKey
        }.count
    }

    private var selectedContentRuntimeSettings: AppSettings? {
        let selectedKey = PetBehaviorKey(
            installationID: petLibrarySession.selectedInstallationID
        )
        let settings = settingsSession.settings
        if settings.selectedPetInstance?.petKey == selectedKey {
            return settings.runtimeSettings(
                for: settings.selectedPetInstanceID
            )
        }
        guard let instanceID = settings.activePetInstances
            .filter({ $0.petKey == selectedKey })
            .sorted(by: { $0.displayOrder < $1.displayOrder })
            .first?.instanceID else {
            return nil
        }
        return settings.runtimeSettings(for: instanceID)
    }

    private func prepareDesktopPetAddition() {
        desktopAdditionRecommendedProfile = petLibrarySession
            .recommendedProfileForSelectedPet()
        isConfirmingDesktopAddition = true
    }

    private func addSelectedPetToDesktop(
        appliesRecommendedProfile: Bool
    ) {
        let petKey = PetBehaviorKey(
            installationID: petLibrarySession.selectedInstallationID
        )
        if appliesRecommendedProfile,
           let desktopAdditionRecommendedProfile {
            _ = settingsSession.addPetInstance(
                for: petKey,
                applyingRecommendedProfile: desktopAdditionRecommendedProfile
            )
        } else {
            _ = settingsSession.addPetInstance(
                for: petKey,
                usesSelectedOverlayFallback: false
            )
        }
        self.desktopAdditionRecommendedProfile = nil
    }

    private var exportSuccessAlertBinding: Binding<Bool> {
        Binding(
            get: { exportedPackageFileName != nil },
            set: { isPresented in
                if !isPresented {
                    exportedPackageFileName = nil
                }
            }
        )
    }

    private func choosePetPackage() {
        let panel = NSOpenPanel()
        panel.title = "MonglePet 패키지 가져오기"
        panel.prompt = "가져오기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if let packageType = UTType(filenameExtension: "monglepet") {
            panel.allowedContentTypes = [packageType]
        }

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        importReview = petLibrarySession.reviewPackageForImport(from: sourceURL)
    }

    private func performPendingRemoteImportRequest() {
        guard let request = remotePetImportRequestCenter.request else {
            return
        }
        remotePetImportRequestCenter.consume(request.id)
        remotePetImportRequestCenter.clearError()
        remotePetURLText = request.source.canonicalWebURL.absoluteString
        startRemotePetImport(source: request.source)
    }

    private func startRemotePetImport(source: RemotePetImportSource? = nil) {
        guard !isPetLibraryBusy else {
            return
        }
        remoteImportTask?.cancel()
        remoteImportErrorMessage = nil
        remotePetImportRequestCenter.clearError()
        isImportingRemotePet = true
        let input = remotePetURLText
        remoteImportTask = Task {
            do {
                let prepared: RemotePetPreparedPackage
                if let source {
                    prepared = try await remotePetImportService.preparePackage(
                        from: source
                    )
                } else {
                    prepared = try await remotePetImportService.preparePackage(
                        from: input
                    )
                }
                do {
                    try Task.checkCancellation()
                } catch {
                    try? FileManager.default.removeItem(
                        at: prepared.temporaryDirectoryURL
                    )
                    throw error
                }

                cleanupRemoteImportTemporaryDirectory()
                remoteImportTemporaryDirectoryURL = prepared.temporaryDirectoryURL
                importReview = petLibrarySession.reviewPackageForImport(
                    from: prepared.packageURL
                )?.withPublishedMinimumMonglePetVersion(
                    prepared.publishedMinimumMonglePetVersion
                )
                if importReview == nil {
                    cleanupRemoteImportTemporaryDirectory()
                }
            } catch is CancellationError {
                // Switching away from the view cancels an unfinished request.
            } catch {
                remoteImportErrorMessage = messageForRemoteImportError(error)
            }
            isImportingRemotePet = false
            remoteImportTask = nil
        }
    }

    private func clearRemoteImportErrors() {
        remoteImportErrorMessage = nil
        remotePetImportRequestCenter.clearError()
    }

    private func messageForRemoteImportError(_ error: Error) -> String {
        if let importError = error as? RemotePetImportError {
            return importError.localizedDescription
        }
        guard let urlError = error as? URLError else {
            return "펫을 가져오지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        }
        switch urlError.code {
        case .notConnectedToInternet:
            return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        case .timedOut, .networkConnectionLost:
            return "서버 응답이 늦거나 연결이 끊겼습니다. 잠시 뒤 다시 시도해 주세요."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "MonglePet 서버에 연결할 수 없습니다. 주소를 확인하거나 잠시 뒤 다시 시도해 주세요."
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateUntrusted:
            return "MonglePet 서버와 안전하게 연결할 수 없어 가져오기를 중단했습니다."
        default:
            return "펫을 가져오지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        }
    }

    private func performPendingImportAction() {
        guard let action = pendingImportAction else {
            cleanupRemoteImportTemporaryDirectory()
            return
        }
        pendingImportAction = nil
        _ = petLibrarySession.installReviewedPackage(
            action.review
        )
        cleanupRemoteImportIfFinished()
    }

    private func cleanupRemoteImportIfFinished() {
        guard
            importReview == nil,
            pendingImportAction == nil
        else {
            return
        }
        cleanupRemoteImportTemporaryDirectory()
    }

    private func cleanupRemoteImportTemporaryDirectory() {
        guard let remoteImportTemporaryDirectoryURL else {
            return
        }
        try? FileManager.default.removeItem(at: remoteImportTemporaryDirectoryURL)
        self.remoteImportTemporaryDirectoryURL = nil
    }

    private func preparePetPackageExport(
        for review: PetPackageShareReview,
        options: PetPackageShareOptions
    ) {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MonglePetShareUI-\(UUID().uuidString)",
                isDirectory: true
            )
        let archiveURL = workspaceURL.appendingPathComponent(
            review.suggestedFileName,
            isDirectory: false
        )

        do {
            try FileManager.default.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false
            )
        } catch {
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
            return
        }
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        guard petLibrarySession.exportSelectedPet(
            reviewed: review,
            options: options,
            isConfirmed: true,
            to: archiveURL
        ) else {
            return
        }

        do {
            petPackageExportDocument = MonglePetPackageDocument(
                data: try Data(contentsOf: archiveURL)
            )
            petPackageExportFileName = review.suggestedFileName
            petPackageExportErrorMessage = nil
            isPresentingPetPackageExporter = true
        } catch {
            petPackageExportDocument = nil
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
        }
    }

    private func handlePetPackageExportResult(
        _ result: Result<URL, Error>
    ) {
        switch result {
        case let .success(destinationURL):
            petPackageExportErrorMessage = nil
            exportedPackageFileName = destinationURL.lastPathComponent
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                petPackageExportErrorMessage = error.localizedDescription
            }
        }
    }

    private func performPendingSharingFollowUp() {
        guard let followUp = pendingSharingFollowUp else {
            return
        }
        pendingSharingFollowUp = nil

        switch followUp {
        case let .export(review, options):
            preparePetPackageExport(for: review, options: options)
        }
    }

    @ViewBuilder
    private func noticeLabel(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.orange)
            .font(.callout)
            .accessibilityIdentifier("monglepet.settings.notice")
    }
}

private struct RemotePetImportControls: View {
    @Environment(\.openURL) private var openURL
    @Binding var urlText: String
    let isImporting: Bool
    let isBusy: Bool
    let errorMessage: String?
    let catalogURL: URL
    let onInputChange: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MonglePet 웹에서 원하는 펫을 찾아보세요.")
                .font(.callout)
            Text("펫 상세 화면에서 앱으로 가져오거나 주소를 복사할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                openURL(catalogURL)
            } label: {
                Label("펫 보러가기", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("monglepet.settings.browseWebPets")
        }

        Divider()
            .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
            Text("주소로 직접 가져오기")
                .font(.subheadline.weight(.medium))
            Text("MonglePet 펫 상세 주소가 있다면 아래에 붙여 넣으세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "펫 상세 주소를 붙여 넣으세요",
                text: $urlText
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(onImport)
            .onChange(of: urlText) {
                if !isImporting {
                    onInputChange()
                }
            }
            .accessibilityLabel("웹 펫 주소")
            .accessibilityIdentifier("monglepet.settings.remotePetURL")

            Button(action: onImport) {
                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("펫 정보를 확인하는 중…")
                    }
                } else {
                    Label(
                        errorMessage == nil ? "주소에서 가져오기" : "다시 시도",
                        systemImage: "link.badge.plus"
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(isBusy || trimmedURLText.isEmpty)
            .accessibilityIdentifier(
                "monglepet.settings.importRemotePackage"
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "monglepet.settings.remoteImportError"
                    )

                Text("주소를 수정하거나 연결 상태를 확인한 뒤 다시 시도할 수 있습니다. 오류가 있는 파일은 설치되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedURLText: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PetAnimationSelectionRow: View {
    let motionID: String
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(motionID)
                .lineLimit(1)
            Spacer()
            if isDefault {
                Text("기본")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: 32,
            alignment: .leading
        )
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct PetAnimationSelectionButton: View {
    let motionID: String
    let isDefault: Bool
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PetAnimationSelectionRow(
                motionID: motionID,
                isDefault: isDefault,
                isSelected: isSelected
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PetAnimationListView: View {
    let motions: [PetMotion]
    let defaultMotionID: String
    let selectedMotionID: String
    let height: CGFloat
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(motions) { motion in
                    PetAnimationSelectionButton(
                        motionID: motion.id,
                        isDefault: motion.id == defaultMotionID,
                        isSelected: motion.id == selectedMotionID,
                        accessibilityLabel: motion.id == defaultMotionID
                            ? "\(motion.id), 기본 애니메이션"
                            : motion.id
                    ) {
                        onSelect(motion.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
        }
        .frame(height: height)
        .background(
            .quaternary.opacity(0.24),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: 1
                )
        }
        .accessibilityIdentifier("monglepet.settings.petAnimations")
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var loginLaunchSettings: LoginLaunchSettings

    var body: some View {
        Form {
            if let loadNotice = settingsSession.loadNotice {
                noticeLabel(
                    loadNotice,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            if let saveErrorMessage = settingsSession.saveErrorMessage {
                noticeLabel(
                    saveErrorMessage,
                    systemImage: "xmark.circle.fill"
                )
            }

            Section("앱 실행") {
                Toggle(
                    "로그인 시 MonglePet 자동 실행",
                    isOn: loginLaunchBinding
                )
                .accessibilityIdentifier(
                    "monglepet.settings.launchAtLogin"
                )

                loginLaunchStatusLabel

                if loginLaunchSettings.requiresApproval {
                    Button("로그인 항목 설정 열기") {
                        loginLaunchSettings.openSystemSettings()
                    }
                    .accessibilityIdentifier(
                        "monglepet.settings.openLoginItems"
                    )
                }

                if let errorMessage = loginLaunchSettings.errorMessage {
                    noticeLabel(
                        errorMessage,
                        systemImage: "xmark.circle.fill"
                    )
                }
            }

            Section("앱 정보") {
                LabeledContent(
                    "버전",
                    value: MonglePetAppVersion.current.displayText
                )
                .accessibilityIdentifier("monglepet.settings.appVersion")

                Text("펫 패키지 호환성은 이 앱 버전을 기준으로 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loginLaunchSettings.refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginLaunchSettings.refresh()
        }
    }

    private var loginLaunchBinding: Binding<Bool> {
        Binding(
            get: { loginLaunchSettings.isRequestedEnabled },
            set: { loginLaunchSettings.setEnabled($0) }
        )
    }

    @ViewBuilder
    private var loginLaunchStatusLabel: some View {
        switch loginLaunchSettings.status {
        case .notRegistered:
            Text("초기에는 꺼져 있으며 원할 때 직접 켤 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .enabled:
            Label(
                "다음 로그인부터 MonglePet이 자동으로 실행됩니다.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .requiresApproval:
            Label(
                "macOS 승인이 필요합니다. 로그인 항목 설정에서 MonglePet을 허용해 주세요.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier(
                "monglepet.settings.loginApprovalRequired"
            )
        case .notFound:
            Label(
                "아직 로그인 항목 등록 기록이 없습니다. 켜면 새로 등록합니다.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "monglepet.settings.loginItemUnavailable"
            )
        }
    }

    @ViewBuilder
    private func noticeLabel(
        _ message: String,
        systemImage: String
    ) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.orange)
            .font(.callout)
            .accessibilityIdentifier("monglepet.settings.notice")
    }
}

nonisolated struct MonglePetPackageDocument: FileDocument {
    static let contentType = UTType(
        filenameExtension: "monglepet",
        conformingTo: .zip
    ) ?? .zip

    static var readableContentTypes: [UTType] {
        [contentType]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum PetSharingFollowUp {
    case export(PetPackageShareReview, PetPackageShareOptions)
}

private struct PetImportAction {
    let review: PetPackageImportReview
}

private struct PetPackageImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let review: PetPackageImportReview
    let allowsInstallation: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("펫 추가")
                            .font(.title2.weight(.semibold))
                        Text("펫과 제작자가 구성한 행동·이동·말풍선 설정을 함께 추가합니다. 추가한 뒤 모든 설정을 자유롭게 변경할 수 있습니다.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("펫 정보")
                            .font(.headline)
                        Grid(
                            alignment: .leading,
                            horizontalSpacing: 20,
                            verticalSpacing: 8
                        ) {
                            informationRow("펫 이름", value: review.metadata.displayName)
                            informationRow("버전", value: review.metadata.version)
                            informationRow("제작자", value: review.metadata.author)
                            informationRow("애니메이션", value: "\(review.definition.motions.count)개")
                        }
                        .padding(12)
                        .background(
                            .quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }

                    compatibilitySection
                    recommendedProfileSection

                    Text("가져오면 독립된 설정을 가진 새 펫으로 내 펫에 추가됩니다. 같은 펫을 다시 가져와도 기존 펫과 설정은 바뀌지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("펫 추가") {
                    onInstall()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!review.canInstall || !allowsInstallation)
                .accessibilityIdentifier("monglepet.import.addPet")
            }
            .padding(16)
        }
        .frame(width: 560)
        .frame(minHeight: 440, maxHeight: 680)
        .accessibilityIdentifier("monglepet.import.review")
    }

    @ViewBuilder
    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MonglePet 호환성")
                .font(.headline)

            if let compatibility = review.compatibility {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 20,
                    verticalSpacing: 8
                ) {
                    informationRow(
                        "현재 앱",
                        value: review.currentMonglePetVersion.description
                    )
                    informationRow(
                        "제작 앱",
                        value: compatibility.createdWithMonglePetVersion?.description
                            ?? "정보 없음"
                    )
                    informationRow(
                        "최소 앱",
                        value: compatibility.minimumMonglePetVersion?.description
                            ?? "정보 없음"
                    )
                }
                .padding(12)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            } else {
                Label(
                    "이전 형식의 패키지로 앱 호환 버전 정보가 없습니다.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }

            switch review.effectiveCompatibilityAssessment {
            case .compatible:
                if review.compatibility != nil {
                    Label(
                        "현재 MonglePet 버전에서 설치할 수 있습니다.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            case let .createdWithNewerVersion(createdWithVersion):
                Label(
                    "MonglePet \(createdWithVersion.description)에서 만든 펫입니다. 일부 표현이 다를 수 있지만 설치할 수 있습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            case let .updateRecommended(requiredVersion):
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "MonglePet \(requiredVersion.description) 이상으로 업데이트를 권장합니다. 지금도 설치할 수 있지만 일부 기능이 적용되지 않거나 다르게 보일 수 있습니다.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("monglepet.import.updateRecommended")

                    Button {
                        openURL(
                            URL(string: "https://mapleroom.kr/monglepet/download")!
                        )
                    } label: {
                        Label(
                            "MonglePet 다운로드 페이지",
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    .accessibilityIdentifier("monglepet.import.openDownloadPage")
                }
            }
        }
    }

    @ViewBuilder
    private var recommendedProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("펫별 표시·평상시 행동·규칙·이동·말풍선 설정")
                .font(.headline)

            if let profile = review.recommendedProfile {
                RecommendedProfileSummaryView(
                    summary: RecommendedProfileSummary(profile: profile)
                )

                Text("제작자가 구성한 표시·행동·이동·말풍선 설정이 이 펫에 자동으로 적용됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let issue = review.recommendedProfileIssue {
                Label(
                    "제작자 설정은 적용할 수 없지만 펫은 안전한 기본 설정으로 추가할 수 있습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Text(issue.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "이 펫에는 제작자 설정이 포함되어 있지 않습니다. 추가한 뒤 원하는 방식으로 설정할 수 있습니다.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }

            if !allowsInstallation {
                Label(
                    "현재 설정 파일을 보호하기 위해 펫 추가가 비활성화되어 있습니다.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func informationRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

}


private struct PetPackageShareReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let review: PetPackageShareReview
    let onExport: (PetPackageShareOptions) -> Void

    @State private var isSharingRightsConfirmed = false
    @State private var includesApplicationRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("공유 내용 확인")
                            .font(.title2.weight(.semibold))
                        Text("저장할 `.monglepet` 파일에 포함할 내용을 선택합니다.")
                            .foregroundStyle(.secondary)
                    }

                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 20,
                        verticalSpacing: 10
                    ) {
                        shareInformationRow("펫 이름", value: review.displayName)
                        shareInformationRow("버전", value: review.version)
                        shareInformationRow("제작자", value: review.author)
                    }
                    .padding(12)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                    sharedContentOptions

                    Toggle(
                        "이 펫과 이미지 자산을 게시하거나 공유할 권한이 있음을 확인합니다.",
                        isOn: $isSharingRightsConfirmed
                    )
                    .accessibilityIdentifier(
                        "monglepet.share.rightsConfirmation"
                    )

                    Text(
                        "공유한 콘텐츠의 권리와 책임은 게시자에게 있으며, 받는 사용자는 자신의 펫으로 가져와 편집할 수 있습니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }

                Button("저장 위치 선택…") {
                    onExport(
                        PetPackageShareOptions(
                            includesApplicationRules:
                                includesApplicationRules
                        )
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !isSharingRightsConfirmed
                        || review.recommendedProfile == nil
                )
                .accessibilityIdentifier("monglepet.share.chooseDestination")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
        .frame(minHeight: 480, maxHeight: 680)
        .accessibilityIdentifier("monglepet.share.review")
    }

    private var sharedContentOptions: some View {
        GroupBox("내보낼 내용") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "펫 정보, 미리보기와 등록된 애니메이션",
                    systemImage: "photo.on.rectangle.angled"
                )

                Divider()

                Label(
                    "펫별 표시·평상시 행동·규칙·이동·말풍선 설정 전체",
                    systemImage: "checkmark.circle.fill"
                )
                .accessibilityIdentifier(
                    "monglepet.share.includeRecommendedProfile"
                )

                if let issue = review.recommendedProfileIssue {
                    Label(
                        "현재 설정은 포함할 수 없습니다: \(issue)",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if review.recommendedProfile == nil {
                    Text("선택한 설치 펫에 공유할 평상시 행동·규칙·이동·말풍선 제작자 설정이 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    recommendedProfileSummary
                    applicationRuleOptions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var recommendedProfileSummary: some View {
        if let profile = includesApplicationRules
            ? review.recommendedProfileWithApplicationRules
            : review.recommendedProfile {
            RecommendedProfileSummaryView(
                summary: RecommendedProfileSummary(profile: profile)
            )
            .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private var applicationRuleOptions: some View {
        if review.applicationRuleCount > 0 {
            Divider()

            Toggle(
                "앱 사용 규칙 \(review.applicationRuleCount)개 포함",
                isOn: $includesApplicationRules
            )
            .disabled(review.recommendedProfileWithApplicationRules == nil)
            .accessibilityIdentifier(
                "monglepet.share.includeApplicationRules"
            )

            if let issue = review.applicationRulesIssue {
                Label(
                    "앱 사용 규칙은 포함할 수 없습니다: \(issue)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text(
                    includesApplicationRules
                        ? "포함할 앱 식별자: "
                            + review.applicationBundleIdentifiers.joined(
                                separator: ", "
                            )
                        : "앱 사용 규칙은 기본적으로 포함하지 않습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private func shareInformationRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct RecommendedProfileSummaryView: View {
    let summary: RecommendedProfileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 16,
                verticalSpacing: 6
            ) {
                informationRow(
                    "평상시 행동 방식",
                    value: stationaryBehaviorModeName
                )
                informationRow(
                    behaviorSelectionLabel,
                    value: behaviorSelectionDescription
                )
                informationRow(
                    "행동 루틴",
                    value: "\(summary.sequences.count)개"
                )
                informationRow(
                    "조건 규칙",
                    value: summary.conditionRuleDescription
                )
                informationRow(
                    "규칙 우선순위",
                    value: summary.automaticRulePriorityDescription
                )
                informationRow(
                    "이동 방식",
                    value: movementModeName(summary.movement.mode)
                )
                if summary.includesDisplaySettings {
                    informationRow(
                        "펫 표시 · 크기/불투명도",
                        value: "\(Int(summary.display.scalePercent.rounded()))% · 불투명도 \(Int((summary.display.opacity * 100).rounded()))%"
                    )
                    informationRow(
                        "펫 표시 · 클릭 통과",
                        value: usageName(summary.display.clickThrough)
                    )
                    informationRow(
                        "펫 표시 · 포인터 겹침",
                        value: summary.display.pointerOverlapFadeEnabled
                            ? "사용 · \(Int((summary.display.pointerOverlapOpacity * 100).rounded()))%"
                            : "사용 안 함"
                    )
                    informationRow(
                        "펫 표시 · 픽셀 방식",
                        value: usageName(summary.display.pixelArtRendering)
                    )
                } else {
                    informationRow(
                        "펫 표시",
                        value: "구형 패키지 · 현재 표시 설정 유지"
                    )
                }
                informationRow(
                    "쓰다듬기",
                    value: summary.movement.mode == .cursorAvoiding
                        ? "도망가기 중 사용 안 함 · 저장값 "
                            + (summary.pettingMotionID.map(
                                summary.behaviorDisplayName(for:)
                            ) ?? "지정 안 함")
                        : summary.pettingMotionID.map(
                            summary.behaviorDisplayName(for:)
                        )
                            ?? "지정 안 함"
                )
                informationRow(
                    "말풍선",
                    value: summary.speech.isEnabled
                        ? "사용 · \(summary.speech.theme.colorStyle.displayName) 테마"
                        : "사용 안 함 · \(summary.speech.theme.colorStyle.displayName) 테마"
                )
                informationRow(
                    "말풍선 위치",
                    value:
                        "\(summary.speech.placement.preferredPosition.displayName) · "
                        + "좌우 \(Int(summary.speech.placement.horizontalOffset.rounded()))pt · "
                        + "간격 \(Int(summary.speech.placement.gap.rounded()))pt"
                )
                informationRow(
                    "행동 대사",
                    value:
                        "\(summary.speech.behaviorPhrases.count)개 · "
                        + "전환 시 \(summary.speech.behaviorChangePolicy.displayName)"
                )
                informationRow(
                    "주기 대사",
                    value: summary.speech.periodicIsEnabled
                        ? "\(summary.speech.periodicPhrases.count)개 · "
                            + "\(summary.speech.periodicOrder.displayName) · "
                            + speechIntervalDescription
                        : "사용 안 함 · \(summary.speech.periodicPhrases.count)개"
                )
            }

            DisclosureGroup("행동 루틴 상세") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.sequences, id: \.id) { sequence in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                sequence.displayName
                            )
                                .font(.caption.weight(.semibold))
                            Text("단계 반복 횟수는 한 순환에 적용 · 전체 반복은 사용 문맥에 따라 결정")
                            .foregroundStyle(.secondary)
                            ForEach(
                                Array(sequence.steps.enumerated()),
                                id: \.offset
                            ) { index, step in
                                Text(
                                    "\(index + 1). \(BuiltInBehaviorPresets.motionDisplayName(for: step.motionID)) × \(step.repeatCount)"
                                )
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("조건 규칙 상세") {
                VStack(alignment: .leading, spacing: 8) {
                    if summary.automaticRules.isEmpty {
                        Text("포함된 조건 규칙이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.automaticRules, id: \.id) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ruleConditionText(rule.condition))
                                    .textSelection(.enabled)
                                Text(
                                    "\(rule.isEnabled ? "사용" : "사용 안 함") · \(summary.behaviorDisplayName(for: rule.sequenceID))"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("이동 설정 상세") {
                VStack(alignment: .leading, spacing: 6) {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 14,
                        verticalSpacing: 5
                    ) {
                        informationRow(
                            "따라가기 · 속도",
                            value: pointsPerSecond(
                                summary.movement.cursorFollowing.speed
                            )
                        )
                        informationRow(
                            "따라가기 · 마우스 거리",
                            value: points(
                                summary.movement.cursorFollowing.cursorDistance
                            )
                        )
                        informationRow(
                            "따라가기 · 정지 반경",
                            value: points(
                                summary.movement.cursorFollowing.stopRadius
                            )
                        )
                        informationRow(
                            "자유 이동 · 속도",
                            value: pointsPerSecond(
                                summary.movement.freeRoaming.speed
                            )
                        )
                        informationRow(
                            "자유 이동 · 정지 반경",
                            value: points(
                                summary.movement.freeRoaming.stopRadius
                            )
                        )
                        informationRow(
                            "자유 이동 · 머무는 시간",
                            value: dwellDescription(
                                summary.movement.freeRoaming
                            )
                        )
                        informationRow(
                            "자유 이동 · 활성 앱 창 우선",
                            value: usageName(
                                summary.movement.freeRoaming
                                    .prefersFrontmostWindow
                            )
                        )
                        informationRow(
                            "도망가기 · 감지 거리",
                            value: points(
                                summary.movement.cursorAvoiding
                                    .detectionDistance
                            )
                        )
                        informationRow(
                            "도망가기 · 속도",
                            value: pointsPerSecond(
                                summary.movement.cursorAvoiding.speed
                            )
                        )
                        informationRow(
                            "도망가기 · 정지 반경",
                            value: points(
                                summary.movement.cursorAvoiding.stopRadius
                            )
                        )
                        informationRow(
                            "도망가기 · 평상시",
                            value: summary.movement.cursorAvoiding.idleBehavior
                                == .stationary
                                ? "가만히 있기"
                                : "자유 이동"
                        )
                        informationRow(
                            "도망가기 평상시 · 속도",
                            value: pointsPerSecond(
                                summary.movement.cursorAvoiding
                                    .idleFreeRoaming.speed
                            )
                        )
                        informationRow(
                            "도망가기 평상시 · 정지 반경",
                            value: points(
                                summary.movement.cursorAvoiding
                                    .idleFreeRoaming.stopRadius
                            )
                        )
                        informationRow(
                            "도망가기 평상시 · 머무는 시간",
                            value: dwellDescription(
                                summary.movement.cursorAvoiding
                                    .idleFreeRoaming
                            )
                        )
                        informationRow(
                            "도망가기 평상시 · 활성 앱 창 우선",
                            value: usageName(
                                summary.movement.cursorAvoiding
                                    .idleFreeRoaming.prefersFrontmostWindow
                            )
                        )
                    }

                    Divider()

                    movementAnimationSummary(
                        title: "마우스 따라가기",
                        systemImage: "cursorarrow",
                        isCurrent:
                            summary.movement.mode == .cursorFollowing,
                        animation:
                            summary.movement.cursorFollowing.animation
                    )

                    Divider()

                    movementAnimationSummary(
                        title: "자유 이동",
                        systemImage: "arrow.triangle.2.circlepath",
                        isCurrent: summary.movement.mode == .freeRoaming,
                        animation: summary.movement.freeRoaming.animation
                    )

                    Divider()

                    movementAnimationSummary(
                        title: "마우스 도망가기",
                        systemImage: "figure.run",
                        isCurrent:
                            summary.movement.mode == .cursorAvoiding,
                        animation:
                            summary.movement.cursorAvoiding.animation
                    )

                    Divider()

                    movementAnimationSummary(
                        title: "도망가기 평상시 자유 이동",
                        systemImage: "figure.walk",
                        isCurrent: summary.movement.mode == .cursorAvoiding
                            && summary.movement.cursorAvoiding.idleBehavior
                                == .freeRoaming,
                        animation: summary.movement.cursorAvoiding
                            .idleFreeRoaming.animation
                    )
                }
                .padding(.top, 6)
            }

            Label(
                "화면 위치·모니터·모든 펫 공통 이동 범위·깨움 상태·로그인 실행은 기기 전용 값이라 이 패키지에 포함되지 않습니다.",
                systemImage: "desktopcomputer"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(12)
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @ViewBuilder
    private func movementAnimationSummary(
        title: String,
        systemImage: String,
        isCurrent: Bool,
        animation: MovementAnimationSettings
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                if isCurrent {
                    Text("현재 사용")
                        .foregroundStyle(.tint)
                        .font(.caption2.weight(.semibold))
                }

                Text(animationStyleName(animation))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        .quaternary,
                        in: Capsule()
                    )
            }

            Grid(
                alignment: .leading,
                horizontalSpacing: 14,
                verticalSpacing: 5
            ) {
                informationRow(
                    "기본 이동",
                    value: animation.fallbackMotionID.map(
                        summary.behaviorDisplayName(for:)
                    )
                        ?? "기존 행동 유지"
                )
                if animation.usesDirectionalMotions {
                    ForEach(displayedDirections(for: animation), id: \.self) {
                        direction in
                        informationRow(
                            directionLabel(direction),
                            value: directionMotionDescription(
                                direction,
                                animation: animation
                            )
                        )
                    }
                }
            }
        }
    }

    private var speechIntervalDescription: String {
        let seconds =
            summary.speech.periodicIntervalMilliseconds / 1_000
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "\(seconds / 60)분 간격"
        }
        return "\(seconds)초 간격"
    }

    private var stationaryBehaviorModeName: String {
        switch summary.stationaryBehaviorMode {
        case .fixed:
            "하나 선택"
        case .random:
            "랜덤 선택"
        }
    }

    private var behaviorSelectionLabel: String {
        summary.stationaryBehaviorMode == .random
            ? "랜덤 행동"
            : "평상시 행동"
    }

    private var behaviorSelectionDescription: String {
        switch summary.stationaryBehaviorMode {
        case .fixed:
            summary.stationarySequenceID.map(
                summary.behaviorDisplayName(for:)
            ) ?? "기본 행동"
        case .random:
            summary.randomSequenceIDs.isEmpty
                ? "기본 행동"
                : "\(summary.randomSequenceIDs.count)개 · "
                    + summary.randomSequenceIDs
                        .map(summary.behaviorDisplayName(for:))
                        .joined(separator: ", ")
        }
    }

    private func dwellDescription(
        _ roaming: FreeRoamingMovementSettings
    ) -> String {
        let maximum = dwellText(roaming.dwellMilliseconds)
        guard roaming.randomizesDwell else {
            return maximum
        }
        return "\(dwellText(roaming.dwellMinimumMilliseconds))~\(maximum) 랜덤"
    }

    private func animationStyleName(
        _ animation: MovementAnimationSettings
    ) -> String {
        guard animation.usesDirectionalMotions else {
            return "공통 하나"
        }
        return animation.usesDiagonalMotions
            ? "방향별 8방향"
            : "방향별 4방향"
    }

    private func directionMotionDescription(
        _ direction: MovementDirection,
        animation: MovementAnimationSettings
    ) -> String {
        if let motionID = animation.directionMotionIDs[direction] {
            return summary.behaviorDisplayName(for: motionID)
        }
        let availableDirections = animation.usesDiagonalMotions
            ? MovementDirection.cardinalCases
                + MovementDirection.diagonalCases
            : MovementDirection.cardinalCases
        if availableDirections.contains(where: {
            $0 != direction
                && animation.directionMotionIDs[$0] != nil
        }) {
            return "가까운 사용 방향 자동 선택"
        }
        if let fallbackMotionID = animation.fallbackMotionID {
            return "기본 이동 사용 · \(summary.behaviorDisplayName(for: fallbackMotionID))"
        }
        return "기존 행동 유지"
    }

    private func displayedDirections(
        for animation: MovementAnimationSettings
    ) -> [MovementDirection] {
        animation.usesDiagonalMotions
            ? MovementDirection.cardinalCases
                + MovementDirection.diagonalCases
            : MovementDirection.cardinalCases
    }

    private func informationRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func points(_ value: Double) -> String {
        "\(Int(value.rounded())) pt"
    }

    private func pointsPerSecond(_ value: Double) -> String {
        "\(Int(value.rounded())) pt/s"
    }

    private func usageName(_ isEnabled: Bool) -> String {
        isEnabled ? "사용" : "사용 안 함"
    }

    private func movementModeName(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed:
            "위치 고정"
        case .cursorFollowing:
            "마우스 따라가기"
        case .freeRoaming:
            "자유 이동"
        case .cursorAvoiding:
            "마우스 도망가기"
        }
    }

    private func directionLabel(_ direction: MovementDirection) -> String {
        switch direction {
        case .left:
            "왼쪽"
        case .right:
            "오른쪽"
        case .up:
            "위쪽"
        case .down:
            "아래쪽"
        case .upLeft:
            "왼쪽 위"
        case .upRight:
            "오른쪽 위"
        case .downLeft:
            "왼쪽 아래"
        case .downRight:
            "오른쪽 아래"
        }
    }

    private func ruleConditionText(_ condition: RuleCondition) -> String {
        switch condition {
        case let .application(bundleIdentifier):
            "앱: \(bundleIdentifier)"
        case let .idleAtLeast(milliseconds):
            "입력 없음: \(dwellText(milliseconds)) 이상"
        case .unsupported:
            "지원하지 않는 조건"
        }
    }

    private func dwellText(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1_000
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(seconds / 60))분"
        }
        if seconds.rounded() == seconds {
            return "\(Int(seconds))초"
        }
        return String(format: "%.1f초", seconds)
    }
}

private enum UserPetEditorMode: String, Identifiable {
    case create
    case addAnimation

    var id: String { rawValue }
}

private enum AnimationBehaviorLinkMode: String, CaseIterable, Identifiable {
    case none
    case newBehavior
    case existingBehavior

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "연결 안 함"
        case .newBehavior:
            "새 행동 만들기"
        case .existingBehavior:
            "기존 행동에 추가"
        }
    }
}

private func effectiveBehaviorName(
    enteredName: String,
    animationID: String
) -> String {
    let normalizedName = enteredName.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    return normalizedName.isEmpty ? animationID : normalizedName
}

private func animationBehaviorLinkValidationMessage(
    mode: AnimationBehaviorLinkMode,
    newBehaviorName: String,
    existingBehaviorID: String,
    animationID: String,
    sequences: [BehaviorSequence]
) -> String? {
    switch mode {
    case .none:
        return nil
    case .newBehavior:
        let behaviorName = effectiveBehaviorName(
            enteredName: newBehaviorName,
            animationID: animationID
        )
        guard !behaviorName.isEmpty else {
            return "애니메이션 이름 또는 새 행동 이름을 입력해 주세요."
        }
        guard sequences.count < AppSettingsLimits.maximumSequences else {
            return "행동은 최대 100개까지 만들 수 있습니다."
        }
        if sequences.contains(where: {
            $0.displayName.compare(
                behaviorName,
                options: .caseInsensitive
            ) == .orderedSame
        }) {
            return "같은 이름의 행동이 이미 있습니다."
        }
        return nil
    case .existingBehavior:
        guard let sequence = sequences.first(where: {
            $0.id == existingBehaviorID
        }) else {
            return "애니메이션을 추가할 행동을 선택해 주세요."
        }
        guard sequence.steps.count < AppSettingsLimits.maximumStepsPerSequence else {
            return "선택한 행동에는 단계를 더 추가할 수 없습니다."
        }
        return nil
    }
}

private struct AnimationBehaviorLinkSection: View {
    @Binding var mode: AnimationBehaviorLinkMode
    @Binding var newBehaviorName: String
    @Binding var existingBehaviorID: String
    let animationID: String
    let sequences: [BehaviorSequence]
    let currentBehaviorNames: [String]?

    var body: some View {
        GroupBox("행동 연결") {
            VStack(alignment: .leading, spacing: 12) {
                if let currentBehaviorNames {
                    LabeledContent("현재 사용 중") {
                        Text(
                            currentBehaviorNames.isEmpty
                                ? "없음"
                                : currentBehaviorNames.joined(separator: ", ")
                        )
                        .foregroundStyle(
                            currentBehaviorNames.isEmpty ? .secondary : .primary
                        )
                        .multilineTextAlignment(.trailing)
                    }
                }

                Picker("저장 후", selection: $mode) {
                    ForEach(AnimationBehaviorLinkMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("monglepet.animationBehaviorLink.mode")

                switch mode {
                case .none:
                    Text("애니메이션만 저장하며 행동 구성은 바꾸지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .newBehavior:
                    TextField(
                        animationID.isEmpty ? "행동 이름" : animationID,
                        text: $newBehaviorName
                    )
                    .accessibilityIdentifier(
                        "monglepet.animationBehaviorLink.newBehaviorName"
                    )
                    Text("비워 두면 애니메이션 이름으로 한 단계 행동을 만듭니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .existingBehavior:
                    if sequences.isEmpty {
                        Text("추가할 수 있는 행동이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("추가할 행동", selection: $existingBehaviorID) {
                            ForEach(sequences) { sequence in
                                Text(sequence.displayName).tag(sequence.id)
                            }
                        }
                        .accessibilityIdentifier(
                            "monglepet.animationBehaviorLink.existingBehavior"
                        )

                        if selectedSequenceContainsAnimation {
                            Label(
                                "이 행동에 같은 애니메이션이 이미 있습니다. 저장하면 마지막 단계에 한 번 더 추가됩니다.",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("선택한 행동의 마지막 단계에 1회 재생으로 추가합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }

    var validationMessage: String? {
        animationBehaviorLinkValidationMessage(
            mode: mode,
            newBehaviorName: newBehaviorName,
            existingBehaviorID: existingBehaviorID,
            animationID: animationID,
            sequences: sequences
        )
    }

    private var selectedSequence: BehaviorSequence? {
        sequences.first { $0.id == existingBehaviorID }
    }

    private var selectedSequenceContainsAnimation: Bool {
        guard !animationID.isEmpty else {
            return false
        }
        return selectedSequence?.steps.contains {
            $0.motionID == animationID
        } ?? false
    }
}

private struct UserPetAnimationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: UserPetEditorMode
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var settingsSession: AppSettingsSession
    let prepareForSaving: () -> Bool
    let duplicationSourceAnimationID: String?

    @State private var petName = ""
    @State private var version = "1.0.0"
    @State private var author = "MonglePet 사용자"
    @State private var petDescription = "MonglePet에서 사용자가 만든 펫입니다."
    @State private var animationName = ""
    @State private var frameDurationMilliseconds = 450
    @State private var loops = true
    @State private var frames: [UserPetAnimationFrameDraft] = []
    @State private var selectedFrameID: UUID?
    @State private var spriteSheetImport: SpriteSheetImportPresentation?
    @State private var pngCropImport: PNGFrameCropPresentation?
    @State private var existingFrameImport: ExistingPetFramePickerPresentation?
    @State private var imageImportErrorMessage: String?
    @State private var behaviorLinkMode: AnimationBehaviorLinkMode = .none
    @State private var newBehaviorName = ""
    @State private var existingBehaviorID = ""
    @State private var behaviorLinkErrorMessage: String?

    init(
        mode: UserPetEditorMode,
        petLibrarySession: PetLibrarySession,
        settingsSession: AppSettingsSession,
        prepareForSaving: @escaping () -> Bool,
        duplicating motion: PetMotion? = nil
    ) {
        self.mode = mode
        self.petLibrarySession = petLibrarySession
        self.settingsSession = settingsSession
        self.prepareForSaving = prepareForSaving
        duplicationSourceAnimationID = motion?.id
        if let motion {
            _animationName = State(initialValue: "\(motion.id) 사본")
            _loops = State(initialValue: motion.loops)
            let sourceDrafts = UserPetAnimationDraftFactory.existing(
                item: petLibrarySession.selectedItem,
                motion: motion
            )
            let frameDrafts: [UserPetAnimationFrameDraft] = sourceDrafts
                .enumerated()
                .flatMap { index, draft -> [UserPetAnimationFrameDraft] in
                    guard let image = draft.previewImage else { return [] }
                    return UserPetAnimationDraftFactory.new(
                        images: [
                            UserPetSourceImage(
                                displayName: "\(motion.id) \(index + 1)번 프레임",
                                image: image
                            )
                        ],
                        durationMilliseconds: draft.durationMilliseconds
                    )
                }
            _frames = State(initialValue: frameDrafts)
            _selectedFrameID = State(initialValue: frameDrafts.first?.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editorTitle)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .create {
                        petInformationSection
                    }
                    animationInformationSection
                    if mode == .addAnimation {
                        behaviorLinkSection
                    }
                    frameEditorSection

                    Text("개별 프레임은 512×512 px 투명 PNG를 권장합니다. 정적 PNG·WebP 스프라이트 시트도 경계를 확인한 뒤 여러 프레임으로 가져올 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let imageImportErrorMessage {
                        Label(imageImportErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    if let behaviorLinkErrorMessage {
                        Label(
                            behaviorLinkErrorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

                    if let errorMessage = petLibrarySession.errorMessage {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button(mode == .create ? "펫 만들기" : "추가") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.userPet.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 680)
        .onAppear {
            if mode == .create {
                animationName = "기본"
            }
            selectFirstBehaviorIfNeeded()
        }
        .sheet(item: $spriteSheetImport) { presentation in
            SpriteSheetImportView(document: presentation.document) { images in
                appendSpriteImages(images)
            }
        }
        .sheet(item: $pngCropImport) { presentation in
            PNGFrameCropEditorView(images: presentation.images) { images in
                appendSpriteImages(images)
            }
        }
        .sheet(item: $existingFrameImport) { presentation in
            ExistingPetFramePickerView(
                petName: presentation.petName,
                groups: presentation.groups
            ) { selections in
                appendExistingFrames(selections)
            }
        }
    }

    private var editorTitle: String {
        if mode == .create {
            return "새 펫 만들기"
        }
        if duplicationSourceAnimationID != nil {
            return "애니메이션 복제"
        }
        return "펫 애니메이션 추가"
    }

    private var petInformationSection: some View {
        GroupBox("펫 정보") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("펫 이름")
                    TextField("펫 이름", text: $petName)
                        .accessibilityIdentifier("monglepet.userPet.petName")
                }

                GridRow {
                    fieldLabel("제작자")
                    TextField("제작자", text: $author)
                        .accessibilityIdentifier("monglepet.userPet.author")
                }

                GridRow {
                    fieldLabel("버전")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("버전", text: $version)
                            .accessibilityIdentifier("monglepet.userPet.version")
                        if !UserPetContentVersion.isValid(version) {
                            Text(UserPetContentVersion.guidance)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier(
                                    "monglepet.userPet.versionError"
                                )
                        }
                    }
                }

                GridRow {
                    fieldLabel("설명")
                    TextField("설명", text: $petDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("monglepet.userPet.description")
                }
            }
            .padding(8)
        }
    }

    private var animationInformationSection: some View {
        GroupBox("애니메이션 설정") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("이름")
                    TextField("애니메이션 이름", text: $animationName)
                        .accessibilityIdentifier("monglepet.userPet.animationName")
                }

                GridRow {
                    fieldLabel("새 프레임 간격")
                    HStack {
                        FrameDurationInput(
                            milliseconds: $frameDurationMilliseconds,
                            accessibilityIdentifier: "monglepet.userPet.frameDuration"
                        )

                        Text("앞으로 추가할 프레임의 기본값")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    fieldLabel("재생")
                    Toggle("반복 재생", isOn: $loops)
                        .accessibilityIdentifier("monglepet.userPet.loops")
                }
            }
            .padding(8)
        }
    }

    private var behaviorLinkSection: some View {
        AnimationBehaviorLinkSection(
            mode: $behaviorLinkMode,
            newBehaviorName: $newBehaviorName,
            existingBehaviorID: $existingBehaviorID,
            animationID: normalizedAnimationName,
            sequences: settingsSession.settings.sequences,
            currentBehaviorNames: nil
        )
    }

    private var frameEditorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("애니메이션 프레임")
                            .font(.headline)
                        Text("프레임을 선택하면 배율·위치·재생 간격을 개별 편집할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if frames.isEmpty {
                    VStack(alignment: .trailing, spacing: 8) {
                        frameImportMenu
                        ContentUnavailableView(
                            "추가한 프레임이 없습니다.",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("개별 PNG 또는 정적 PNG·WebP 스프라이트 시트를 추가해 주세요.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            EditableAnimationPreviewPanel(
                                frames: $frames,
                                loops: loops,
                                selectedFrameID: selectedFrameID
                            )

                            if let selectedFrameBinding {
                                FramePlacementControls(
                                    frame: selectedFrameBinding,
                                    onDuplicate: duplicateSelectedFrame
                                )
                            }
                        }
                        .frame(width: 260)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("프레임 순서와 간격")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                frameImportMenu
                            }

                            List(selection: $selectedFrameID) {
                                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                                    frameRow(frame, at: index)
                                        .tag(frame.id)
                                }
                            }
                            .frame(minHeight: 320)
                            .accessibilityIdentifier("monglepet.userPet.frames")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(8)
        }
    }

    private var frameImportMenu: some View {
        Menu {
            Button("개별 PNG 추가…") {
                choosePNGs()
            }
            .accessibilityIdentifier("monglepet.userPet.choosePNGs")

            Button("스프라이트 시트에서 추가…") {
                chooseSpriteSheet()
            }
            .accessibilityIdentifier("monglepet.userPet.chooseSpriteSheet")

            if mode == .addAnimation {
                Divider()
                Button("현재 펫 프레임에서 추가…") {
                    chooseExistingFrames()
                }
                .accessibilityIdentifier(
                    "monglepet.userPet.chooseExistingFrames"
                )
            }
        } label: {
            Label(
                frames.isEmpty ? "프레임 선택" : "프레임 추가",
                systemImage: "plus"
            )
        }
        .accessibilityIdentifier(
            "monglepet.userPet.frameImportMenu"
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 88, alignment: .trailing)
    }

    private func frameRow(
        _ frame: UserPetAnimationFrameDraft,
        at index: Int
    ) -> some View {
        HStack(spacing: 8) {
            frameThumbnail(frame)
                .frame(width: 38, height: 38)

            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(frameFilename(frame))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "간격",
                value: durationBinding(for: frame.id),
                format: .number
            )
            .frame(width: 66)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("\(index + 1)번 프레임 간격")

            Text("ms")
                .foregroundStyle(.secondary)

            Button {
                moveFrame(at: index, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == frames.startIndex)
            .accessibilityLabel("위로 이동")

            Button {
                moveFrame(at: index, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == frames.index(before: frames.endIndex))
            .accessibilityLabel("아래로 이동")

            Button {
                duplicateFrame(at: index)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("프레임 복사")

            Button(role: .destructive) {
                removeFrame(id: frame.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("프레임 삭제")
        }
    }

    private var canSave: Bool {
        !animationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !frames.isEmpty
            && frames.allSatisfy { 16...60_000 ~= $0.durationMilliseconds }
            && (mode != .addAnimation || behaviorLinkValidationMessage == nil)
            && (behaviorLinkMode == .none || settingsSession.isWritingEnabled)
            && (mode != .create
                || (!petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && UserPetContentVersion.isValid(version)
                    && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private func choosePNGs() {
        let panel = NSOpenPanel()
        panel.title = "PNG 프레임 선택"
        panel.prompt = "추가"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK else {
            return
        }
        do {
            pngCropImport = PNGFrameCropPresentation(
                images: try PNGFrameImportLoader.load(panel.urls)
            )
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func chooseSpriteSheet() {
        let panel = NSOpenPanel()
        panel.title = "정적 스프라이트 시트 선택"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png, .webP]

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        do {
            let document = try SpriteSheetFrameExtractor().load(at: sourceURL)
            spriteSheetImport = SpriteSheetImportPresentation(document: document)
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func chooseExistingFrames() {
        do {
            let item = petLibrarySession.selectedItem
            existingFrameImport = ExistingPetFramePickerPresentation(
                petName: item.metadata.displayName,
                groups: try ExistingPetFrameLibrary.load(from: item)
            )
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func appendSpriteImages(_ images: [UserPetSourceImage]) {
        let addedFrames = UserPetAnimationDraftFactory.new(
            images: images,
            durationMilliseconds: frameDurationMilliseconds,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
    }

    private func appendExistingFrames(
        _ selections: [ExistingPetFrameSelection]
    ) {
        let addedFrames = UserPetAnimationDraftFactory.reused(
            selections: selections,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
    }

    private func moveFrame(at index: Int, offset: Int) {
        let destination = index + offset
        guard frames.indices.contains(index), frames.indices.contains(destination) else {
            return
        }
        frames.swapAt(index, destination)
    }

    private func duplicateFrame(at index: Int) {
        guard frames.indices.contains(index) else {
            return
        }
        let duplicate = frames[index].duplicated()
        frames.insert(duplicate, at: index + 1)
        selectedFrameID = duplicate.id
    }

    private func duplicateSelectedFrame() {
        guard let selectedFrameID,
              let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
            return
        }
        duplicateFrame(at: index)
    }

    private func removeFrame(id: UUID) {
        frames.removeAll { $0.id == id }
        if selectedFrameID == id {
            selectedFrameID = frames.first?.id
        }
    }

    private func durationBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: {
                frames.first(where: { $0.id == id })?.durationMilliseconds ?? 450
            },
            set: { newValue in
                guard let index = frames.firstIndex(where: { $0.id == id }) else {
                    return
                }
                frames[index].durationMilliseconds = newValue
            }
        )
    }

    private func save() {
        behaviorLinkErrorMessage = nil
        guard mode == .create || prepareForSaving() else {
            return
        }
        let succeeded: Bool
        switch mode {
        case .create:
            succeeded = petLibrarySession.createUserPet(
                UserPetCreationRequest(
                    displayName: petName,
                    animationName: animationName,
                    loops: loops,
                    frames: sourceFrameRequests,
                    version: version,
                    author: author,
                    description: petDescription
                )
            )
        case .addAnimation:
            succeeded = petLibrarySession.addAnimationToSelectedPet(
                UserPetAnimationRequest(
                    animationName: normalizedAnimationName,
                    loops: loops,
                    frames: sourceFrameRequests
                )
            )
        }
        if succeeded {
            if mode == .addAnimation,
               !applyBehaviorLink(animationID: normalizedAnimationName) {
                let linkError = settingsSession.behaviorEditErrorMessage
                    ?? "행동 연결을 저장하지 못했습니다."
                let rolledBack = petLibrarySession.removeSelectedPetAnimation(
                    id: normalizedAnimationName
                )
                behaviorLinkErrorMessage = rolledBack
                    ? "\(linkError) 추가한 애니메이션은 되돌렸습니다."
                    : "\(linkError) 애니메이션은 추가되었을 수 있으니 펫 정보·애니메이션에서 확인해 주세요."
                return
            }
            dismiss()
        }
    }

    private var normalizedAnimationName: String {
        animationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var behaviorLinkValidationMessage: String? {
        animationBehaviorLinkValidationMessage(
            mode: behaviorLinkMode,
            newBehaviorName: newBehaviorName,
            existingBehaviorID: existingBehaviorID,
            animationID: normalizedAnimationName,
            sequences: settingsSession.settings.sequences
        )
    }

    private func selectFirstBehaviorIfNeeded() {
        guard !settingsSession.settings.sequences.contains(where: {
            $0.id == existingBehaviorID
        }) else {
            return
        }
        existingBehaviorID = settingsSession.settings.sequences.first?.id ?? ""
    }

    private func applyBehaviorLink(animationID: String) -> Bool {
        switch behaviorLinkMode {
        case .none:
            return true
        case .newBehavior:
            return settingsSession.addBehaviorSequence(
                named: effectiveBehaviorName(
                    enteredName: newBehaviorName,
                    animationID: animationID
                ),
                initialMotionID: animationID
            )
        case .existingBehavior:
            return settingsSession.addBehaviorStep(
                to: existingBehaviorID,
                motionID: animationID
            )
        }
    }

    private var sourceFrameRequests: [UserPetSourceFrameRequest] {
        frames.compactMap { frame in
            switch frame.source {
            case .existing:
                return nil
            case let .png(url):
                return UserPetSourceFrameRequest(
                    sourceURL: url,
                    durationMilliseconds: frame.durationMilliseconds,
                    placement: frame.placement,
                    flipsHorizontally: frame.flipsHorizontally,
                    flipsVertically: frame.flipsVertically
                )
            case let .image(image):
                return UserPetSourceFrameRequest(
                    image: image,
                    durationMilliseconds: frame.durationMilliseconds,
                    placement: frame.placement,
                    flipsHorizontally: frame.flipsHorizontally,
                    flipsVertically: frame.flipsVertically
                )
            }
        }
    }

    private var selectedFrameBinding: Binding<UserPetAnimationFrameDraft>? {
        guard let selectedFrameID,
              frames.contains(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return Binding(
            get: { frames.first(where: { $0.id == selectedFrameID })! },
            set: { updated in
                guard let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
                    return
                }
                frames[index] = updated
            }
        )
    }

    @ViewBuilder
    private func frameThumbnail(_ frame: UserPetAnimationFrameDraft) -> some View {
        if let image = frame.previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func frameFilename(_ frame: UserPetAnimationFrameDraft) -> String {
        switch frame.source {
        case .existing:
            return "기존 프레임"
        case let .png(url):
            return url.lastPathComponent
        case let .image(image):
            return image.displayName
        }
    }
}

private struct PetCopyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PetLibraryItem
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var displayName: String

    init(
        item: PetLibraryItem,
        petLibrarySession: PetLibrarySession
    ) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        _displayName = State(initialValue: "\(item.metadata.displayName) 사본")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("펫 사본 새로 만들기")
                .font(.title2.weight(.semibold))

            Text("현재 펫은 그대로 보존됩니다. 사본은 독립된 이미지·애니메이션과 설정을 가진 새 펫으로 추가됩니다.")
                .foregroundStyle(.secondary)

            Form {
                TextField("사본 이름", text: $displayName)
                    .accessibilityIdentifier("monglepet.editableCopy.name")

                LabeledContent("원본 펫", value: item.metadata.displayName)
                LabeledContent("제작자", value: item.metadata.author)
                LabeledContent("버전", value: item.metadata.version)
            }
            .formStyle(.grouped)

            Text("애니메이션과 미리보기 자산을 복사하고, 현재 행동·규칙 설정·이동·쓰다듬기·말풍선 설정도 새 펫에 복사합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = petLibrarySession.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("사본 만들기") {
                    createCopy()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.editableCopy.create")
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 420)
    }

    private var canCreate: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createCopy() {
        if petLibrarySession.createEditableCopyOfSelectedPet(displayName: displayName) {
            dismiss()
        }
    }
}

private struct UserPetDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PetLibraryItem
    @ObservedObject var petLibrarySession: PetLibrarySession
    let prepareForSaving: () -> Bool

    @State private var displayName: String
    @State private var version: String
    @State private var author: String
    @State private var petDescription: String
    @State private var defaultMotionID: String

    init(
        item: PetLibraryItem,
        petLibrarySession: PetLibrarySession,
        prepareForSaving: @escaping () -> Bool
    ) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        self.prepareForSaving = prepareForSaving
        _displayName = State(initialValue: item.metadata.displayName)
        _version = State(initialValue: item.metadata.version)
        _author = State(initialValue: item.metadata.author)
        _petDescription = State(initialValue: item.metadata.description ?? "")
        _defaultMotionID = State(initialValue: item.definition.defaultMotionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("펫 정보 수정")
                .font(.title2.weight(.semibold))

            Form {
                LabeledContent("패키지 ID", value: item.metadata.id)
                    .textSelection(.enabled)

                TextField("펫 이름", text: $displayName)
                    .accessibilityIdentifier("monglepet.petDetails.name")

                TextField("제작자", text: $author)
                    .accessibilityIdentifier("monglepet.petDetails.author")

                VStack(alignment: .leading, spacing: 4) {
                    TextField("버전", text: $version)
                        .accessibilityIdentifier("monglepet.petDetails.version")
                    if !UserPetContentVersion.isValid(version) {
                        Text(UserPetContentVersion.guidance)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(
                                "monglepet.petDetails.versionError"
                            )
                    }
                }

                TextField("설명", text: $petDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("monglepet.petDetails.description")

                Picker("기본 애니메이션", selection: $defaultMotionID) {
                    ForEach(item.definition.motions) { motion in
                        Text(motion.id).tag(motion.id)
                    }
                }
                .accessibilityIdentifier("monglepet.petDetails.defaultAnimation")
            }
            .formStyle(.grouped)

            Text("패키지 ID와 설치 항목은 유지됩니다. 저장 전 임시 사본을 전체 검증한 뒤 현재 펫을 교체합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = petLibrarySession.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.petDetails.save")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UserPetContentVersion.isValid(version)
            && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.definition.motion(id: defaultMotionID) != nil
    }

    private func save() {
        guard prepareForSaving() else { return }
        let succeeded = petLibrarySession.updateSelectedPetDetails(
            UserPetDetailsRequest(
                displayName: displayName,
                version: version,
                author: author,
                description: petDescription,
                defaultMotionID: defaultMotionID
            )
        )
        if succeeded {
            dismiss()
        }
    }
}

private struct UserPetAnimationDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let motion: PetMotion
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var settingsSession: AppSettingsSession
    let prepareForSaving: () -> Bool
    let duplicationSourceAnimationID: String?
    let onSaved: (String) -> Void

    @State private var animationName: String
    @State private var loops: Bool
    @State private var frames: [UserPetAnimationFrameDraft]
    @State private var selectedFrameID: UUID?
    @State private var spriteSheetImport: SpriteSheetImportPresentation?
    @State private var pngCropImport: PNGFrameCropPresentation?
    @State private var existingFrameImport: ExistingPetFramePickerPresentation?
    @State private var imageImportErrorMessage: String?
    @State private var frameDurationMilliseconds = 450
    @State private var behaviorLinkMode: AnimationBehaviorLinkMode = .none
    @State private var newBehaviorName = ""
    @State private var existingBehaviorID = ""
    @State private var behaviorLinkErrorMessage: String?

    init(
        item: PetLibraryItem,
        motion: PetMotion,
        petLibrarySession: PetLibrarySession,
        settingsSession: AppSettingsSession,
        prepareForSaving: @escaping () -> Bool,
        duplicationSourceAnimationID: String? = nil,
        onSaved: @escaping (String) -> Void
    ) {
        self.motion = motion
        self.petLibrarySession = petLibrarySession
        self.settingsSession = settingsSession
        self.prepareForSaving = prepareForSaving
        self.duplicationSourceAnimationID = duplicationSourceAnimationID
        self.onSaved = onSaved
        _animationName = State(initialValue: motion.id)
        _loops = State(initialValue: motion.loops)
        let frameDrafts = UserPetAnimationDraftFactory.existing(
            item: item,
            motion: motion
        )
        _frames = State(initialValue: frameDrafts)
        _selectedFrameID = State(initialValue: frameDrafts.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    duplicationSourceAnimationID == nil
                        ? "펫 애니메이션 수정"
                        : "애니메이션 복제본 편집"
                )
                .font(.title2.weight(.semibold))

                if let duplicationSourceAnimationID {
                    Text("원본: \(duplicationSourceAnimationID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                TextField("애니메이션 이름", text: $animationName)
                    .accessibilityIdentifier("monglepet.petAnimation.name")

                Toggle("반복 재생", isOn: $loops)
                    .accessibilityIdentifier("monglepet.petAnimation.loops")

                LabeledContent("새 프레임 간격") {
                    FrameDurationInput(
                        milliseconds: $frameDurationMilliseconds,
                        accessibilityIdentifier: "monglepet.petAnimation.frameDuration"
                    )
                }

                LabeledContent("프레임 수", value: "\(frames.count)")
            }
            .formStyle(.grouped)

            behaviorLinkSection

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("편집 미리보기")
                        .font(.headline)
                        EditableAnimationPreviewPanel(
                            frames: $frames,
                            loops: loops,
                            selectedFrameID: selectedFrameID
                        )
                        .frame(width: 260)
                        .accessibilityLabel("편집 중인 애니메이션 미리보기")

                    if let selectedFrameBinding {
                        FramePlacementControls(
                            frame: selectedFrameBinding,
                            onDuplicate: duplicateSelectedFrame
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("프레임 순서와 간격")
                            .font(.headline)
                        Spacer()
                        frameImportMenu
                    }

                    List {
                        ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                            HStack(spacing: 8) {
                                frameThumbnail(frame)
                                    .frame(width: 38, height: 38)

                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)

                                TextField(
                                    "간격",
                                    value: durationBinding(for: frame.id),
                                    format: .number
                                )
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("\(index + 1)번 프레임 간격")

                                Text("ms")
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    moveFrame(at: index, offset: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == frames.startIndex)
                                .accessibilityLabel("위로 이동")

                                Button {
                                    moveFrame(at: index, offset: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == frames.index(before: frames.endIndex))
                                .accessibilityLabel("아래로 이동")

                                Button {
                                    duplicateFrame(at: index)
                                } label: {
                                    Image(systemName: "plus.square.on.square")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("프레임 복사")

                                Button(role: .destructive) {
                                    removeFrame(id: frame.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(frames.count == 1)
                                .accessibilityLabel("프레임 삭제")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFrameID = frame.id
                            }
                            .background(
                                selectedFrameID == frame.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                    }
                    .frame(minHeight: 190)
                    .accessibilityIdentifier("monglepet.petAnimation.frames")
                }
                .frame(maxWidth: .infinity)
            }

            Text("개별 프레임은 512×512 px 투명 PNG를 권장합니다. 정적 PNG·WebP 스프라이트 시트도 경계를 확인한 뒤 추가할 수 있습니다. 각 프레임 간격은 16~60000ms입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

                }
            }

            editorStatusBanner

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button(
                    duplicationSourceAnimationID == nil
                        ? "저장"
                        : "복제본 저장"
                ) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    saveBlockingMessage != nil
                        || petLibrarySession.isImporting
                )
                .accessibilityIdentifier("monglepet.petAnimation.save")
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 680)
        .onAppear {
            selectFirstBehaviorIfNeeded()
        }
        .sheet(item: $spriteSheetImport) { presentation in
            SpriteSheetImportView(document: presentation.document) { images in
                appendSpriteImages(images)
            }
        }
        .sheet(item: $pngCropImport) { presentation in
            PNGFrameCropEditorView(images: presentation.images) { images in
                appendSpriteImages(images)
            }
        }
        .sheet(item: $existingFrameImport) { presentation in
            ExistingPetFramePickerView(
                petName: presentation.petName,
                groups: presentation.groups
            ) { selections in
                appendExistingFrames(selections)
            }
        }
    }

    private var saveBlockingMessage: String? {
        if normalizedAnimationName.isEmpty {
            return "애니메이션 이름을 입력해 주세요."
        }
        if frames.isEmpty {
            return "저장할 프레임을 한 개 이상 추가해 주세요."
        }
        if !frames.allSatisfy({ 16...60_000 ~= $0.durationMilliseconds }) {
            return "모든 프레임 간격을 16~60000ms 사이로 입력해 주세요."
        }
        if behaviorLinkMode != .none && !settingsSession.isWritingEnabled {
            return "행동을 연결하려면 설정 저장을 사용할 수 있어야 합니다."
        }
        return behaviorLinkValidationMessage
    }

    @ViewBuilder
    private var editorStatusBanner: some View {
        if let message = operationErrorMessage {
            Label(message, systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityIdentifier(
                    "monglepet.petAnimation.operationError"
                )
        } else if let saveBlockingMessage {
            Label(
                saveBlockingMessage,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .accessibilityIdentifier(
                "monglepet.petAnimation.validationMessage"
            )
        }
    }

    private var operationErrorMessage: String? {
        behaviorLinkErrorMessage
            ?? imageImportErrorMessage
            ?? petLibrarySession.errorMessage
    }

    private var behaviorLinkSection: some View {
        AnimationBehaviorLinkSection(
            mode: $behaviorLinkMode,
            newBehaviorName: $newBehaviorName,
            existingBehaviorID: $existingBehaviorID,
            animationID: normalizedAnimationName,
            sequences: settingsSession.settings.sequences,
            currentBehaviorNames: currentBehaviorNames
        )
    }

    private var currentBehaviorNames: [String] {
        settingsSession.settings.sequences.compactMap { sequence in
            sequence.steps.contains { $0.motionID == motion.id }
                ? sequence.displayName
                : nil
        }
    }

    private var frameImportMenu: some View {
        Menu {
            Button("개별 PNG 추가…") {
                choosePNGs()
            }
            .accessibilityIdentifier("monglepet.petAnimation.addFrames")

            Button("스프라이트 시트에서 추가…") {
                chooseSpriteSheet()
            }
            .accessibilityIdentifier("monglepet.petAnimation.addSpriteSheet")

            Divider()
            Button("현재 펫 프레임에서 추가…") {
                chooseExistingFrames()
            }
            .accessibilityIdentifier(
                "monglepet.petAnimation.addExistingFrames"
            )
        } label: {
            Label("프레임 추가", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func frameThumbnail(_ frame: UserPetAnimationFrameDraft) -> some View {
        if let image = frame.previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func durationBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: {
                frames.first(where: { $0.id == id })?.durationMilliseconds ?? 450
            },
            set: { newValue in
                guard let index = frames.firstIndex(where: { $0.id == id }) else {
                    return
                }
                frames[index].durationMilliseconds = newValue
            }
        )
    }

    private var selectedFrameBinding: Binding<UserPetAnimationFrameDraft>? {
        guard let selectedFrameID,
              frames.contains(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return Binding(
            get: {
                frames.first(where: { $0.id == selectedFrameID })!
            },
            set: { updated in
                guard let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
                    return
                }
                frames[index] = updated
            }
        )
    }

    private func choosePNGs() {
        let panel = NSOpenPanel()
        panel.title = "추가할 PNG 프레임 선택"
        panel.prompt = "추가"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK else {
            return
        }
        do {
            pngCropImport = PNGFrameCropPresentation(
                images: try PNGFrameImportLoader.load(panel.urls)
            )
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func chooseSpriteSheet() {
        let panel = NSOpenPanel()
        panel.title = "정적 스프라이트 시트 선택"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png, .webP]

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        do {
            let document = try SpriteSheetFrameExtractor().load(at: sourceURL)
            spriteSheetImport = SpriteSheetImportPresentation(document: document)
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func chooseExistingFrames() {
        do {
            let item = petLibrarySession.selectedItem
            existingFrameImport = ExistingPetFramePickerPresentation(
                petName: item.metadata.displayName,
                groups: try ExistingPetFrameLibrary.load(from: item)
            )
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func appendSpriteImages(_ images: [UserPetSourceImage]) {
        let addedFrames = UserPetAnimationDraftFactory.new(
            images: images,
            durationMilliseconds: frameDurationMilliseconds,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
    }

    private func appendExistingFrames(
        _ selections: [ExistingPetFrameSelection]
    ) {
        let addedFrames = UserPetAnimationDraftFactory.reused(
            selections: selections,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
    }

    private func moveFrame(at index: Int, offset: Int) {
        let destination = index + offset
        guard frames.indices.contains(index), frames.indices.contains(destination) else {
            return
        }
        frames.swapAt(index, destination)
    }

    private func duplicateFrame(at index: Int) {
        guard frames.indices.contains(index) else {
            return
        }
        let duplicate = frames[index].duplicated()
        frames.insert(duplicate, at: index + 1)
        selectedFrameID = duplicate.id
    }

    private func duplicateSelectedFrame() {
        guard let selectedFrameID,
              let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
            return
        }
        duplicateFrame(at: index)
    }

    private func removeFrame(id: UUID) {
        guard frames.count > 1 else {
            return
        }
        frames.removeAll { $0.id == id }
        if selectedFrameID == id {
            selectedFrameID = frames.first?.id
        }
    }

    private func save() {
        behaviorLinkErrorMessage = nil
        guard prepareForSaving() else { return }
        let normalizedName = normalizedAnimationName
        let succeeded = petLibrarySession.updateSelectedPetAnimation(
            UserPetAnimationDetailsRequest(
                animationID: motion.id,
                animationName: normalizedName,
                loops: loops,
                frames: frames.map {
                    UserPetAnimationFrameRequest(
                        source: $0.source,
                        durationMilliseconds: $0.durationMilliseconds,
                        placement: $0.placement,
                        flipsHorizontally: $0.flipsHorizontally,
                        flipsVertically: $0.flipsVertically
                    )
                }
            )
        )
        if succeeded {
            if settingsSession.isWritingEnabled,
               !settingsSession.synchronizeGeneratedSingleStepBehaviorNames() {
                behaviorLinkErrorMessage = settingsSession.behaviorEditErrorMessage
                    ?? "애니메이션은 저장했지만 자동 생성 행동 이름을 갱신하지 못했습니다."
                return
            }
            guard applyBehaviorLink(animationID: normalizedName) else {
                behaviorLinkErrorMessage = settingsSession.behaviorEditErrorMessage
                    ?? "애니메이션은 저장했지만 행동 연결을 추가하지 못했습니다. 다시 저장해 주세요."
                return
            }
            onSaved(normalizedName)
            dismiss()
        }
    }

    private var normalizedAnimationName: String {
        animationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var behaviorLinkValidationMessage: String? {
        animationBehaviorLinkValidationMessage(
            mode: behaviorLinkMode,
            newBehaviorName: newBehaviorName,
            existingBehaviorID: existingBehaviorID,
            animationID: normalizedAnimationName,
            sequences: settingsSession.settings.sequences
        )
    }

    private func selectFirstBehaviorIfNeeded() {
        guard !settingsSession.settings.sequences.contains(where: {
            $0.id == existingBehaviorID
        }) else {
            return
        }
        existingBehaviorID = settingsSession.settings.sequences.first?.id ?? ""
    }

    private func applyBehaviorLink(animationID: String) -> Bool {
        switch behaviorLinkMode {
        case .none:
            return true
        case .newBehavior:
            return settingsSession.addBehaviorSequence(
                named: effectiveBehaviorName(
                    enteredName: newBehaviorName,
                    animationID: animationID
                ),
                initialMotionID: animationID
            )
        case .existingBehavior:
            return settingsSession.addBehaviorStep(
                to: existingBehaviorID,
                motionID: animationID
            )
        }
    }

}

private struct UserPetAnimationFrameDraft: Identifiable {
    var id = UUID()
    let source: UserPetAnimationFrameSource
    var durationMilliseconds: Int
    let content: TransparentFrameContent
    let canvasSize: PixelSize
    let baseScale: Double
    let anchorX: Double
    let anchorBottom: Double
    var scalePercent: Double = 100
    var offsetX: Double = 0
    var offsetY: Double = 0
    var flipsHorizontally = false
    var flipsVertically = false
    var transformedContentImage: CGImage
    var previewImage: CGImage?

    init?(
        source: UserPetAnimationFrameSource,
        durationMilliseconds: Int,
        image: CGImage,
        canvasSize: PixelSize,
        baseScale: Double,
        anchorX: Double,
        anchorBottom: Double
    ) {
        guard let content = try? FrameCanvasComposer().transparentContent(in: image) else {
            return nil
        }
        self.source = source
        self.durationMilliseconds = durationMilliseconds
        self.content = content
        self.canvasSize = canvasSize
        self.baseScale = baseScale
        self.anchorX = anchorX
        self.anchorBottom = anchorBottom
        transformedContentImage = content.image
        previewImage = nil
        refreshPreview()
    }

    var placement: FrameCanvasPlacement {
        let scale = baseScale * scalePercent / 100
        return FrameCanvasPlacement(
            canvasWidth: canvasSize.width,
            canvasHeight: canvasSize.height,
            scale: scale,
            x: anchorX - Double(content.image.width) * scale / 2 + offsetX,
            y: anchorBottom - Double(content.image.height) * scale + offsetY
        )
    }

    var renderedContentSize: CGSize {
        CGSize(
            width: Double(content.image.width) * placement.scale,
            height: Double(content.image.height) * placement.scale
        )
    }

    mutating func refreshPreview() {
        previewImage = try? FrameCanvasComposer().compose(
            TransparentFrameContent(
                image: transformedContentImage,
                sourceBounds: content.sourceBounds
            ),
            placement: placement
        )
    }

    mutating func refreshTransform() {
        guard let transformed = ImageCropProcessor().transformed(
            content.image,
            flipsHorizontally: flipsHorizontally,
            flipsVertically: flipsVertically
        ) else {
            previewImage = nil
            return
        }
        transformedContentImage = transformed
        refreshPreview()
    }

    mutating func resetPlacement() {
        scalePercent = 100
        offsetX = 0
        offsetY = 0
        refreshPreview()
    }

    mutating func resetFlips() {
        flipsHorizontally = false
        flipsVertically = false
        refreshTransform()
    }

    func duplicated() -> UserPetAnimationFrameDraft {
        var duplicate = self
        duplicate.id = UUID()
        return duplicate
    }
}

@MainActor
private enum PNGFrameImportLoader {
    static func load(_ sourceURLs: [URL]) throws -> [UserPetSourceImage] {
        try sourceURLs.map { sourceURL in
            UserPetSourceImage(
                displayName: sourceURL.lastPathComponent,
                image: try SimpleAnimationPetPackageAdapter()
                    .loadStaticPNGWithSecurityScope(at: sourceURL)
            )
        }
    }
}

@MainActor
private enum UserPetAnimationDraftFactory {
    static func existing(
        item: PetLibraryItem,
        motion: PetMotion
    ) -> [UserPetAnimationFrameDraft] {
        let atlases = (try? PetPresentationResourceLoader.loadAtlases(for: item)) ?? []
        let atlasImages = Dictionary(uniqueKeysWithValues: atlases.map { ($0.id, $0.image) })
        return motion.frames.enumerated().compactMap { index, frame in
            guard let image = atlasImages[frame.atlasID]?.cropping(
                to: CGRect(
                    x: frame.sourceRect.x,
                    y: frame.sourceRect.y,
                    width: frame.sourceRect.width,
                    height: frame.sourceRect.height
                )
            ), let content = try? FrameCanvasComposer().transparentContent(in: image) else {
                return nil
            }
            return UserPetAnimationFrameDraft(
                source: .existing(index: index),
                durationMilliseconds: durationMilliseconds(frame.duration),
                image: image,
                canvasSize: PixelSize(
                    width: frame.sourceRect.width,
                    height: frame.sourceRect.height
                ),
                baseScale: 1,
                anchorX: Double(content.sourceBounds.x)
                    + Double(content.sourceBounds.width) / 2,
                anchorBottom: Double(
                    content.sourceBounds.y + content.sourceBounds.height
                )
            )
        }
    }

    static func new(
        images: [UserPetSourceImage],
        durationMilliseconds: Int,
        reference: UserPetAnimationFrameDraft? = nil
    ) -> [UserPetAnimationFrameDraft] {
        let sources = images.compactMap { sourceImage -> NewFrameSource? in
            guard let content = try? FrameCanvasComposer().transparentContent(
                in: sourceImage.image
            ) else {
                return nil
            }
            return NewFrameSource(
                source: .image(sourceImage),
                image: sourceImage.image,
                content: content,
                durationMilliseconds: durationMilliseconds
            )
        }
        return new(
            sources: sources,
            reference: reference
        )
    }

    static func reused(
        selections: [ExistingPetFrameSelection],
        reference: UserPetAnimationFrameDraft? = nil
    ) -> [UserPetAnimationFrameDraft] {
        let sources = selections.compactMap { selection -> NewFrameSource? in
            let sourceImage = selection.image
            guard let content = try? FrameCanvasComposer().transparentContent(
                in: sourceImage.image
            ) else {
                return nil
            }
            return NewFrameSource(
                source: .image(sourceImage),
                image: sourceImage.image,
                content: content,
                durationMilliseconds: selection.durationMilliseconds
            )
        }
        return new(sources: sources, reference: reference)
    }

    private static func new(
        sources: [NewFrameSource],
        reference: UserPetAnimationFrameDraft?
    ) -> [UserPetAnimationFrameDraft] {
        guard !sources.isEmpty else {
            return []
        }

        if let reference {
            let referencePlacement = reference.placement
            let targetSize = reference.renderedContentSize
            let anchorX = referencePlacement.x + targetSize.width / 2
            let anchorBottom = referencePlacement.y + targetSize.height
            let maximumContentWidth = sources.map { $0.content.image.width }.max() ?? 1
            let maximumContentHeight = sources.map { $0.content.image.height }.max() ?? 1
            let commonScale = min(
                targetSize.width / Double(maximumContentWidth),
                targetSize.height / Double(maximumContentHeight)
            )
            return sources.compactMap { item in
                return UserPetAnimationFrameDraft(
                    source: item.source,
                    durationMilliseconds: item.durationMilliseconds,
                    image: item.image,
                    canvasSize: reference.canvasSize,
                    baseScale: commonScale,
                    anchorX: anchorX,
                    anchorBottom: anchorBottom
                )
            }
        }

        let canvasSize = PixelSize(
            width: sources.map { $0.image.width }.max() ?? 512,
            height: sources.map { $0.image.height }.max() ?? 512
        )
        let usesSameCanvas = Set(
            sources.map { "\($0.image.width)x\($0.image.height)" }
        ).count == 1
        let maximumContentWidth = sources.map { $0.content.image.width }.max() ?? 1
        let maximumContentHeight = sources.map { $0.content.image.height }.max() ?? 1
        let commonScale = min(
            Double(canvasSize.width) * 0.8 / Double(maximumContentWidth),
            Double(canvasSize.height) * 0.8 / Double(maximumContentHeight)
        )
        return sources.compactMap { item in
            let image = item.image
            let content = item.content
            let scale: Double
            let anchorX: Double
            let anchorBottom: Double
            if usesSameCanvas {
                scale = 1
                anchorX = Double(content.sourceBounds.x)
                    + Double(content.sourceBounds.width) / 2
                anchorBottom = Double(
                    content.sourceBounds.y + content.sourceBounds.height
                )
            } else {
                scale = commonScale
                anchorX = Double(canvasSize.width) / 2
                anchorBottom = Double(canvasSize.height) * 0.9
            }
            return UserPetAnimationFrameDraft(
                source: item.source,
                durationMilliseconds: item.durationMilliseconds,
                image: image,
                canvasSize: canvasSize,
                baseScale: scale,
                anchorX: anchorX,
                anchorBottom: anchorBottom
            )
        }
    }

    private struct NewFrameSource {
        let source: UserPetAnimationFrameSource
        let image: CGImage
        let content: TransparentFrameContent
        let durationMilliseconds: Int
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: value)
    }
}

private struct FrameDurationInput: View {
    @Binding var milliseconds: Int
    let accessibilityIdentifier: String

    private static let allowedRange = 16...60_000
    private static let presets = [100, 250, 450, 1_000]

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "밀리초",
                value: boundedMilliseconds,
                format: .number
            )
            .frame(width: 76)
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier(accessibilityIdentifier)

            Text("ms")
                .foregroundStyle(.secondary)

            Stepper(
                "프레임 간격 조절",
                value: boundedMilliseconds,
                in: Self.allowedRange,
                step: 10
            )
            .labelsHidden()

            Menu("빠른 값") {
                ForEach(Self.presets, id: \.self) { value in
                    Button("\(value) ms") {
                        milliseconds = value
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var boundedMilliseconds: Binding<Int> {
        Binding(
            get: {
                min(Self.allowedRange.upperBound, max(Self.allowedRange.lowerBound, milliseconds))
            },
            set: { newValue in
                milliseconds = min(
                    Self.allowedRange.upperBound,
                    max(Self.allowedRange.lowerBound, newValue)
                )
            }
        )
    }
}

private struct FramePlacementControls: View {
    @Binding var frame: UserPetAnimationFrameDraft
    let onDuplicate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("자동 맞춤 대비 배율")
                Spacer()
                Text("\(Int(frame.scalePercent.rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(
                value: scaleBinding,
                in: 25...400,
                step: 5,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        frame.refreshPreview()
                    }
                }
            )
                .accessibilityLabel("선택 프레임 배율")

            editorGroup("위치") {
                HStack(spacing: 8) {
                    FrameAxisAdjustmentControl(
                        title: "가로",
                        value: horizontalOffsetBinding,
                        range: -Double(frame.canvasSize.width)...Double(frame.canvasSize.width),
                        negativeDirectionHint: "왼쪽",
                        positiveDirectionHint: "오른쪽"
                    )
                    FrameAxisAdjustmentControl(
                        title: "세로",
                        value: verticalOffsetBinding,
                        range: -Double(frame.canvasSize.height)...Double(frame.canvasSize.height),
                        negativeDirectionHint: "위",
                        positiveDirectionHint: "아래"
                    )
                }

                Button {
                    frame.resetPlacement()
                } label: {
                    frameActionLabel(
                        "배치 초기화",
                        systemImage: "scope"
                    )
                }
                .accessibilityIdentifier(
                    "monglepet.petAnimation.resetPlacement"
                )
            }

            editorGroup("이미지 방향") {
                HStack(spacing: 8) {
                    Button {
                        frame.flipsHorizontally.toggle()
                        frame.refreshTransform()
                    } label: {
                        frameActionLabel(
                            frame.flipsHorizontally ? "좌우 해제" : "좌우 반전",
                            systemImage: "arrow.left.and.right"
                        )
                    }
                    .accessibilityIdentifier(
                        "monglepet.petAnimation.flipHorizontal"
                    )

                    Button {
                        frame.flipsVertically.toggle()
                        frame.refreshTransform()
                    } label: {
                        frameActionLabel(
                            frame.flipsVertically ? "상하 해제" : "상하 반전",
                            systemImage: "arrow.up.and.down"
                        )
                    }
                    .accessibilityIdentifier(
                        "monglepet.petAnimation.flipVertical"
                    )
                }

                Button {
                    frame.resetFlips()
                } label: {
                    frameActionLabel(
                        "방향 초기화",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .disabled(!frame.flipsHorizontally && !frame.flipsVertically)
                .accessibilityIdentifier(
                    "monglepet.petAnimation.resetFlips"
                )
            }

            editorGroup("프레임 작업") {
                Button(action: onDuplicate) {
                    frameActionLabel(
                        "선택 프레임 복사",
                        systemImage: "plus.square.on.square"
                    )
                }
                .accessibilityIdentifier(
                    "monglepet.petAnimation.duplicateFrame"
                )
            }
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
    }

    private func editorGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func frameActionLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30)
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { frame.scalePercent },
            set: {
                frame.scalePercent = $0
            }
        )
    }

    private var horizontalOffsetBinding: Binding<Double> {
        Binding(
            get: { frame.offsetX },
            set: {
                frame.offsetX = $0
                frame.refreshPreview()
            }
        )
    }

    private var verticalOffsetBinding: Binding<Double> {
        Binding(
            get: { frame.offsetY },
            set: {
                frame.offsetY = $0
                frame.refreshPreview()
            }
        )
    }
}

private struct FrameAxisAdjustmentControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let negativeDirectionHint: String
    let positiveDirectionHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text("\(Int(value.rounded())) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                adjustmentButton(
                    systemImage: "minus",
                    directionHint: negativeDirectionHint,
                    delta: -1
                )
                adjustmentButton(
                    systemImage: "plus",
                    directionHint: positiveDirectionHint,
                    delta: 1
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("선택 프레임 \(title) 위치")
    }

    private func adjustmentButton(
        systemImage: String,
        directionHint: String,
        delta: Double
    ) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .disabled(
            delta < 0 ? value <= range.lowerBound : value >= range.upperBound
        )
        .accessibilityLabel("\(title) 위치 \(directionHint)으로 1픽셀")
    }
}

private enum EditableAnimationPreviewMode: String, CaseIterable, Identifiable {
    case animation = "전체 재생"
    case selectedFrame = "선택 프레임"

    var id: Self { self }
}

private struct EditableAnimationPreviewPanel: View {
    @Binding var frames: [UserPetAnimationFrameDraft]
    let loops: Bool
    let selectedFrameID: UUID?

    @State private var previewMode: EditableAnimationPreviewMode = .selectedFrame
    @State private var isPlaying = true
    @State private var showsReferenceFrame = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("미리보기 방식", selection: $previewMode) {
                ForEach(EditableAnimationPreviewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("monglepet.petAnimation.previewMode")

            EditableAnimationPreviewView(
                frames: frames,
                loops: loops,
                selectedFrameID: selectedFrameID,
                previewMode: previewMode,
                isPlaying: $isPlaying,
                editableFrame: previewMode == .selectedFrame
                    ? selectedFrameBinding
                    : nil,
                referenceImage: referenceImage
            )
            .frame(height: 190)
            .background(
                .quaternary.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 10)
            )

            HStack {
                if previewMode == .animation {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Label(
                            isPlaying ? "일시정지" : "재생",
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("monglepet.petAnimation.previewPlayback")
                }

                Spacer()

                Text(previewCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if previewMode == .selectedFrame,
               selectedFrameID != frames.first?.id,
               frames.count > 1 {
                Toggle("첫 프레임 겹쳐보기", isOn: $showsReferenceFrame)
                    .font(.caption)
                    .controlSize(.small)
            }

            if previewMode == .selectedFrame, selectedFrameBinding != nil {
                Text("펫을 드래그해 이동하고 위쪽 핸들로 크기를 조절합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedFrameBinding: Binding<UserPetAnimationFrameDraft>? {
        guard let selectedFrameID,
              let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return $frames[index]
    }

    private var referenceImage: CGImage? {
        guard showsReferenceFrame,
              selectedFrameID != frames.first?.id else {
            return nil
        }
        return frames.first?.previewImage
    }

    private var previewCaption: String {
        switch previewMode {
        case .animation:
            "총 \(frames.count)개 프레임"
        case .selectedFrame:
            if let selectedFrameID,
               let index = frames.firstIndex(where: { $0.id == selectedFrameID }) {
                "선택 \(index + 1)/\(frames.count)"
            } else {
                "프레임을 선택해 주세요"
            }
        }
    }
}

private struct FramePlacementEditorOverlay: View {
    @Binding var frame: UserPetAnimationFrameDraft
    let displayedCanvasSize: CGSize

    @State private var moveStartOffset: CGSize?
    @State private var resizeStartPercent: Double?
    @State private var resizeStartSize: CGSize?

    var body: some View {
        let rect = displayedContentRect
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.04))
                .overlay {
                    Rectangle()
                        .stroke(Color.accentColor.opacity(0.9), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture)

            Circle()
                .fill(Color.accentColor)
                .overlay {
                    Circle().stroke(.white, lineWidth: 1)
                }
                .frame(width: 12, height: 12)
                .position(x: rect.midX, y: rect.minY)
                .gesture(resizeGesture)
                .accessibilityLabel("선택 프레임 크기 조절")
        }
        .frame(
            width: displayedCanvasSize.width,
            height: displayedCanvasSize.height,
            alignment: .topLeading
        )
        .coordinateSpace(name: Self.coordinateSpaceName)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel("선택 프레임 직접 배치")
    }

    private static let coordinateSpaceName = "monglepet.framePlacementEditor"

    private var displayedContentRect: CGRect {
        let placement = frame.placement
        let scaleX = displayedCanvasSize.width
            / CGFloat(max(1, frame.canvasSize.width))
        let scaleY = displayedCanvasSize.height
            / CGFloat(max(1, frame.canvasSize.height))
        return CGRect(
            x: CGFloat(placement.x) * scaleX,
            y: CGFloat(placement.y) * scaleY,
            width: frame.renderedContentSize.width * scaleX,
            height: frame.renderedContentSize.height * scaleY
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named(Self.coordinateSpaceName)
        )
            .onChanged { value in
                let start = moveStartOffset
                    ?? CGSize(
                        width: CGFloat(frame.offsetX),
                        height: CGFloat(frame.offsetY)
                    )
                moveStartOffset = start
                let canvasScale = displayedCanvasSize.width
                    / CGFloat(max(1, frame.canvasSize.width))
                var updated = frame
                updated.offsetX = Double(
                    start.width
                        + value.translation.width / max(0.000_1, canvasScale)
                )
                updated.offsetY = Double(
                    start.height
                        + value.translation.height / max(0.000_1, canvasScale)
                )
                frame = updated
            }
            .onEnded { _ in
                moveStartOffset = nil
                var updated = frame
                updated.refreshPreview()
                frame = updated
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.coordinateSpaceName)
        )
            .onChanged { value in
                let startPercent = resizeStartPercent ?? frame.scalePercent
                let startSize = resizeStartSize ?? displayedContentRect.size
                resizeStartPercent = startPercent
                resizeStartSize = startSize
                var updated = frame
                updated.scalePercent = min(
                    400,
                    max(
                        25,
                        startPercent
                            * (1 - value.translation.height / max(1, startSize.height))
                    )
                )
                frame = updated
            }
            .onEnded { _ in
                resizeStartPercent = nil
                resizeStartSize = nil
                var updated = frame
                updated.refreshPreview()
                frame = updated
            }
    }
}

private struct EditableAnimationPreviewView: View {
    let frames: [UserPetAnimationFrameDraft]
    let loops: Bool
    let selectedFrameID: UUID?
    let previewMode: EditableAnimationPreviewMode
    @Binding var isPlaying: Bool
    let editableFrame: Binding<UserPetAnimationFrameDraft>?
    let referenceImage: CGImage?

    @State private var frameIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = fittedCanvasSize(in: geometry.size)

            ZStack {
                TransparencyGridView()

                if let editableFrame {
                    if let referenceImage {
                        Image(decorative: referenceImage, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .opacity(0.24)
                    }

                    LivePlacedFrameView(
                        frame: editableFrame.wrappedValue,
                        displayedCanvasSize: canvasSize
                    )
                } else if let image = currentFrame?.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

                if let editableFrame {
                    FramePlacementEditorOverlay(
                        frame: editableFrame,
                        displayedCanvasSize: canvasSize
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay {
                Rectangle()
                    .stroke(.secondary.opacity(0.45), lineWidth: 1)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .task(id: playbackIdentity) {
            guard previewMode == .animation, isPlaying, !frames.isEmpty else {
                return
            }
            if !frames.indices.contains(frameIndex) {
                frameIndex = 0
            }
            if !loops, frameIndex == frames.index(before: frames.endIndex) {
                frameIndex = 0
            }
            while !Task.isCancelled {
                let delay = min(
                    60_000,
                    max(16, currentFrame?.durationMilliseconds ?? 120)
                )
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else {
                    return
                }
                if frameIndex + 1 < frames.count {
                    frameIndex += 1
                } else if loops {
                    frameIndex = 0
                } else {
                    isPlaying = false
                    return
                }
            }
        }
    }

    private var currentFrame: UserPetAnimationFrameDraft? {
        if previewMode == .selectedFrame {
            return frames.first(where: { $0.id == selectedFrameID }) ?? frames.first
        }
        guard frames.indices.contains(frameIndex) else {
            return frames.first
        }
        return frames[frameIndex]
    }

    private func fittedCanvasSize(in availableSize: CGSize) -> CGSize {
        let width = max(1, Double(currentFrame?.canvasSize.width ?? 1))
        let height = max(1, Double(currentFrame?.canvasSize.height ?? 1))
        let availableWidth = max(1, availableSize.width - 16)
        let availableHeight = max(1, availableSize.height - 16)
        let scale = min(availableWidth / width, availableHeight / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    private var playbackIdentity: String {
        frames.map { "\($0.id.uuidString):\($0.durationMilliseconds)" }
            .joined(separator: "|")
            + ":\(loops):\(previewMode.rawValue):\(isPlaying)"
    }
}

private struct LivePlacedFrameView: View {
    let frame: UserPetAnimationFrameDraft
    let displayedCanvasSize: CGSize

    var body: some View {
        let placement = frame.placement
        let contentSize = frame.renderedContentSize
        let scaleX = displayedCanvasSize.width
            / CGFloat(max(1, frame.canvasSize.width))
        let scaleY = displayedCanvasSize.height
            / CGFloat(max(1, frame.canvasSize.height))
        Image(decorative: frame.transformedContentImage, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(
                width: contentSize.width * scaleX,
                height: contentSize.height * scaleY
            )
            .position(
                x: (placement.x + contentSize.width / 2) * scaleX,
                y: (placement.y + contentSize.height / 2) * scaleY
            )
    }
}

private struct TransparencyGridView: View {
    private let squareLength = 10.0

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(nsColor: .controlBackgroundColor))
            )
            let columns = Int(ceil(size.width / squareLength))
            let rows = Int(ceil(size.height / squareLength))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: Double(column) * squareLength,
                                y: Double(row) * squareLength,
                                width: squareLength,
                                height: squareLength
                            )
                        ),
                        with: .color(.secondary.opacity(0.13))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    let settingsSession = AppSettingsSession(
            store: AppSettingsStore(
                settingsURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("MonglePet-Preview-settings.json")
            )
        )
    let definition = BuiltInPet.mongleDefinition()
    SettingsView(
        settingsSession: settingsSession,
        petLibrarySession: PetLibrarySession(
            builtInDefinition: definition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in }
        ),
        loginLaunchSettings: LoginLaunchSettings(
            service: PreviewLoginLaunchService()
        ),
        runtimeControlSession: PetRuntimeControlSession(),
        remotePetImportRequestCenter: RemotePetImportRequestCenter(),
        remotePetImportService: RemotePetImportService()
    )
}

@MainActor
private final class PreviewLoginLaunchService: LoginLaunchServicing {
    var status: LoginLaunchStatus {
        .notRegistered
    }

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
