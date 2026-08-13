import SwiftUI

struct PetDisplaySettingsSections: View {
    @ObservedObject var settingsSession: AppSettingsSession

    var body: some View {
        Group {
            Section("표시 상태") {
                Toggle("펫 깨우기", isOn: awakeBinding)
                    .accessibilityIdentifier("monglepet.settings.awake")

                Text("재워도 메뉴 막대나 활성 펫 화면에서 다시 깨울 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("화면 표시") {
                HStack {
                    Text("펫 크기")
                    Slider(
                        value: overlayWidthBinding,
                        in: AppSettingsLimits.minimumOverlayWidth
                            ... AppSettingsLimits.maximumOverlayWidth,
                        step: 8,
                        onEditingChanged: persistSliderWhenEditingEnds
                    )
                    .accessibilityIdentifier(
                        "monglepet.settings.overlayWidth"
                    )
                    Text("\(Int(settingsSession.settings.overlay.width)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
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

    private var awakeBinding: Binding<Bool> {
        Binding(
            get: {
                settingsSession.settings.lastUserPresentation == .awake
            },
            set: {
                settingsSession.setUserPresentation(
                    $0 ? .awake : .tuckedAway
                )
            }
        )
    }

    private var overlayWidthBinding: Binding<Double> {
        Binding(
            get: { settingsSession.settings.overlay.width },
            set: { settingsSession.setOverlayWidth($0, persist: false) }
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
