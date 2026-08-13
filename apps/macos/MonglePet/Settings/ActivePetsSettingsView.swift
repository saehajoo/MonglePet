import SwiftUI

struct ActivePetsSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
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
    let onSelect: () -> Void
    let onSetAwake: (Bool) -> Void
    let onRename: (String?) -> Void
    let onMoveForward: () -> Void
    let onMoveBackward: () -> Void
    let onRemove: () -> Void
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
        onSelect: @escaping () -> Void,
        onSetAwake: @escaping (Bool) -> Void,
        onRename: @escaping (String?) -> Void,
        onMoveForward: @escaping () -> Void,
        onMoveBackward: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.instance = instance
        self.item = item
        self.profile = profile
        self.isSelected = isSelected
        self.canRemove = canRemove
        self.canEdit = canEdit
        self.canMoveForward = canMoveForward
        self.canMoveBackward = canMoveBackward
        self.onSelect = onSelect
        self.onSetAwake = onSetAwake
        self.onRename = onRename
        self.onMoveForward = onMoveForward
        self.onMoveBackward = onMoveBackward
        self.onRemove = onRemove
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
                    Text(instance.presentation == .awake ? "깨어 있음" : "자는 중")
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
