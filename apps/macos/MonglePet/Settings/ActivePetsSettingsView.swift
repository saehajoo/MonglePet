import SwiftUI

struct ActivePetsSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var runtimeControlSession: PetRuntimeControlSession
    @State private var isAddingPet = false
    @State private var removingInstanceID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let noticeMessage {
                Label(noticeMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                Divider()
            }

            if let pendingID = runtimeControlSession
                .pendingRecoveryInstanceID {
                safeStartBanner(pendingInstanceID: pendingID)
                Divider()
            }

            if let warning = runtimeControlSession.resourceWarning {
                resourceWarningBanner(warning)
                Divider()
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(orderedInstances) { instance in
                        ActivePetCard(
                            instance: instance,
                            item: item(for: instance),
                            profile: settingsSession.settings
                                .runtimeSettings(for: instance.instanceID)?
                                .activeBehaviorProfile,
                            isSelected: instance.instanceID
                                == settingsSession.settings
                                    .selectedPetInstanceID,
                            canRemove: orderedInstances.count > 1,
                            canEdit: settingsSession.isWritingEnabled,
                            canMoveForward: instance.displayOrder > 0,
                            canMoveBackward: instance.displayOrder
                                < orderedInstances.count - 1,
                            isRestored: runtimeControlSession
                                .restoredInstanceIDs
                                .contains(instance.instanceID),
                            onSelect: {
                                settingsSession.selectPetInstance(
                                    instance.instanceID
                                )
                            },
                            onSetAwake: { isAwake in
                                settingsSession.setUserPresentation(
                                    isAwake ? .awake : .tuckedAway,
                                    for: instance.instanceID
                                )
                            },
                            onRename: { nickname in
                                settingsSession.setPetInstanceNickname(
                                    nickname,
                                    for: instance.instanceID
                                )
                            },
                            onMoveForward: {
                                move(instance, by: -1)
                            },
                            onMoveBackward: {
                                move(instance, by: 1)
                            },
                            onRemove: {
                                removingInstanceID = instance.instanceID
                            },
                            onRestore: {
                                runtimeControlSession.restoreInstance(
                                    instance.instanceID
                                )
                            }
                        )
                        .draggable(instance.instanceID.uuidString)
                        .dropDestination(for: String.self) {
                            identifiers, _ in
                            guard
                                let source = identifiers.first,
                                let sourceID = UUID(uuidString: source),
                                sourceID != instance.instanceID
                            else {
                                return false
                            }
                            settingsSession.movePetInstance(
                                sourceID,
                                to: instance.displayOrder
                            )
                            return true
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("활성 펫")
        .sheet(isPresented: $isAddingPet) {
            AddActivePetView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                isPresented: $isAddingPet
            )
        }
        .alert(
            "활성 펫을 제거할까요?",
            isPresented: removalAlertBinding
        ) {
            Button("취소", role: .cancel) {
                removingInstanceID = nil
            }
            Button("제거", role: .destructive) {
                if let removingInstanceID {
                    _ = settingsSession.removePetInstance(
                        removingInstanceID
                    )
                }
                self.removingInstanceID = nil
            }
        } message: {
            Text("화면의 해당 펫과 이 펫만의 설정을 제거합니다. 보관함의 원본 펫은 삭제하지 않습니다.")
        }
        .accessibilityIdentifier("monglepet.settings.activePets")
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("활성 펫")
                    .font(.title2.weight(.semibold))
                Text("각 펫은 위치, 행동, 이동과 말풍선 설정을 독립적으로 사용합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("모두 깨우기", systemImage: "sun.max") {
                setAllPresentations(.awake)
            }
            Button("모두 재우기", systemImage: "moon.zzz") {
                setAllPresentations(.tuckedAway)
            }
            Button(
                runtimeControlSession.isAllPaused
                    ? "모두 계속하기"
                    : "모두 일시정지",
                systemImage: runtimeControlSession.isAllPaused
                    ? "play.fill"
                    : "pause.fill"
            ) {
                runtimeControlSession.setAllPaused(
                    !runtimeControlSession.isAllPaused
                )
            }
            Button("펫 추가", systemImage: "plus") {
                isAddingPet = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!settingsSession.isWritingEnabled)
            .accessibilityIdentifier("monglepet.settings.addActivePet")
        }
        .padding(20)
    }

    private var orderedInstances: [PetInstanceSettings] {
        settingsSession.settings.activePetInstances.sorted {
            $0.displayOrder < $1.displayOrder
        }
    }

    private var noticeMessage: String? {
        settingsSession.saveErrorMessage ?? settingsSession.loadNotice
    }

    private func safeStartBanner(
        pendingInstanceID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("안전 시작", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            Text(
                runtimeControlSession.isUserRequestedSafeMode
                    ? "요청에 따라 모든 펫을 멈춘 안전 모드입니다. 아래 카드에서 한 마리씩 복원하거나 ‘모두 복원’으로 평상시 실행을 다시 시작할 수 있습니다."
                    : "이전 실행이 ‘\(displayName(for: pendingInstanceID))’을 복원하는 중 종료되어 펫을 자동으로 띄우지 않았습니다. 아래 카드에서 한 마리씩 복원하거나 마지막 복원 펫을 제외하고 계속할 수 있습니다."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                if !runtimeControlSession.isUserRequestedSafeMode {
                    Button("마지막 복원 펫 제외하고 계속") {
                        runtimeControlSession.restoreAllExceptPending()
                    }
                }
                Button("모두 복원") {
                    runtimeControlSession.restoreAll()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.orange.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .accessibilityIdentifier("monglepet.settings.safeStart")
    }

    private func resourceWarningBanner(
        _ warning: PetResourceWarning
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("성능 사용량을 확인해 주세요", systemImage: "gauge.high")
                .font(.headline)
            Text(
                "펫 \(warning.activePetCount)마리 중 \(warning.movingPetCount)마리가 이동 중이며 CPU 약 \(Int(warning.cpuPercentage.rounded()))%, 메모리 \(formattedMemory(warning.residentMemoryBytes))를 사용하고 있습니다. 펫 추가는 계속 가능하며 필요하면 모두 일시정지하거나 개별 펫을 재워 주세요."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.yellow.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .accessibilityIdentifier("monglepet.settings.resourceWarning")
    }

    private func displayName(for instanceID: UUID) -> String {
        guard let instance = orderedInstances.first(where: {
            $0.instanceID == instanceID
        }) else {
            return "알 수 없는 펫"
        }
        return instance.nickname ?? item(for: instance).metadata.displayName
    }

    private func formattedMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .memory
        )
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { removingInstanceID != nil },
            set: { isPresented in
                if !isPresented {
                    removingInstanceID = nil
                }
            }
        )
    }

    private func item(for instance: PetInstanceSettings) -> PetLibraryItem {
        petLibrarySession.item(for: instance.petKey)
            ?? petLibrarySession.selectedItem
    }

    private func move(_ instance: PetInstanceSettings, by offset: Int) {
        settingsSession.movePetInstance(
            instance.instanceID,
            to: instance.displayOrder + offset
        )
    }

    private func setAllPresentations(_ presentation: PetPresentation) {
        for instance in orderedInstances {
            settingsSession.setUserPresentation(
                presentation,
                for: instance.instanceID
            )
        }
    }
}

private struct ActivePetCard: View {
    let instance: PetInstanceSettings
    let item: PetLibraryItem
    let profile: BehaviorProfile?
    let isSelected: Bool
    let canRemove: Bool
    let canEdit: Bool
    let canMoveForward: Bool
    let canMoveBackward: Bool
    let isRestored: Bool
    let onSelect: () -> Void
    let onSetAwake: (Bool) -> Void
    let onRename: (String?) -> Void
    let onMoveForward: () -> Void
    let onMoveBackward: () -> Void
    let onRemove: () -> Void
    let onRestore: () -> Void
    @State private var nickname: String

    init(
        instance: PetInstanceSettings,
        item: PetLibraryItem,
        profile: BehaviorProfile?,
        isSelected: Bool,
        canRemove: Bool,
        canEdit: Bool,
        canMoveForward: Bool,
        canMoveBackward: Bool,
        isRestored: Bool,
        onSelect: @escaping () -> Void,
        onSetAwake: @escaping (Bool) -> Void,
        onRename: @escaping (String?) -> Void,
        onMoveForward: @escaping () -> Void,
        onMoveBackward: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onRestore: @escaping () -> Void
    ) {
        self.instance = instance
        self.item = item
        self.profile = profile
        self.isSelected = isSelected
        self.canRemove = canRemove
        self.canEdit = canEdit
        self.canMoveForward = canMoveForward
        self.canMoveBackward = canMoveBackward
        self.isRestored = isRestored
        self.onSelect = onSelect
        self.onSetAwake = onSetAwake
        self.onRename = onRename
        self.onMoveForward = onMoveForward
        self.onMoveBackward = onMoveBackward
        self.onRemove = onRemove
        self.onRestore = onRestore
        _nickname = State(initialValue: instance.nickname ?? "")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PetAnimationPreviewView(
                item: item,
                motionID: item.definition.defaultMotionID
            )
            .frame(width: 84, height: 84)
            .background(
                .quaternary.opacity(0.28),
                in: RoundedRectangle(cornerRadius: 12)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.headline)
                    if isSelected {
                        Text("설정 중")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    Spacer()
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if instance.nickname != nil {
                    Text("원본: \(item.metadata.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label(movementTitle, systemImage: "location")
                    Label(
                        instance.overlay.clickThrough
                            ? "클릭 통과 켜짐"
                            : "직접 상호작용",
                        systemImage: instance.overlay.clickThrough
                            ? "cursorarrow.rays"
                            : "hand.point.up.left"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("구분 이름 (선택)", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveNickname)
                        .disabled(!canEdit)
                        .accessibilityIdentifier(
                            "monglepet.settings.activePetNickname"
                        )
                    Button("저장", action: saveNickname)
                        .disabled(
                            !canEdit
                                || nickname == (instance.nickname ?? "")
                        )
                }
            }

            VStack(spacing: 8) {
                if !isRestored {
                    Button("복원", action: onRestore)
                        .buttonStyle(.borderedProminent)
                }
                Toggle(
                    "",
                    isOn: Binding(
                        get: { instance.presentation == .awake },
                        set: { isAwake in
                            onSetAwake(isAwake)
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isRestored)
                .help(instance.presentation == .awake ? "펫 재우기" : "펫 깨우기")

                HStack(spacing: 4) {
                    Button(action: onMoveForward) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canEdit || !canMoveForward)
                    .help("한 단계 앞으로")
                    Button(action: onMoveBackward) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canEdit || !canMoveBackward)
                    .help("한 단계 뒤로")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canEdit || !canRemove)
                .help(canRemove ? "활성 펫 제거" : "펫은 한 마리 이상 필요합니다")
            }
        }
        .padding(16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .background(
            isSelected
                ? Color.accentColor.opacity(0.09)
                : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.55)
                        : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .onTapGesture(perform: onSelect)
        .onChange(of: instance.nickname) { _, newValue in
            nickname = newValue ?? ""
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monglepet.settings.activePetCard")
    }

    private var displayName: String {
        instance.nickname ?? item.metadata.displayName
    }

    private var movementTitle: String {
        switch profile?.movement.mode ?? .fixed {
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

    private var statusTitle: String {
        if !isRestored {
            return "복원 대기"
        }
        return instance.presentation == .awake ? "깨어 있음" : "자는 중"
    }

    private func saveNickname() {
        onRename(nickname.isEmpty ? nil : nickname)
    }
}

private struct AddActivePetView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @Binding var isPresented: Bool
    @State private var selection: PetLibrarySelection = .builtIn
    @State private var copiesExistingSettings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("활성 펫 추가")
                    .font(.title2.weight(.semibold))
                Text("같은 원본 펫도 여러 마리 추가할 수 있으며 이후 설정은 서로 독립적으로 저장됩니다.")
                    .foregroundStyle(.secondary)
            }

            Picker("추가할 펫", selection: $selection) {
                ForEach(petLibrarySession.items) { item in
                    Text(item.metadata.displayName)
                        .tag(item.selection)
                }
            }

            if let item = selectedItem {
                HStack(spacing: 16) {
                    PetAnimationPreviewView(
                        item: item,
                        motionID: item.definition.defaultMotionID
                    )
                    .frame(width: 112, height: 112)
                    .background(
                        .quaternary.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.metadata.displayName)
                            .font(.headline)
                        Text("제작자 \(item.metadata.author)")
                        Text("애니메이션 \(item.definition.motions.count)개")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Toggle(
                "이미 활성화된 같은 펫의 설정 복사",
                isOn: $copiesExistingSettings
            )
            .disabled(copySourceInstanceID == nil)

            Text(
                copySourceInstanceID == nil
                    ? "같은 펫이 처음 추가되므로 기본 설정으로 시작합니다."
                    : "끄면 기본 설정으로, 켜면 기존 펫의 행동·이동·말풍선 설정을 복사해 시작합니다. 이후 변경은 서로 공유되지 않습니다."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    isPresented = false
                }
                Button("추가") {
                    addPet()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            selection = petLibrarySession.selectedItem.selection
            copiesExistingSettings = copySourceInstanceID != nil
        }
        .onChange(of: selection) { _, _ in
            copiesExistingSettings = copySourceInstanceID != nil
        }
    }

    private var selectedItem: PetLibraryItem? {
        petLibrarySession.items.first { $0.selection == selection }
    }

    private var selectedPetKey: PetBehaviorKey {
        PetBehaviorKey(installationID: selection.installationID)
    }

    private var copySourceInstanceID: UUID? {
        let matching = settingsSession.settings.activePetInstances.filter {
            $0.petKey == selectedPetKey
        }
        return matching.first(where: {
            $0.instanceID == settingsSession.settings.selectedPetInstanceID
        })?.instanceID ?? matching.first?.instanceID
    }

    private func addPet() {
        let sourceID = copiesExistingSettings ? copySourceInstanceID : nil
        guard settingsSession.addPetInstance(
            for: selectedPetKey,
            copyingSettingsFrom: sourceID
        ) != nil else {
            return
        }
        isPresented = false
    }
}
