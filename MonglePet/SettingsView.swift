import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession

    var body: some View {
        TabView {
            GeneralSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession
            )
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            BehaviorSequencesSettingsView(
                settingsSession: settingsSession,
                petDefinition: petLibrarySession.selectedItem.definition
            )
                .tabItem {
                    Label("행동 루틴", systemImage: "list.bullet.rectangle")
                }

            AutomaticRulesSettingsView(settingsSession: settingsSession)
                .tabItem {
                    Label("자동 규칙", systemImage: "bolt.badge.clock")
                }
        }
        .frame(minWidth: 680, minHeight: 540)
        .accessibilityIdentifier("monglepet.settings.root")
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @State private var isConfirmingRemoval = false
    @State private var isEditingPetDetails = false
    @State private var userPetEditorMode: UserPetEditorMode?
    @State private var previewMotionID: String?

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

            Section("펫 라이브러리") {
                Picker("현재 펫", selection: petSelectionBinding) {
                    ForEach(petLibrarySession.items) { item in
                        Text(item.metadata.displayName)
                            .tag(item.selection)
                    }
                }
                .accessibilityIdentifier("monglepet.settings.petSelection")

                HStack(alignment: .top, spacing: 16) {
                    PetAnimationPreviewView(
                        item: petLibrarySession.selectedItem,
                        motionID: effectivePreviewMotionID
                    )
                    .frame(width: 176, height: 176)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("현재 펫 애니메이션 미리보기")

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "버전",
                            value: petLibrarySession.selectedItem.metadata.version
                        )
                        LabeledContent(
                            "제작자",
                            value: petLibrarySession.selectedItem.metadata.author
                        )
                        LabeledContent(
                            "라이선스",
                            value: petLibrarySession.selectedItem.metadata.license
                        )
                        if let description = petLibrarySession.selectedItem.metadata.description {
                            LabeledContent("설명", value: description)
                        }

                        Text("등록된 애니메이션")
                            .font(.headline)

                        List(selection: $previewMotionID) {
                            ForEach(petLibrarySession.selectedItem.definition.motions) { motion in
                                HStack {
                                    Text(motion.id)
                                    Spacer()
                                    if motion.id
                                        == petLibrarySession.selectedItem.definition.defaultMotionID {
                                        Text("기본")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(motion.id)
                            }
                        }
                        .frame(minHeight: 96, maxHeight: 132)
                        .accessibilityIdentifier("monglepet.settings.petAnimations")

                        if let motion = selectedPreviewMotion {
                            Text(motionSummary(motion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityIdentifier(
                                    "monglepet.settings.petAnimationSummary"
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("PNG로 새 펫 만들기…") {
                        userPetEditorMode = .create
                    }
                    .disabled(petLibrarySession.isImporting)
                    .accessibilityIdentifier("monglepet.settings.createUserPet")

                    if petLibrarySession.selectedItem.isEditable {
                        Button("펫 정보 수정…") {
                            isEditingPetDetails = true
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier("monglepet.settings.editPetDetails")

                        Button("펫 애니메이션 추가…") {
                            userPetEditorMode = .addAnimation
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier("monglepet.settings.addPetAnimation")
                    }
                }

                HStack {
                    Button("MonglePet 패키지 가져오기…") {
                        choosePetPackage()
                    }
                    .disabled(petLibrarySession.isImporting)
                    .accessibilityIdentifier("monglepet.settings.importPackage")

                    if !petLibrarySession.selectedItem.isBuiltIn {
                        Button("선택한 펫 삭제…", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                        .accessibilityIdentifier("monglepet.settings.removePet")
                    }
                }

                Text(
                    petLibrarySession.selectedItem.isBuiltIn
                        ? "내장 몽글이는 삭제할 수 없으며 언제든 다시 선택할 수 있습니다."
                        : petLibrarySession.selectedItem.isEditable
                            ? "PNG 한 장은 정지 애니메이션, 여러 장은 지정한 순서대로 재생됩니다."
                            : "가져온 패키지는 원본 보호를 위해 현재 버전에서 직접 편집하지 않습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("펫 표시") {
                Toggle("펫 깨우기", isOn: awakeBinding)
                    .accessibilityIdentifier("monglepet.settings.awake")

                Text("재워도 메뉴 막대에서 언제든 다시 깨울 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("행동 모드") {
                Picker("행동 모드", selection: behaviorModeBinding) {
                    Text("자동").tag(BehaviorMode.automatic.rawValue)
                    Text("수동").tag(BehaviorMode.manual.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("monglepet.settings.behaviorMode")

                if settingsSession.settings.behaviorMode == .manual {
                    Picker("수동 행동 루틴", selection: manualSequenceBinding) {
                        ForEach(settingsSession.settings.sequences) { sequence in
                            Text(BuiltInBehaviorPresets.displayName(for: sequence.id))
                                .tag(sequence.id)
                        }
                    }
                    .accessibilityIdentifier("monglepet.settings.manualSequence")
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settingsSession.isWritingEnabled)

            Section("화면 표시") {
                HStack {
                    Text("펫 크기")
                    Slider(
                        value: overlayWidthBinding,
                        in: AppSettingsLimits.minimumOverlayWidth
                            ... AppSettingsLimits.maximumOverlayWidth,
                        step: 8,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                settingsSession.persistCurrentSettings()
                            }
                        }
                    )
                    .accessibilityIdentifier("monglepet.settings.overlayWidth")
                    Text("\(Int(settingsSession.settings.overlay.width)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }

                Toggle("클릭 통과", isOn: clickThroughBinding)
                    .accessibilityIdentifier("monglepet.settings.clickThrough")

                Text(
                    settingsSession.settings.overlay.clickThrough
                        ? "펫을 직접 드래그할 수 없습니다. 이 설정창에서 클릭 통과를 끌 수 있습니다."
                        : "켜면 펫 아래의 앱을 바로 클릭할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(!settingsSession.isWritingEnabled)
        }
        .formStyle(.grouped)
        .alert(
            "동일한 펫 패키지가 이미 설치되어 있습니다.",
            isPresented: duplicateInstallAlertBinding
        ) {
            Button("별도 사본으로 설치") {
                petLibrarySession.installDuplicateSeparately()
            }
            Button("기존 항목 교체", role: .destructive) {
                petLibrarySession.replaceDuplicateInstallation()
            }
            Button("취소", role: .cancel) {
                petLibrarySession.cancelDuplicateInstallation()
            }
        } message: {
            Text(duplicateInstallMessage)
        }
        .alert("선택한 펫을 삭제할까요?", isPresented: $isConfirmingRemoval) {
            Button("삭제", role: .destructive) {
                _ = petLibrarySession.removeSelectedInstallation()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("라이브러리에서 패키지 파일을 삭제하고 내장 몽글이로 전환합니다.")
        }
        .sheet(item: $userPetEditorMode) { mode in
            UserPetAnimationEditorView(
                mode: mode,
                petLibrarySession: petLibrarySession
            )
        }
        .sheet(isPresented: $isEditingPetDetails) {
            UserPetDetailsEditorView(
                item: petLibrarySession.selectedItem,
                petLibrarySession: petLibrarySession
            )
        }
        .onAppear(perform: synchronizePreviewMotion)
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

    private var selectedPreviewMotion: PetMotion? {
        petLibrarySession.selectedItem.definition.motion(id: effectivePreviewMotionID)
    }

    private func synchronizePreviewMotion() {
        previewMotionID = petLibrarySession.selectedItem.definition.defaultMotion?.id
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

    private var awakeBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.lastUserPresentation == .awake },
            set: {
                settingsSession.setUserPresentation($0 ? .awake : .tuckedAway)
            }
        )
    }

    private var petSelectionBinding: Binding<PetLibrarySelection> {
        Binding(
            get: { petLibrarySession.selection },
            set: { _ = petLibrarySession.select($0) }
        )
    }

    private var behaviorModeBinding: Binding<String> {
        Binding(
            get: { settingsSession.settings.behaviorMode.rawValue },
            set: { rawValue in
                guard let mode = BehaviorMode(rawValue: rawValue) else {
                    return
                }
                settingsSession.setBehaviorMode(mode)
            }
        )
    }

    private var overlayWidthBinding: Binding<Double> {
        Binding(
            get: { settingsSession.settings.overlay.width },
            set: { settingsSession.setOverlayWidth($0, persist: false) }
        )
    }

    private var manualSequenceBinding: Binding<String> {
        Binding(
            get: {
                settingsSession.settings.manualSequenceID
                    ?? settingsSession.settings.sequences.first?.id
                    ?? ""
            },
            set: { settingsSession.setManualSequenceID($0) }
        )
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.overlay.clickThrough },
            set: { settingsSession.setClickThrough($0) }
        )
    }

    private var modeDescription: String {
        switch settingsSession.settings.behaviorMode {
        case .automatic:
            "활성화된 자동 규칙 중 우선순위가 가장 높은 행동을 재생합니다."
        case .manual:
            "선택한 행동 루틴의 펫 애니메이션을 순서대로 재생합니다."
        }
    }

    private var duplicateInstallAlertBinding: Binding<Bool> {
        Binding(
            get: { petLibrarySession.duplicateInstallRequest != nil },
            set: { isPresented in
                if !isPresented {
                    petLibrarySession.cancelDuplicateInstallation()
                }
            }
        )
    }

    private var duplicateInstallMessage: String {
        guard let request = petLibrarySession.duplicateInstallRequest else {
            return ""
        }
        if request.installationIDs.count > 1 {
            return "같은 패키지 ID의 설치 항목이 \(request.installationIDs.count)개 있습니다. 교체를 선택하면 기존 항목 목록의 첫 항목을 교체합니다."
        }
        return "기존 설치를 유지하고 사본을 추가하거나, 기존 항목을 같은 설치 ID로 교체할 수 있습니다."
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
        _ = petLibrarySession.installPackage(from: sourceURL)
    }

    @ViewBuilder
    private func noticeLabel(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.orange)
            .font(.callout)
            .accessibilityIdentifier("monglepet.settings.notice")
    }
}

private enum UserPetEditorMode: String, Identifiable {
    case create
    case addAnimation

    var id: String { rawValue }
}

private struct UserPetAnimationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: UserPetEditorMode
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var petName = ""
    @State private var version = "1.0.0"
    @State private var author = "MonglePet 사용자"
    @State private var license = "Private Use"
    @State private var petDescription = "MonglePet에서 사용자가 만든 펫입니다."
    @State private var animationName = ""
    @State private var frameDurationMilliseconds = 120
    @State private var loops = true
    @State private var sourceURLs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "PNG로 새 펫 만들기" : "펫 애니메이션 추가")
                .font(.title2.weight(.semibold))

            Form {
                if mode == .create {
                    TextField("펫 이름", text: $petName)
                        .accessibilityIdentifier("monglepet.userPet.petName")

                    TextField("제작자", text: $author)
                        .accessibilityIdentifier("monglepet.userPet.author")

                    TextField("버전", text: $version)
                        .accessibilityIdentifier("monglepet.userPet.version")

                    TextField("라이선스", text: $license)
                        .accessibilityIdentifier("monglepet.userPet.license")

                    TextField("설명", text: $petDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("monglepet.userPet.description")
                }

                TextField("애니메이션 이름", text: $animationName)
                    .accessibilityIdentifier("monglepet.userPet.animationName")

                LabeledContent("기본 프레임 간격") {
                    Stepper(
                        "\(frameDurationMilliseconds) ms",
                        value: $frameDurationMilliseconds,
                        in: 16...60_000,
                        step: 10
                    )
                    .accessibilityIdentifier("monglepet.userPet.frameDuration")
                }

                Toggle("반복 재생", isOn: $loops)
                    .accessibilityIdentifier("monglepet.userPet.loops")
            }
            .formStyle(.grouped)

            HStack {
                Text("PNG 프레임")
                    .font(.headline)
                Spacer()
                Button(sourceURLs.isEmpty ? "PNG 선택…" : "PNG 다시 선택…") {
                    choosePNGs()
                }
                .accessibilityIdentifier("monglepet.userPet.choosePNGs")
            }

            GroupBox {
                if sourceURLs.isEmpty {
                    ContentUnavailableView(
                        "선택한 PNG가 없습니다.",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("한 장 또는 여러 장의 PNG를 선택해 주세요.")
                    )
                } else {
                    List {
                        ForEach(sourceURLs.indices, id: \.self) { index in
                            HStack {
                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Text(sourceURLs[index].lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    moveFrame(at: index, offset: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == sourceURLs.startIndex)
                                .accessibilityLabel("위로 이동")

                                Button {
                                    moveFrame(at: index, offset: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == sourceURLs.index(before: sourceURLs.endIndex))
                                .accessibilityLabel("아래로 이동")
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 150)

            Text("크기가 다른 이미지는 가장 큰 프레임 크기의 투명 캔버스 중앙에 맞춰집니다. 프레임 간격은 원본 재생 속도이며, 행동 루틴에서 유지 시간과 재생 속도를 별도로 지정할 수 있습니다.")
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
                Button(mode == .create ? "펫 만들기" : "추가") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.userPet.save")
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 570)
        .onAppear {
            if mode == .create {
                animationName = "기본"
            }
        }
    }

    private var canSave: Bool {
        !animationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceURLs.isEmpty
            && (mode != .create
                || (!petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private func choosePNGs() {
        let panel = NSOpenPanel()
        panel.title = "PNG 프레임 선택"
        panel.prompt = "선택"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK else {
            return
        }
        sourceURLs = panel.urls
    }

    private func moveFrame(at index: Int, offset: Int) {
        let destination = index + offset
        guard sourceURLs.indices.contains(index), sourceURLs.indices.contains(destination) else {
            return
        }
        sourceURLs.swapAt(index, destination)
    }

    private func save() {
        let succeeded: Bool
        switch mode {
        case .create:
            succeeded = petLibrarySession.createUserPet(
                UserPetCreationRequest(
                    displayName: petName,
                    animationName: animationName,
                    frameDurationMilliseconds: frameDurationMilliseconds,
                    loops: loops,
                    sourceURLs: sourceURLs,
                    version: version,
                    author: author,
                    license: license,
                    description: petDescription
                )
            )
        case .addAnimation:
            succeeded = petLibrarySession.addAnimationToSelectedPet(
                UserPetAnimationRequest(
                    animationName: animationName,
                    frameDurationMilliseconds: frameDurationMilliseconds,
                    loops: loops,
                    sourceURLs: sourceURLs
                )
            )
        }
        if succeeded {
            dismiss()
        }
    }
}

private struct UserPetDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PetLibraryItem
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var displayName: String
    @State private var version: String
    @State private var author: String
    @State private var license: String
    @State private var petDescription: String
    @State private var defaultMotionID: String

    init(item: PetLibraryItem, petLibrarySession: PetLibrarySession) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        _displayName = State(initialValue: item.metadata.displayName)
        _version = State(initialValue: item.metadata.version)
        _author = State(initialValue: item.metadata.author)
        _license = State(initialValue: item.metadata.license)
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

                TextField("버전", text: $version)
                    .accessibilityIdentifier("monglepet.petDetails.version")

                TextField("라이선스", text: $license)
                    .accessibilityIdentifier("monglepet.petDetails.license")

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
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.definition.motion(id: defaultMotionID) != nil
    }

    private func save() {
        let succeeded = petLibrarySession.updateSelectedPetDetails(
            UserPetDetailsRequest(
                displayName: displayName,
                version: version,
                author: author,
                license: license,
                description: petDescription,
                defaultMotionID: defaultMotionID
            )
        )
        if succeeded {
            dismiss()
        }
    }
}

#Preview {
    let settingsSession = AppSettingsSession(
            store: AppSettingsStore(
                settingsURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("MonglePet-Preview-settings.json")
            )
        )
    let definition = BuiltInPet.mongleDefinition(
        atlasPixelSize: PixelSize(width: 192, height: 208)
    )
    SettingsView(
        settingsSession: settingsSession,
        petLibrarySession: PetLibrarySession(
            builtInDefinition: definition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in }
        )
    )
}
