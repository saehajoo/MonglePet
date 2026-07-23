import AppKit
import Foundation
import SwiftUI

struct MovementSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDefinition: PetDefinition
    let petDisplayName: String
    @State private var displayOptions: [PetMovementDisplayOption] = []

    var body: some View {
        Form {
            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.movementPetName"
                    )
            }

            Section("이동 방식") {
                Picker("이동 방식", selection: movementModeBinding) {
                    Text("위치 고정").tag(PetMovementMode.fixed)
                    Text("마우스 따라가기").tag(PetMovementMode.cursorFollowing)
                    Text("자유 이동").tag(PetMovementMode.freeRoaming)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("monglepet.settings.movementMode")

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if movement.mode != .fixed {
                Section("이동 감각") {
                    movementSlider(
                        title: "이동 속도",
                        value: movementSpeedBinding,
                        range: AppSettingsLimits.minimumMovementSpeed
                            ... AppSettingsLimits.maximumMovementSpeed,
                        step: 10,
                        valueText: "\(Int(movement.speed.rounded())) pt/s",
                        accessibilityIdentifier: "monglepet.settings.movementSpeed"
                    )
                    movementSlider(
                        title: "정지 반경",
                        value: movementStopRadiusBinding,
                        range: AppSettingsLimits.minimumMovementStopRadius
                            ... AppSettingsLimits.maximumMovementStopRadius,
                        step: 4,
                        valueText: "\(Int(movement.stopRadius.rounded())) pt",
                        accessibilityIdentifier: "monglepet.settings.movementStopRadius"
                    )
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

                    motionPicker(
                        title: "이동 중 애니메이션",
                        selection: cursorFollowingMotionBinding,
                        noneLabel: "기존 행동 유지",
                        accessibilityIdentifier:
                            "monglepet.settings.cursorFollowingMotion"
                    )

                    Text("마우스 포인터와 지정한 거리를 유지하며 화면 안에서 따라갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .freeRoaming:
                Section("자유 이동") {
                    movementSlider(
                        title: "머무는 시간",
                        value: freeRoamingDwellSecondsBinding,
                        range: freeRoamingDwellSecondsRange,
                        step: 0.5,
                        valueText: dwellTimeText,
                        accessibilityIdentifier: "monglepet.settings.freeRoamingDwell"
                    )

                    Toggle(
                        "현재 사용 중인 앱의 창 근처를 우선",
                        isOn: prefersFrontmostWindowBinding
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.prefersFrontmostWindow"
                    )

                    motionPicker(
                        title: "이동 중 애니메이션",
                        selection: freeRoamingMotionBinding,
                        noneLabel: "기존 행동 유지",
                        accessibilityIdentifier:
                            "monglepet.settings.freeRoamingMotion"
                    )

                    Text("창 정보를 얻을 수 없거나 전체 화면이면 현재 화면 안에서 안전한 위치를 선택합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("상호작용") {
                motionPicker(
                    title: "쓰다듬기 애니메이션",
                    selection: pettingMotionBinding,
                    noneLabel: "반응 없음",
                    accessibilityIdentifier: "monglepet.settings.pettingMotion"
                )

                Text("펫을 클릭하면 선택한 애니메이션을 한 번 재생한 뒤 기존 행동으로 돌아갑니다. 드래그는 쓰다듬기로 처리하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsSession.settings.overlay.clickThrough {
                    Text("클릭 통과가 켜져 있습니다. 쓰다듬기를 사용하려면 일반 탭에서 클릭 통과를 꺼 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("이동 방식은 현재 펫에 저장되고 이동 범위는 이 Mac의 모든 펫에 공통으로 적용됩니다. 마우스 위치와 앱 창 위치는 저장하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var movement: PetMovementSettings {
        settingsSession.settings.movementSettings
    }

    private var movementBoundary: MovementBoundarySettings {
        settingsSession.settings.overlay.movementBoundary
    }

    @ViewBuilder
    private var movementBoundarySection: some View {
        Section("이동 범위") {
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
        }
    }

    private var movementModeBinding: Binding<PetMovementMode> {
        Binding(
            get: { movement.mode },
            set: { apply(.mode($0)) }
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
                    ),
                    persist: false
                )
            }
        )
    }

    private var prefersFrontmostWindowBinding: Binding<Bool> {
        Binding(
            get: { movement.prefersFrontmostWindow },
            set: { apply(.prefersFrontmostWindow($0)) }
        )
    }

    private var cursorFollowingMotionBinding: Binding<String> {
        Binding(
            get: { movement.cursorFollowingMotionID ?? "" },
            set: {
                apply(
                    .cursorFollowingMotionID($0.isEmpty ? nil : $0)
                )
            }
        )
    }

    private var freeRoamingMotionBinding: Binding<String> {
        Binding(
            get: { movement.freeRoamingMotionID ?? "" },
            set: {
                apply(
                    .freeRoamingMotionID($0.isEmpty ? nil : $0)
                )
            }
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

    private var dwellTimeText: String {
        let seconds = Double(movement.freeRoamingDwellMilliseconds) / 1_000
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

    private func motionPicker(
        title: String,
        selection: Binding<String>,
        noneLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(noneLabel).tag("")
            ForEach(motionIDs(for: selection.wrappedValue), id: \.self) {
                motionID in
                Text(motionLabel(for: motionID)).tag(motionID)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func motionIDs(for selectedMotionID: String) -> [String] {
        var motionIDs = petDefinition.motions.map(\.id)
        if !selectedMotionID.isEmpty,
           !motionIDs.contains(selectedMotionID) {
            motionIDs.append(selectedMotionID)
        }
        return motionIDs
    }

    private func motionLabel(for motionID: String) -> String {
        petDefinition.motion(id: motionID) == nil
            ? "\(motionID) (찾을 수 없음)"
            : motionID
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
        var speed = current.speed
        var cursorDistance = current.cursorDistance
        var stopRadius = current.stopRadius
        var freeRoamingDwellMilliseconds =
            current.freeRoamingDwellMilliseconds
        var prefersFrontmostWindow = current.prefersFrontmostWindow
        var cursorFollowingMotionID = current.cursorFollowingMotionID
        var freeRoamingMotionID = current.freeRoamingMotionID

        switch edit {
        case let .mode(value):
            mode = value
        case let .speed(value):
            speed = value
        case let .cursorDistance(value):
            cursorDistance = value
        case let .stopRadius(value):
            stopRadius = value
        case let .freeRoamingDwellMilliseconds(value):
            freeRoamingDwellMilliseconds = value
        case let .prefersFrontmostWindow(value):
            prefersFrontmostWindow = value
        case let .cursorFollowingMotionID(value):
            cursorFollowingMotionID = value
        case let .freeRoamingMotionID(value):
            freeRoamingMotionID = value
        }

        settingsSession.setMovementSettings(
            PetMovementSettings(
                mode: mode,
                speed: speed,
                cursorDistance: cursorDistance,
                stopRadius: stopRadius,
                freeRoamingDwellMilliseconds:
                    freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: prefersFrontmostWindow,
                cursorFollowingMotionID: cursorFollowingMotionID,
                freeRoamingMotionID: freeRoamingMotionID
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
    case prefersFrontmostWindow(Bool)
    case cursorFollowingMotionID(String?)
    case freeRoamingMotionID(String?)
}

private enum CustomAreaField {
    case x
    case y
    case width
    case height
}
