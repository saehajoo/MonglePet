import AppKit
import SwiftUI

struct MonglePetQuickGuideView: View {
    let onOpenMyPets: () -> Void
    let onOpenPetContent: () -> Void
    let onOpenBehavior: () -> Void
    let onOpenStationaryBehavior: () -> Void
    let onOpenDisplay: () -> Void
    let onOpenMovement: () -> Void
    let onOpenInteraction: () -> Void
    let onOpenSpeech: () -> Void
    let onOpenRules: () -> Void

    @State private var showsWebGuideError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                quickStart
                terminology
                webGuide
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(28)
        }
        .navigationTitle("이용 가이드")
        .accessibilityIdentifier("monglepet.guide.root")
        .alert(
            "웹 가이드를 열 수 없습니다",
            isPresented: $showsWebGuideError
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("인터넷 연결을 확인한 뒤 다시 시도해 주세요.")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MonglePet 시작하기", systemImage: "pawprint.fill")
                .font(.title2.weight(.semibold))

            Text("펫을 추가한 뒤 애니메이션과 행동을 준비하고, 화면 표시·이동·규칙을 원하는 방식으로 설정해 보세요.")
                .font(.body)

            Label(
                "각 펫의 행동, 이동, 말풍선과 화면 설정은 서로 독립적으로 저장됩니다.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("빠르게 시작하기")
                .font(.headline)

            GuideStepCard(
                number: 1,
                title: "펫 준비하기",
                description: "내 펫에서 새 펫을 만들거나 파일·웹 주소로 가져옵니다. 사용할 펫을 고르고 깨우기와 재우기도 이곳에서 관리합니다."
            ) {
                GuideDestinationButton(
                    "내 펫 열기",
                    identifier: "monglepet.guide.open.myPets",
                    action: onOpenMyPets
                )
            }

            GuideStepCard(
                number: 2,
                title: "애니메이션과 행동 만들기",
                description: "먼저 이미지 프레임으로 애니메이션을 준비한 다음, 하나 이상의 애니메이션 단계를 묶어 실제 행동을 만듭니다."
            ) {
                guideActionLayout {
                    GuideDestinationButton(
                        "애니메이션 열기",
                        identifier: "monglepet.guide.open.petContent",
                        action: onOpenPetContent
                    )
                    GuideDestinationButton(
                        "행동 편집 열기",
                        identifier: "monglepet.guide.open.behavior",
                        action: onOpenBehavior
                    )
                }
            }

            GuideStepCard(
                number: 3,
                title: "평상시 행동과 규칙 정하기",
                description: "다른 조건이 없을 때 보여 줄 평상시 행동을 고릅니다. 입력 없음이나 특정 앱 사용 중에 다른 행동을 보여 주려면 규칙을 추가합니다."
            ) {
                guideActionLayout {
                    GuideDestinationButton(
                        "평상시 행동 열기",
                        identifier: "monglepet.guide.open.stationaryBehavior",
                        action: onOpenStationaryBehavior
                    )
                    GuideDestinationButton(
                        "규칙 설정 열기",
                        identifier: "monglepet.guide.open.rules",
                        action: onOpenRules
                    )
                }
            }

            GuideStepCard(
                number: 4,
                title: "보이는 모습과 움직임 꾸미기",
                description: "크기와 투명도, 이동 방식과 범위, 쓰다듬기 반응 및 말풍선을 선택한 펫에 맞게 조정합니다."
            ) {
                guideActionLayout {
                    GuideDestinationButton(
                        "화면 표시",
                        identifier: "monglepet.guide.open.display",
                        action: onOpenDisplay
                    )
                    GuideDestinationButton(
                        "이동",
                        identifier: "monglepet.guide.open.movement",
                        action: onOpenMovement
                    )
                    GuideDestinationButton(
                        "상호작용",
                        identifier: "monglepet.guide.open.interaction",
                        action: onOpenInteraction
                    )
                    GuideDestinationButton(
                        "말풍선",
                        identifier: "monglepet.guide.open.speech",
                        action: onOpenSpeech
                    )
                }
            }

            GuideStepCard(
                number: 5,
                title: "완성한 펫 보관하고 공유하기",
                description: "내 펫에서 패키지 파일로 저장하면 펫 이미지와 제작자가 구성한 휴대 가능한 설정을 함께 공유할 수 있습니다."
            ) {
                GuideDestinationButton(
                    "내 펫에서 내보내기",
                    identifier: "monglepet.guide.open.export",
                    action: onOpenMyPets
                )
            }
        }
    }

    private var terminology: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("헷갈리기 쉬운 말")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                GuideTermCard(
                    title: "애니메이션",
                    description: "이미지 프레임이 순서대로 재생되는 화면 표현입니다."
                )
                GuideTermCard(
                    title: "행동",
                    description: "하나 이상의 애니메이션 단계를 순서와 반복 횟수로 묶은 동작입니다."
                )
                GuideTermCard(
                    title: "평상시 행동",
                    description: "이동하지 않고 적용할 조건 규칙이 없을 때 계속 보여 주는 기본 행동입니다."
                )
                GuideTermCard(
                    title: "규칙",
                    description: "입력 없음이나 사용 중인 앱 같은 조건이 맞을 때 평상시 행동보다 먼저 적용됩니다."
                )
                GuideTermCard(
                    title: "제작자 설정",
                    description: "가져온 펫에 포함된 행동·이동·말풍선 설정이며 추가한 뒤 자유롭게 바꿀 수 있습니다."
                )
            }
        }
    }

    private var webGuide: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("더 자세한 제작 방법이 필요하신가요?")
                        .font(.headline)
                    Text("이미지 준비, 펫 제작과 공유에 관한 자세한 설명은 웹 가이드에서 확인할 수 있습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    if !NSWorkspace.shared.open(webGuideURL) {
                        showsWebGuideError = true
                    }
                } label: {
                    Label("웹 가이드 보기", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("monglepet.guide.openWeb")
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func guideActionLayout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8, content: content)
            VStack(alignment: .leading, spacing: 8, content: content)
        }
    }

    private var webGuideURL: URL {
        URL(string: "https://mapleroom.kr/monglepet/guide")!
    }
}

private struct GuideStepCard<Actions: View>: View {
    let number: Int
    let title: String
    let description: String
    let actions: Actions

    init(
        number: Int,
        title: String,
        description: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.number = number
        self.title = title
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(4)
        }
    }
}

private struct GuideDestinationButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    init(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }
}

private struct GuideTermCard: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}
