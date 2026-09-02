import AppKit
import Foundation
import SwiftUI

nonisolated enum BehaviorSelectionLabel {
    static func text(for sequence: BehaviorSequence) -> String {
        guard let firstStep = sequence.steps.first else {
            return "애니메이션 없음"
        }
        let animationName = firstStep.motionID
            == PetMotionReference.currentPetDefault
            ? "기본 애니메이션"
            : firstStep.motionID
        guard sequence.steps.count > 1 else {
            return animationName
        }
        return "\(animationName) 외 \(sequence.steps.count - 1)개"
    }
}

enum MovementSettingsContent {
    case stationaryBehavior
    case movement
    case interaction
}

struct MovementSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDefinition: PetDefinition
    let content: MovementSettingsContent
    @State private var displayOptions: [PetMovementDisplayOption] = []

    var body: some View {
        Form {
            if content == .stationaryBehavior {
                stationaryBehaviorSection
            }

            if content == .movement {
                Section("이동 방식") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(
                        [
                            PetMovementMode.fixed,
                            .freeRoaming,
                            .cursorFollowing,
                            .cursorAvoiding
                        ],
                        id: \.self
                    ) { mode in
                        movementModeCard(mode)
                    }
                }
                .accessibilityIdentifier("monglepet.settings.movementMode")

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if movement.mode != .fixed {
                Section("기본 이동 설정") {
                    if movement.mode != .cursorAvoiding
                        || movement.cursorAvoidingIdleBehavior == .freeRoaming {
                        movementSlider(
                            title: movement.mode == .cursorAvoiding
                                ? "평상시 이동 속도"
                                : "이동 속도",
                            value: movementSpeedBinding,
                            range: AppSettingsLimits.minimumMovementSpeed
                                ... AppSettingsLimits.maximumMovementSpeed,
                            step: 10,
                            valueText:
                                "\(Int(movement.speed.rounded())) pt/s",
                            accessibilityIdentifier:
                                "monglepet.settings.movementSpeed"
                        )
                    }
                    movementSlider(
                        title: "정지 반경",
                        value: movementStopRadiusBinding,
                        range: AppSettingsLimits.minimumMovementStopRadius
                            ... AppSettingsLimits.maximumMovementStopRadius,
                        step: 4,
                        valueText: "\(Int(movement.stopRadius.rounded())) pt",
                        accessibilityIdentifier:
                            "monglepet.settings.movementStopRadius"
                    )
                    Text("목표에 가까워졌을 때 움직임을 멈추는 범위입니다. 흔들림이 보일 때만 조절해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                movementBoundarySection
            }

            switch movement.mode {
            case .fixed:
                Section {
                    Text(
                        settingsSession.settings.overlay.clickThrough
                            ? "클릭 통과가 켜져 있어 펫을 드래그할 수 없습니다. 일반 탭에서 클릭 통과를 끄면 위치를 옮길 수 있습니다."
                            : "펫을 직접 드래그한 위치에 그대로 둡니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            case .cursorFollowing:
                Section("마우스 따라가기") {
                    movementSlider(
                        title: "마우스와 거리",
                        value: cursorDistanceBinding,
                        range: AppSettingsLimits.minimumCursorDistance
                            ... AppSettingsLimits.maximumCursorDistance,
                        step: 8,
                        valueText: "\(Int(movement.cursorDistance.rounded())) pt",
                        accessibilityIdentifier: "monglepet.settings.cursorDistance"
                    )

                    movementAnimationEditor(
                        for: .cursorFollowing,
                        accessibilityPrefix:
                            "monglepet.settings.cursorFollowing"
                    )

                    Text("마우스 포인터와 지정한 거리를 유지하며 화면 안에서 따라갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .freeRoaming:
                Section("자유 이동") {
                    dwellEditor(
                        title: "목표 도착 후 머무는 시간",
                        accessibilityPrefix:
                            "monglepet.settings.freeRoamingDwell"
                    )

                    Toggle(
                        "현재 사용 중인 앱의 창 근처를 우선",
                        isOn: prefersFrontmostWindowBinding
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.prefersFrontmostWindow"
                    )

                    movementAnimationEditor(
                        for: .freeRoaming,
                        accessibilityPrefix:
                            "monglepet.settings.freeRoaming"
                    )

                    Text("창 정보를 얻을 수 없거나 전체 화면이면 현재 화면 안에서 안전한 위치를 선택합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .cursorAvoiding:
                Section("마우스 도망가기") {
                    Picker(
                        "평상시 행동",
                        selection: cursorAvoidingIdleBehaviorBinding
                    ) {
                        Text("가만히 있기")
                            .tag(CursorAvoidingIdleBehavior.stationary)
                        Text("자유 이동")
                            .tag(CursorAvoidingIdleBehavior.freeRoaming)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(
                        "monglepet.settings.cursorAvoidingIdleBehavior"
                    )

                    movementSlider(
                        title: "마우스 감지 거리",
                        value: cursorAvoidingDetectionDistanceBinding,
                        range:
                            AppSettingsLimits
                                .minimumCursorAvoidingDetectionDistance
                            ... AppSettingsLimits
                                .maximumCursorAvoidingDetectionDistance,
                        step: 8,
                        valueText:
                            "\(Int(movement.cursorAvoidingDetectionDistance.rounded())) pt",
                        accessibilityIdentifier:
                            "monglepet.settings.cursorAvoidingDetectionDistance"
                    )
                    movementSlider(
                        title: "도망가는 속도",
                        value: cursorAvoidingSpeedBinding,
                        range: AppSettingsLimits.minimumMovementSpeed
                            ... AppSettingsLimits.maximumMovementSpeed,
                        step: 10,
                        valueText:
                            "\(Int(movement.cursorAvoidingSpeed.rounded())) pt/s",
                        accessibilityIdentifier:
                            "monglepet.settings.cursorAvoidingSpeed"
                    )

                    if movement.cursorAvoidingIdleBehavior == .freeRoaming {
                        dwellEditor(
                            title: "평상시 머무는 시간",
                            accessibilityPrefix:
                                "monglepet.settings.cursorAvoidingDwell"
                        )
                        Toggle(
                            "현재 사용 중인 앱의 창 근처를 우선",
                            isOn: prefersFrontmostWindowBinding
                        )
                        movementAnimationEditor(
                            for: .freeRoaming,
                            title: "평상시 자유 이동 행동",
                            accessibilityPrefix:
                                "monglepet.settings.cursorAvoidingRoaming"
                        )
                    }

                    movementAnimationEditor(
                        for: .cursorAvoiding,
                        title: "도망가기 행동",
                        accessibilityPrefix:
                            "monglepet.settings.cursorAvoiding"
                    )

                    Text("클릭 통과 여부와 관계없이 마우스를 피해 이동합니다. 안전한 거리까지 멀어지면 선택한 평상시 행동으로 돌아갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            }

            if content == .interaction {
                Section("상호작용") {
                if movement.mode == .cursorAvoiding {
                    LabeledContent("쓰다듬기", value: "사용하지 않음")
                    Text("마우스 도망가기 모드에서는 접근 반응과 충돌하지 않도록 쓰다듬기를 실행하지 않습니다. 다른 이동 모드에서 선택한 설정은 유지됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    behaviorPicker(
                        title: "쓰다듬기 행동",
                        selection: pettingMotionBinding,
                        noneLabel: "반응 없음",
                        accessibilityIdentifier:
                            "monglepet.settings.pettingMotion"
                    )
                    Text("펫의 보이는 부분에 마우스를 잠시 올리면 선택한 행동을 한 번 끝까지 재생한 뒤 기존 행동으로 돌아갑니다. 클릭 통과 중에도 사용할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            }

            if content == .movement {
                Section {
                    Text("이동 방식은 현재 펫에 저장되고 이동 범위는 이 Mac의 모든 펫에 공통으로 적용됩니다. 마우스 위치와 앱 창 위치는 저장하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!settingsSession.isWritingEnabled)
        .accessibilityIdentifier("monglepet.settings.movementRoot")
        .onAppear(perform: reloadDisplayOptions)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            reloadDisplayOptions()
        }
    }

    private var stationaryBehaviorSection: some View {
        Section("평상시 행동") {
            Picker("선택 방식", selection: stationaryBehaviorModeBinding) {
                Text("하나 선택")
                    .tag(StationaryBehaviorMode.fixed.rawValue)
                Text("랜덤 선택")
                    .tag(StationaryBehaviorMode.random.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "monglepet.settings.stationaryBehaviorMode"
            )

            if settingsSession.settings.stationaryBehaviorMode == .fixed {
                Picker("멈춰 있을 때 행동", selection: stationarySequenceBinding) {
                    ForEach(settingsSession.settings.sequences) { sequence in
                        Text(sequence.displayName).tag(sequence.id)
                    }
                }
                .accessibilityIdentifier(
                    "monglepet.settings.stationaryBehavior"
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(settingsSession.settings.sequences) { sequence in
                        Button {
                            toggleRandomSequence(sequence.id)
                        } label: {
                            HStack {
                                Image(
                                    systemName: randomSequenceIDs.contains(
                                        sequence.id
                                    ) ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    randomSequenceIDs.contains(sequence.id)
                                        ? Color.accentColor : .secondary
                                )
                                Text(sequence.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "monglepet.settings.stationaryRandom.\(sequence.id)"
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Text(stationaryBehaviorDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var movement: PetMovementSettings {
        settingsSession.settings.movementSettings
    }

    private var movementBoundary: MovementBoundarySettings {
        settingsSession.settings.overlay.movementBoundary
    }

    @ViewBuilder
    private var movementBoundarySection: some View {
        Section {
            Picker("이동 범위", selection: movementBoundaryModeBinding) {
                Text("모든 화면").tag(MovementBoundaryMode.allDisplays)
                Text("선택 모니터").tag(MovementBoundaryMode.selectedDisplay)
                Text("사용자 지정").tag(MovementBoundaryMode.customArea)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("monglepet.settings.movementBoundaryMode")

            if movementBoundary.mode != .allDisplays {
                if displayOptions.isEmpty {
                    Text("사용 가능한 모니터를 찾을 수 없어 모든 화면을 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "대상 모니터",
                        selection: movementBoundaryDisplayBinding
                    ) {
                        ForEach(displayOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                        if let missingIdentifier =
                            missingBoundaryScreenIdentifier {
                            Text("연결되지 않은 모니터")
                                .tag(missingIdentifier)
                        }
                    }
                    .accessibilityIdentifier(
                        "monglepet.settings.movementBoundaryDisplay"
                    )
                }
            }

            if movementBoundary.mode == .customArea {
                let rect = movementBoundary.normalizedRect ?? .recommended
                percentageSlider(
                    title: "왼쪽 여백",
                    value: customAreaXBinding,
                    range: 0...max(0, 1 - rect.width),
                    accessibilityIdentifier:
                        "monglepet.settings.movementBoundaryX"
                )
                percentageSlider(
                    title: "아래쪽 여백",
                    value: customAreaYBinding,
                    range: 0...max(0, 1 - rect.height),
                    accessibilityIdentifier:
                        "monglepet.settings.movementBoundaryY"
                )
                percentageSlider(
                    title: "영역 너비",
                    value: customAreaWidthBinding,
                    range: min(0.05, 1 - rect.x)...(1 - rect.x),
                    accessibilityIdentifier:
                        "monglepet.settings.movementBoundaryWidth"
                )
                percentageSlider(
                    title: "영역 높이",
                    value: customAreaHeightBinding,
                    range: min(0.05, 1 - rect.y)...(1 - rect.y),
                    accessibilityIdentifier:
                        "monglepet.settings.movementBoundaryHeight"
                )
            }

            Text(boundaryDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            HStack(spacing: 8) {
                Text("이동 범위")
                Text("모든 펫 공통")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var movementModeBinding: Binding<PetMovementMode> {
        Binding(
            get: { movement.mode },
            set: { apply(.mode($0)) }
        )
    }

    private var stationaryBehaviorModeBinding: Binding<String> {
        Binding(
            get: {
                settingsSession.settings.stationaryBehaviorMode.rawValue
            },
            set: { rawValue in
                guard let mode = StationaryBehaviorMode(rawValue: rawValue)
                else { return }
                settingsSession.setStationaryBehaviorMode(mode)
            }
        )
    }

    private var stationarySequenceBinding: Binding<String> {
        Binding(
            get: {
                settingsSession.settings.stationarySequenceID
                    ?? BuiltInBehaviorPresets.defaultSequenceID
            },
            set: { sequenceID in
                settingsSession.setStationarySequenceID(
                    sequenceID == BuiltInBehaviorPresets.defaultSequenceID
                        ? nil : sequenceID
                )
            }
        )
    }

    private var randomSequenceIDs: [String] {
        settingsSession.settings.randomSequenceIDs
    }

    private func toggleRandomSequence(_ sequenceID: String) {
        var ids = randomSequenceIDs
        if let index = ids.firstIndex(of: sequenceID) {
            ids.remove(at: index)
        } else {
            ids.append(sequenceID)
        }
        settingsSession.setRandomSequenceIDs(ids)
    }

    private var stationaryBehaviorDescription: String {
        switch settingsSession.settings.stationaryBehaviorMode {
        case .fixed:
            "펫이 이동하지 않고 적용할 규칙도 없을 때 선택한 행동의 모든 단계를 계속 반복합니다. 단계별 반복 횟수는 한 순환의 길이를 정합니다."
        case .random:
            randomSequenceIDs.isEmpty
                ? "행동을 하나 이상 선택해 주세요. 선택 전에는 기본 행동을 표시합니다."
                : "선택한 행동을 모두 한 번씩 섞어 재생합니다. 입력 없음과 앱 사용 규칙도 함께 적용됩니다."
        }
    }

    private var cursorAvoidingIdleBehaviorBinding:
        Binding<CursorAvoidingIdleBehavior> {
        Binding(
            get: { movement.cursorAvoidingIdleBehavior },
            set: { apply(.cursorAvoidingIdleBehavior($0)) }
        )
    }

    private var cursorAvoidingDetectionDistanceBinding: Binding<Double> {
        Binding(
            get: { movement.cursorAvoidingDetectionDistance },
            set: {
                apply(.cursorAvoidingDetectionDistance($0), persist: false)
            }
        )
    }

    private var cursorAvoidingSpeedBinding: Binding<Double> {
        Binding(
            get: { movement.cursorAvoidingSpeed },
            set: { apply(.cursorAvoidingSpeed($0), persist: false) }
        )
    }

    private var movementBoundaryModeBinding: Binding<MovementBoundaryMode> {
        Binding(
            get: { movementBoundary.mode },
            set: { mode in
                let selectedScreenIdentifier =
                    validBoundaryScreenIdentifier
                        ?? displayOptions.first?.id
                guard mode == .allDisplays
                    || selectedScreenIdentifier != nil else {
                    return
                }
                settingsSession.setMovementBoundary(
                    MovementBoundarySettings(
                        mode: mode,
                        screenIdentifier: selectedScreenIdentifier,
                        normalizedRect: mode == .customArea
                            ? movementBoundary.normalizedRect ?? .recommended
                            : movementBoundary.normalizedRect
                    )
                )
            }
        )
    }

    private var movementBoundaryDisplayBinding: Binding<String> {
        Binding(
            get: {
                movementBoundary.screenIdentifier
                    ?? displayOptions.first?.id
                    ?? ""
            },
            set: { screenIdentifier in
                guard !screenIdentifier.isEmpty else {
                    return
                }
                settingsSession.setMovementBoundary(
                    MovementBoundarySettings(
                        mode: movementBoundary.mode,
                        screenIdentifier: screenIdentifier,
                        normalizedRect: movementBoundary.mode == .customArea
                            ? movementBoundary.normalizedRect ?? .recommended
                            : movementBoundary.normalizedRect
                    )
                )
            }
        )
    }

    private var customAreaXBinding: Binding<Double> {
        customAreaBinding(.x)
    }

    private var customAreaYBinding: Binding<Double> {
        customAreaBinding(.y)
    }

    private var customAreaWidthBinding: Binding<Double> {
        customAreaBinding(.width)
    }

    private var customAreaHeightBinding: Binding<Double> {
        customAreaBinding(.height)
    }

    private var movementSpeedBinding: Binding<Double> {
        Binding(
            get: { movement.speed },
            set: { apply(.speed($0), persist: false) }
        )
    }

    private var movementStopRadiusBinding: Binding<Double> {
        Binding(
            get: { movement.stopRadius },
            set: { apply(.stopRadius($0), persist: false) }
        )
    }

    private var cursorDistanceBinding: Binding<Double> {
        Binding(
            get: { movement.cursorDistance },
            set: { apply(.cursorDistance($0), persist: false) }
        )
    }

    private var freeRoamingDwellSecondsBinding: Binding<Double> {
        Binding(
            get: {
                Double(movement.freeRoamingDwellMilliseconds) / 1_000
            },
            set: {
                apply(
                    .freeRoamingDwellMilliseconds(
                        Int64(($0 * 1_000).rounded())
                    )
                )
            }
        )
    }

    private var freeRoamingDwellMinimumSecondsBinding: Binding<Double> {
        Binding(
            get: {
                Double(movement.freeRoamingDwellMinimumMilliseconds) / 1_000
            },
            set: {
                apply(
                    .freeRoamingDwellMinimumMilliseconds(
                        Int64(($0 * 1_000).rounded())
                    )
                )
            }
        )
    }

    private var randomizesFreeRoamingDwellBinding: Binding<Bool> {
        Binding(
            get: { movement.randomizesFreeRoamingDwell },
            set: { apply(.randomizesFreeRoamingDwell($0)) }
        )
    }

    private var prefersFrontmostWindowBinding: Binding<Bool> {
        Binding(
            get: { movement.prefersFrontmostWindow },
            set: { apply(.prefersFrontmostWindow($0)) }
        )
    }

    private var pettingMotionBinding: Binding<String> {
        Binding(
            get: { settingsSession.settings.pettingMotionID ?? "" },
            set: {
                settingsSession.setPettingMotionID(
                    $0.isEmpty ? nil : $0
                )
            }
        )
    }

    private var modeDescription: String {
        switch movement.mode {
        case .fixed:
            "사용자가 옮긴 위치를 유지하며 자동으로 움직이지 않습니다."
        case .cursorFollowing:
            "마우스 포인터를 부드럽게 따라가며 설정한 거리에서 멈춥니다."
        case .freeRoaming:
            "화면 안의 안전한 목표를 골라 이동하고 잠시 머문 뒤 다시 움직입니다."
        case .cursorAvoiding:
            "평상시에는 선택한 행동을 하다가 마우스가 가까워지면 반대 방향으로 도망갑니다."
        }
    }

    private var boundaryDescription: String {
        switch movementBoundary.mode {
        case .allDisplays:
            "연결된 모든 모니터 안에서 이동합니다."
        case .selectedDisplay:
            missingBoundaryScreenIdentifier == nil
                ? "선택한 모니터 안에서만 이동합니다."
                : "저장된 모니터가 연결되지 않아 현재는 모든 화면을 사용합니다."
        case .customArea:
            missingBoundaryScreenIdentifier == nil
                ? "선택한 모니터의 지정 영역 안에서만 이동합니다."
                : "저장된 모니터가 연결되지 않아 현재는 모든 화면을 사용합니다."
        }
    }

    private var validBoundaryScreenIdentifier: String? {
        guard
            let screenIdentifier = movementBoundary.screenIdentifier,
            displayOptions.contains(where: { $0.id == screenIdentifier })
        else {
            return nil
        }
        return screenIdentifier
    }

    private var missingBoundaryScreenIdentifier: String? {
        guard let screenIdentifier = movementBoundary.screenIdentifier,
              !displayOptions.contains(where: { $0.id == screenIdentifier })
        else {
            return nil
        }
        return screenIdentifier
    }

    @ViewBuilder
    private func dwellEditor(
        title: String,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Text("시간 방식")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Picker(
                    "머무는 시간 방식",
                    selection: dwellTimingModeBinding
                ) {
                    Text("고정").tag(DwellTimingMode.fixed)
                    Text("랜덤").tag(DwellTimingMode.random)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                .accessibilityIdentifier("\(accessibilityPrefix).mode")
            }

            if movement.randomizesFreeRoamingDwell {
                dwellInputRow(
                    title: "최소 시간",
                    value: freeRoamingDwellMinimumSecondsBinding,
                    range: freeRoamingDwellSecondsRange.lowerBound
                        ... freeRoamingDwellSecondsBinding.wrappedValue,
                    accessibilityIdentifier: "\(accessibilityPrefix).minimum"
                )
                dwellInputRow(
                    title: "최대 시간",
                    value: freeRoamingDwellSecondsBinding,
                    range: freeRoamingDwellMinimumSecondsBinding.wrappedValue
                        ... freeRoamingDwellSecondsRange.upperBound,
                    accessibilityIdentifier: "\(accessibilityPrefix).maximum"
                )
                Text("목표 위치에 도착할 때마다 최소~최대 범위에서 한 번만 시간을 뽑습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                dwellInputRow(
                    title: "머무는 시간",
                    value: freeRoamingDwellSecondsBinding,
                    range: freeRoamingDwellSecondsRange,
                    accessibilityIdentifier: accessibilityPrefix
                )
                Text("목표 위치에 도착한 뒤 \(dwellText(freeRoamingDwellSecondsBinding.wrappedValue)) 동안 머뭅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func dwellInputRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)
            Spacer(minLength: 8)

            Button {
                value.wrappedValue = max(
                    value.wrappedValue - 0.5,
                    range.lowerBound
                )
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 30, height: 28)
            .disabled(value.wrappedValue <= range.lowerBound)
            .accessibilityLabel("\(title) 줄이기")
            .accessibilityIdentifier(
                "\(accessibilityIdentifier).decrement"
            )

            TextField(
                "시간",
                value: value,
                format: .number.precision(.fractionLength(0...1))
            )
            .frame(width: 92)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .accessibilityIdentifier(
                "\(accessibilityIdentifier).value"
            )

            Text("초")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            Button {
                value.wrappedValue = min(
                    value.wrappedValue + 0.5,
                    range.upperBound
                )
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 30, height: 28)
            .disabled(value.wrappedValue >= range.upperBound)
            .accessibilityLabel("\(title) 늘리기")
            .accessibilityIdentifier(
                "\(accessibilityIdentifier).increment"
            )
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var dwellTimingModeBinding: Binding<DwellTimingMode> {
        Binding(
            get: {
                movement.randomizesFreeRoamingDwell ? .random : .fixed
            },
            set: { mode in
                randomizesFreeRoamingDwellBinding.wrappedValue =
                    mode == .random
            }
        )
    }

    private func dwellText(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))초"
        }
        return String(format: "%.1f초", seconds)
    }

    private var freeRoamingDwellSecondsRange: ClosedRange<Double> {
        Double(AppSettingsLimits.minimumFreeRoamingDwellMilliseconds) / 1_000
            ... Double(
                AppSettingsLimits.maximumFreeRoamingDwellMilliseconds
            ) / 1_000
    }

    private func movementSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(title)
            Slider(
                value: value,
                in: range,
                step: step,
                onEditingChanged: persistSliderWhenEditingEnds
            )
            .accessibilityIdentifier(accessibilityIdentifier)
            Text(valueText)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func movementModeCard(
        _ mode: PetMovementMode
    ) -> some View {
        let isSelected = movement.mode == mode
        return Button {
            movementModeBinding.wrappedValue = mode
        } label: {
            HStack(spacing: 10) {
                Image(systemName: movementModeSymbol(mode))
                    .font(.title3)
                    .frame(width: 22)
                Text(movementModeTitle(mode))
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.7)
                            : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "monglepet.settings.movementMode.\(movementModeIdentifier(mode))"
        )
    }

    private func movementModeTitle(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed: "위치 고정"
        case .cursorFollowing: "마우스 따라가기"
        case .freeRoaming: "자유 이동"
        case .cursorAvoiding: "마우스 도망가기"
        }
    }

    private func movementModeSymbol(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed: "pin.fill"
        case .cursorFollowing: "cursorarrow.motionlines"
        case .freeRoaming: "arrow.triangle.branch"
        case .cursorAvoiding: "figure.run"
        }
    }

    private func movementModeIdentifier(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        case .cursorAvoiding: "cursorAvoiding"
        }
    }

    private func percentageSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(title)
            Slider(
                value: value,
                in: range,
                step: 0.05,
                onEditingChanged: persistSliderWhenEditingEnds
            )
            .accessibilityIdentifier(accessibilityIdentifier)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func behaviorPicker(
        title: String,
        selection: Binding<String>,
        noneLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(noneLabel).tag("")
            ForEach(behaviorIDs(for: selection.wrappedValue), id: \.self) {
                behaviorID in
                Text(behaviorLabel(for: behaviorID)).tag(behaviorID)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func movementAnimationEditor(
        for mode: PetMovementMode,
        title: String = "이동 행동",
        accessibilityPrefix: String
    ) -> some View {
        let animation = movementAnimation(for: mode)
        return VStack(alignment: .leading, spacing: 10) {
            Picker(
                title,
                selection: directionalAnimationBinding(for: mode)
            ) {
                Text("공통 하나").tag(false)
                Text("방향별").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(accessibilityPrefix)AnimationStyle")

            behaviorPicker(
                title: animation.usesDirectionalMotions
                    ? "기본 이동 행동"
                    : "이동 중 행동",
                selection: fallbackMotionBinding(for: mode),
                noneLabel: "기존 행동 유지",
                accessibilityIdentifier: "\(accessibilityPrefix)FallbackMotion"
            )

            if animation.usesDirectionalMotions {
                Divider()

                Text("방향별 행동")
                    .font(.subheadline.weight(.semibold))

                ForEach(
                    MovementDirection.cardinalCases,
                    id: \.self
                ) { direction in
                    behaviorPicker(
                        title: directionLabel(direction),
                        selection: directionMotionBinding(
                            direction,
                            for: mode
                        ),
                        noneLabel: "자동 선택",
                        accessibilityIdentifier:
                            "\(accessibilityPrefix)Direction\(direction.rawValue)"
                    )
                }

                Toggle(
                    "대각선도 따로 설정",
                    isOn: diagonalAnimationBinding(for: mode)
                )
                .accessibilityIdentifier(
                    "\(accessibilityPrefix)UsesDiagonals"
                )

                if animation.usesDiagonalMotions {
                    ForEach(
                        MovementDirection.diagonalCases,
                        id: \.self
                    ) { direction in
                        behaviorPicker(
                            title: directionLabel(direction),
                            selection: directionMotionBinding(
                                direction,
                                for: mode
                            ),
                            noneLabel: "자동 선택",
                            accessibilityIdentifier:
                                "\(accessibilityPrefix)Direction\(direction.rawValue)"
                        )
                    }
                }

                Text(
                    "자동 선택 방향은 실제 이동과 같은 쪽에 지정된 행동을 사용합니다. 지정된 방향이 없으면 기본 이동 행동이나 기존 행동으로 돌아갑니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func movementAnimation(
        for mode: PetMovementMode
    ) -> MovementAnimationSettings {
        switch mode {
        case .fixed:
            .default
        case .cursorFollowing:
            movement.cursorFollowingAnimation
        case .freeRoaming:
            movement.freeRoamingAnimation
        case .cursorAvoiding:
            movement.cursorAvoidingAnimation
        }
    }

    private func directionalAnimationBinding(
        for mode: PetMovementMode
    ) -> Binding<Bool> {
        Binding(
            get: { movementAnimation(for: mode).usesDirectionalMotions },
            set: { usesDirectionalMotions in
                updateMovementAnimation(for: mode) { current in
                    MovementAnimationSettings(
                        fallbackMotionID: current.fallbackMotionID,
                        usesDirectionalMotions: usesDirectionalMotions,
                        usesDiagonalMotions: usesDirectionalMotions
                            && current.usesDiagonalMotions,
                        directionMotionIDs: current.directionMotionIDs
                    )
                }
            }
        )
    }

    private func diagonalAnimationBinding(
        for mode: PetMovementMode
    ) -> Binding<Bool> {
        Binding(
            get: { movementAnimation(for: mode).usesDiagonalMotions },
            set: { usesDiagonalMotions in
                updateMovementAnimation(for: mode) { current in
                    MovementAnimationSettings(
                        fallbackMotionID: current.fallbackMotionID,
                        usesDirectionalMotions: true,
                        usesDiagonalMotions: usesDiagonalMotions,
                        directionMotionIDs: current.directionMotionIDs
                    )
                }
            }
        )
    }

    private func fallbackMotionBinding(
        for mode: PetMovementMode
    ) -> Binding<String> {
        Binding(
            get: {
                movementAnimation(for: mode).fallbackMotionID ?? ""
            },
            set: { motionID in
                updateMovementAnimation(for: mode) { current in
                    MovementAnimationSettings(
                        fallbackMotionID:
                            motionID.isEmpty ? nil : motionID,
                        usesDirectionalMotions:
                            current.usesDirectionalMotions,
                        usesDiagonalMotions: current.usesDiagonalMotions,
                        directionMotionIDs: current.directionMotionIDs
                    )
                }
            }
        )
    }

    private func directionMotionBinding(
        _ direction: MovementDirection,
        for mode: PetMovementMode
    ) -> Binding<String> {
        Binding(
            get: {
                movementAnimation(for: mode).directionMotionIDs[direction]
                    ?? ""
            },
            set: { motionID in
                updateMovementAnimation(for: mode) { current in
                    MovementAnimationSettings(
                        fallbackMotionID: current.fallbackMotionID,
                        usesDirectionalMotions:
                            current.usesDirectionalMotions,
                        usesDiagonalMotions: current.usesDiagonalMotions,
                        directionMotionIDs:
                            current.directionMotionIDs.replacing(
                                direction,
                                with: motionID.isEmpty ? nil : motionID
                            )
                    )
                }
            }
        )
    }

    private func updateMovementAnimation(
        for mode: PetMovementMode,
        transform: (MovementAnimationSettings) -> MovementAnimationSettings
    ) {
        let animation = transform(movementAnimation(for: mode))
        switch mode {
        case .fixed:
            return
        case .cursorFollowing:
            apply(.cursorFollowingAnimation(animation))
        case .freeRoaming:
            apply(.freeRoamingAnimation(animation))
        case .cursorAvoiding:
            apply(.cursorAvoidingAnimation(animation))
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

    private func behaviorIDs(for selectedBehaviorID: String) -> [String] {
        var behaviorIDs = settingsSession.settings.sequences.map(\.id)
        if !selectedBehaviorID.isEmpty,
           !behaviorIDs.contains(selectedBehaviorID) {
            behaviorIDs.append(selectedBehaviorID)
        }
        return behaviorIDs
    }

    private func behaviorLabel(for behaviorID: String) -> String {
        guard let sequence = settingsSession.settings.sequences.first(where: {
            $0.id == behaviorID
        }) else {
            return "\(behaviorID) (찾을 수 없음)"
        }
        return BehaviorSelectionLabel.text(for: sequence)
    }

    private func persistSliderWhenEditingEnds(_ isEditing: Bool) {
        if !isEditing {
            settingsSession.persistCurrentSettings()
        }
    }

    private func customAreaBinding(
        _ field: CustomAreaField
    ) -> Binding<Double> {
        Binding(
            get: {
                let rect = movementBoundary.normalizedRect ?? .recommended
                return switch field {
                case .x:
                    rect.x
                case .y:
                    rect.y
                case .width:
                    rect.width
                case .height:
                    rect.height
                }
            },
            set: { newValue in
                let current = movementBoundary.normalizedRect ?? .recommended
                let rect: NormalizedMovementRect
                switch field {
                case .x:
                    rect = NormalizedMovementRect(
                        x: min(max(newValue, 0), 1 - current.width),
                        y: current.y,
                        width: current.width,
                        height: current.height
                    )
                case .y:
                    rect = NormalizedMovementRect(
                        x: current.x,
                        y: min(max(newValue, 0), 1 - current.height),
                        width: current.width,
                        height: current.height
                    )
                case .width:
                    rect = NormalizedMovementRect(
                        x: current.x,
                        y: current.y,
                        width: min(max(newValue, 0.01), 1 - current.x),
                        height: current.height
                    )
                case .height:
                    rect = NormalizedMovementRect(
                        x: current.x,
                        y: current.y,
                        width: current.width,
                        height: min(max(newValue, 0.01), 1 - current.y)
                    )
                }
                guard let screenIdentifier =
                    movementBoundary.screenIdentifier
                        ?? displayOptions.first?.id else {
                    return
                }
                settingsSession.setMovementBoundary(
                    MovementBoundarySettings(
                        mode: .customArea,
                        screenIdentifier: screenIdentifier,
                        normalizedRect: rect
                    ),
                    persist: false
                )
            }
        )
    }

    private func reloadDisplayOptions() {
        displayOptions = AppKitDisplayLayoutReader.currentDisplayOptions()
    }

    private func apply(
        _ edit: MovementEdit,
        persist: Bool = true
    ) {
        let current = movement
        var mode = current.mode
        var following = current.cursorFollowing
        var roaming = current.freeRoaming
        var avoiding = current.cursorAvoiding

        func replacingRoaming(
            _ source: FreeRoamingMovementSettings,
            speed: Double? = nil,
            stopRadius: Double? = nil,
            dwell: Int64? = nil,
            randomizesDwell: Bool? = nil,
            minimumDwell: Int64? = nil,
            prefersFrontmostWindow: Bool? = nil,
            animation: MovementAnimationSettings? = nil
        ) -> FreeRoamingMovementSettings {
            let maximum = dwell ?? source.dwellMilliseconds
            return FreeRoamingMovementSettings(
                speed: speed ?? source.speed,
                stopRadius: stopRadius ?? source.stopRadius,
                dwellMilliseconds: maximum,
                randomizesDwell: randomizesDwell ?? source.randomizesDwell,
                dwellMinimumMilliseconds: min(
                    minimumDwell ?? source.dwellMinimumMilliseconds,
                    maximum
                ),
                prefersFrontmostWindow: prefersFrontmostWindow
                    ?? source.prefersFrontmostWindow,
                animation: animation ?? source.animation
            )
        }

        func replacingAvoiding(
            idleBehavior: CursorAvoidingIdleBehavior? = nil,
            detectionDistance: Double? = nil,
            speed: Double? = nil,
            stopRadius: Double? = nil,
            animation: MovementAnimationSettings? = nil,
            idleFreeRoaming: FreeRoamingMovementSettings? = nil
        ) -> CursorAvoidingMovementSettings {
            CursorAvoidingMovementSettings(
                idleBehavior: idleBehavior ?? avoiding.idleBehavior,
                detectionDistance: detectionDistance
                    ?? avoiding.detectionDistance,
                speed: speed ?? avoiding.speed,
                stopRadius: stopRadius ?? avoiding.stopRadius,
                animation: animation ?? avoiding.animation,
                idleFreeRoaming: idleFreeRoaming
                    ?? avoiding.idleFreeRoaming
            )
        }

        func updateActiveRoaming(
            _ transform: (FreeRoamingMovementSettings)
                -> FreeRoamingMovementSettings
        ) {
            if current.mode == .cursorAvoiding {
                avoiding = replacingAvoiding(
                    idleFreeRoaming: transform(avoiding.idleFreeRoaming)
                )
            } else {
                roaming = transform(roaming)
            }
        }

        switch edit {
        case let .mode(value):
            mode = value
        case let .speed(value):
            switch current.mode {
            case .cursorFollowing:
                following = CursorFollowingMovementSettings(
                    speed: value,
                    cursorDistance: following.cursorDistance,
                    stopRadius: following.stopRadius,
                    animation: following.animation
                )
            case .freeRoaming, .fixed:
                roaming = replacingRoaming(roaming, speed: value)
            case .cursorAvoiding:
                updateActiveRoaming { replacingRoaming($0, speed: value) }
            }
        case let .cursorDistance(value):
            following = CursorFollowingMovementSettings(
                speed: following.speed,
                cursorDistance: value,
                stopRadius: following.stopRadius,
                animation: following.animation
            )
        case let .stopRadius(value):
            switch current.mode {
            case .cursorFollowing:
                following = CursorFollowingMovementSettings(
                    speed: following.speed,
                    cursorDistance: following.cursorDistance,
                    stopRadius: value,
                    animation: following.animation
                )
            case .freeRoaming, .fixed:
                roaming = replacingRoaming(roaming, stopRadius: value)
            case .cursorAvoiding:
                avoiding = replacingAvoiding(stopRadius: value)
            }
        case let .freeRoamingDwellMilliseconds(value):
            let maximum = min(
                max(
                    value,
                    AppSettingsLimits.minimumFreeRoamingDwellMilliseconds
                ),
                AppSettingsLimits.maximumFreeRoamingDwellMilliseconds
            )
            updateActiveRoaming { replacingRoaming($0, dwell: maximum) }
        case let .randomizesFreeRoamingDwell(value):
            updateActiveRoaming {
                replacingRoaming($0, randomizesDwell: value)
            }
        case let .freeRoamingDwellMinimumMilliseconds(value):
            updateActiveRoaming {
                replacingRoaming(
                    $0,
                    minimumDwell: min(
                        max(
                            value,
                            AppSettingsLimits
                                .minimumFreeRoamingDwellMilliseconds
                        ),
                        $0.dwellMilliseconds
                    )
                )
            }
        case let .prefersFrontmostWindow(value):
            updateActiveRoaming {
                replacingRoaming($0, prefersFrontmostWindow: value)
            }
        case let .cursorFollowingAnimation(value):
            following = CursorFollowingMovementSettings(
                speed: following.speed,
                cursorDistance: following.cursorDistance,
                stopRadius: following.stopRadius,
                animation: value
            )
        case let .freeRoamingAnimation(value):
            updateActiveRoaming { replacingRoaming($0, animation: value) }
        case let .cursorAvoidingIdleBehavior(value):
            avoiding = replacingAvoiding(idleBehavior: value)
        case let .cursorAvoidingDetectionDistance(value):
            avoiding = replacingAvoiding(detectionDistance: value)
        case let .cursorAvoidingSpeed(value):
            avoiding = replacingAvoiding(speed: value)
        case let .cursorAvoidingAnimation(value):
            avoiding = replacingAvoiding(animation: value)
        }

        settingsSession.setMovementSettings(
            PetMovementSettings(
                mode: mode,
                cursorFollowing: following,
                freeRoaming: roaming,
                cursorAvoiding: avoiding
            ),
            persist: persist
        )
    }
}

private enum MovementEdit {
    case mode(PetMovementMode)
    case speed(Double)
    case cursorDistance(Double)
    case stopRadius(Double)
    case freeRoamingDwellMilliseconds(Int64)
    case randomizesFreeRoamingDwell(Bool)
    case freeRoamingDwellMinimumMilliseconds(Int64)
    case prefersFrontmostWindow(Bool)
    case cursorFollowingAnimation(MovementAnimationSettings)
    case freeRoamingAnimation(MovementAnimationSettings)
    case cursorAvoidingIdleBehavior(CursorAvoidingIdleBehavior)
    case cursorAvoidingDetectionDistance(Double)
    case cursorAvoidingSpeed(Double)
    case cursorAvoidingAnimation(MovementAnimationSettings)
}

private enum CustomAreaField {
    case x
    case y
    case width
    case height
}

private enum DwellTimingMode: Hashable {
    case fixed
    case random
}
