import SwiftUI

struct PetDisplaySettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDisplayName: String

    var body: some View {
        Form {
            PetDisplaySettingsSections(
                settingsSession: settingsSession,
                petDisplayName: petDisplayName
            )
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("monglepet.settings.displayRoot")
    }
}

struct PetDisplaySettingsSections: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDisplayName: String

    var body: some View {
        Group {
            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.movementPetName"
                    )

                Text("현재 선택한 내 펫의 크기와 화면 표시 방식을 설정합니다. 깨우기와 재우기는 내 펫 화면에서 바꿀 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("크기") {
                HStack {
                    Text("펫 크기")
                    Slider(
                        value: overlayScalePercentBinding,
                        in: AppSettingsLimits.minimumOverlayScalePercent
                            ... AppSettingsLimits.maximumOverlayScalePercent,
                        step: 5,
                        onEditingChanged: persistSliderWhenEditingEnds
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.overlayWidth"
                    )
                    HStack(spacing: 3) {
                        TextField(
                            "",
                            value: overlayScaleInputPercentBinding,
                            format: .number.precision(.fractionLength(0))
                        )
                        .accessibilityLabel("펫 크기 퍼센트")
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 62)

                        Text("%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 12, alignment: .leading)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: 6) {
                    Text("빠른 크기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ForEach([10, 25, 50, 100, 150, 200], id: \.self) {
                        percent in
                        Button("\(percent)%") {
                            setOverlayScalePercent(Double(percent))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            abs(overlayScalePercent - Double(percent)) < 0.01
                        )
                        .help(percent == 100 ? "기본 크기" : "\(percent)% 크기")
                        .accessibilityIdentifier(
                            "monglepet.settings.quickScale.\(percent)"
                        )
                    }
                }

                if overlayScalePercent < 25 {
                    Label(
                        "아주 작은 펫은 찾거나 드래그하기 어려울 수 있습니다. 설정에서 다시 크게 만들거나 상태 메뉴의 ‘현재 화면으로 가져오기’를 사용하세요.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(
                        "monglepet.settings.smallPetWarning"
                    )
                }

                Text("100%는 192pt이며 10%~200% 범위에서 펫마다 따로 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("화면 표현") {
                HStack {
                    Text("기본 투명도")
                    Slider(
                        value: overlayOpacityBinding,
                        in: AppSettingsLimits.minimumOverlayOpacity
                            ... AppSettingsLimits.maximumOverlayOpacity,
                        step: 0.05,
                        onEditingChanged: persistSliderWhenEditingEnds
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.overlayOpacity"
                    )
                    Text(opacityText(settingsSession.settings.overlay.opacity))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Toggle(
                    "픽셀 아트 선명하게",
                    isOn: pixelArtRenderingBinding
                )
                .accessibilityIdentifier(
                    "monglepet.settings.pixelArtRendering"
                )

                Text("픽셀 아트의 확대 경계를 또렷하게 표시합니다. 일반 일러스트에서는 계단 현상이 보일 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("마우스 반응") {
                Toggle("클릭 통과", isOn: clickThroughBinding)
                    .accessibilityIdentifier(
                        "monglepet.settings.clickThrough"
                    )

                Text(
                    settingsSession.settings.overlay.clickThrough
                        ? "펫을 직접 드래그할 수 없습니다. 클릭 통과를 끄면 다시 위치를 옮길 수 있습니다."
                        : "켜면 펫 아래의 앱을 바로 클릭할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle(
                    "마우스가 펫과 겹치면 더 투명하게",
                    isOn: pointerOverlapFadeBinding
                )
                .accessibilityIdentifier(
                    "monglepet.settings.pointerOverlapFade"
                )

                if settingsSession.settings.overlay.pointerOverlapFadeEnabled {
                    HStack {
                        Text("겹침 투명도")
                        Slider(
                            value: pointerOverlapOpacityBinding,
                            in: AppSettingsLimits
                                .minimumPointerOverlapOpacity
                                ... AppSettingsLimits
                                    .maximumPointerOverlapOpacity,
                            step: 0.05,
                            onEditingChanged: persistSliderWhenEditingEnds
                        )
                        .accessibilityIdentifier(
                            "monglepet.settings.pointerOverlapOpacity"
                        )
                        Text(
                            opacityText(
                                settingsSession.settings.overlay
                                    .pointerOverlapOpacity
                            )
                        )
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                    }

                    Text(pointerOverlapDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!settingsSession.isWritingEnabled)
    }

    private var overlayScalePercentBinding: Binding<Double> {
        Binding(
            get: {
                settingsSession.settings.overlay.width
                    / AppSettingsLimits.defaultOverlayWidth * 100
            },
            set: { percent in
                let clamped = min(
                    max(
                        percent,
                        AppSettingsLimits.minimumOverlayScalePercent
                    ),
                    AppSettingsLimits.maximumOverlayScalePercent
                )
                settingsSession.setOverlayWidth(
                    AppSettingsLimits.defaultOverlayWidth * clamped / 100,
                    persist: false
                )
            }
        )
    }

    private var overlayScalePercent: Double {
        settingsSession.settings.overlay.width
            / AppSettingsLimits.defaultOverlayWidth * 100
    }

    private func setOverlayScalePercent(_ percent: Double) {
        let clamped = min(
            max(percent, AppSettingsLimits.minimumOverlayScalePercent),
            AppSettingsLimits.maximumOverlayScalePercent
        )
        settingsSession.setOverlayWidth(
            AppSettingsLimits.defaultOverlayWidth * clamped / 100
        )
    }

    private var overlayScaleInputPercentBinding: Binding<Double> {
        Binding(
            get: { overlayScalePercentBinding.wrappedValue },
            set: { percent in
                let clamped = min(
                    max(
                        percent,
                        AppSettingsLimits.minimumOverlayScalePercent
                    ),
                    AppSettingsLimits.maximumOverlayScalePercent
                )
                settingsSession.setOverlayWidth(
                    AppSettingsLimits.defaultOverlayWidth * clamped / 100
                )
            }
        )
    }

    private var overlayOpacityBinding: Binding<Double> {
        Binding(
            get: { settingsSession.settings.overlay.opacity },
            set: {
                settingsSession.setOverlayOpacity($0, persist: false)
            }
        )
    }

    private var pixelArtRenderingBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.overlay.pixelArtRendering },
            set: { settingsSession.setPixelArtRendering($0) }
        )
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.overlay.clickThrough },
            set: { settingsSession.setClickThrough($0) }
        )
    }

    private var pointerOverlapFadeBinding: Binding<Bool> {
        Binding(
            get: {
                settingsSession.settings.overlay.pointerOverlapFadeEnabled
            },
            set: {
                settingsSession.setPointerOverlapFadeEnabled($0)
            }
        )
    }

    private var pointerOverlapOpacityBinding: Binding<Double> {
        Binding(
            get: {
                settingsSession.settings.overlay.pointerOverlapOpacity
            },
            set: {
                settingsSession.setPointerOverlapOpacity(
                    $0,
                    persist: false
                )
            }
        )
    }

    private var pointerOverlapDescription: String {
        guard settingsSession.settings.overlay.clickThrough else {
            return "클릭 통과를 켜면 마우스와 실제로 보이는 펫 영역이 겹칠 때만 적용됩니다."
        }
        let effectiveOpacity = min(
            settingsSession.settings.overlay.opacity,
            settingsSession.settings.overlay.pointerOverlapOpacity
        )
        return "투명한 여백은 제외하며 겹칠 때 실제 투명도는 \(opacityText(effectiveOpacity))입니다."
    }

    private func opacityText(_ opacity: Double) -> String {
        "\(Int((opacity * 100).rounded()))%"
    }

    private func persistSliderWhenEditingEnds(_ isEditing: Bool) {
        if !isEditing {
            settingsSession.persistCurrentSettings()
        }
    }
}
