import AppKit
import SwiftUI

struct SpriteSheetImportPresentation: Identifiable {
    let id = UUID()
    let document: SpriteSheetDocument
}

struct SpriteSheetImportView: View {
    @Environment(\.dismiss) private var dismiss

    let document: SpriteSheetDocument
    let onImport: ([UserPetSourceImage]) -> Void

    @State private var regions: [SelectableSpriteRegion]
    @State private var rows = 1
    @State private var columns: Int
    @State private var inset = 0
    @State private var removesBackground = false
    @State private var backgroundColor: SpriteSheetColor
    @State private var tolerance = 28.0
    @State private var previewImage: CGImage
    @State private var errorMessage: String?

    init(
        document: SpriteSheetDocument,
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        self.document = document
        self.onImport = onImport
        _regions = State(
            initialValue: document.suggestedRegions.map {
                SelectableSpriteRegion(rect: $0)
            }
        )
        _columns = State(initialValue: max(1, document.suggestedRegions.count))
        _backgroundColor = State(initialValue: document.suggestedBackgroundColor)
        _previewImage = State(initialValue: document.image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 18) {
                    preview
                        .frame(minWidth: 420, maxWidth: .infinity)

                    controls
                        .frame(width: 290)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 920, minHeight: 590, idealHeight: 700)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("스프라이트 시트 가져오기")
                .font(.title2.weight(.semibold))
            Text(
                "\(document.sourceURL.lastPathComponent) · "
                    + "\(document.pixelSize.width)×\(document.pixelSize.height) px"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("프레임 경계")
                    .font(.headline)
                Spacer()
                Text("\(selectedRegions.count)개 선택")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SpriteSheetRegionPreview(
                image: previewImage,
                pixelSize: document.pixelSize,
                regions: $regions
            )
            .accessibilityIdentifier("monglepet.spriteSheet.preview")

            Text("번호가 붙은 경계를 클릭하면 가져올 프레임을 선택하거나 제외할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("경계 설정") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("자동 제안으로 되돌리기") {
                        useSuggestedRegions()
                    }

                    Divider()

                    Text("일정한 격자로 다시 나누기")
                        .font(.subheadline.weight(.semibold))

                    Stepper("행 \(rows)", value: $rows, in: 1...32)
                    Stepper("열 \(columns)", value: $columns, in: 1...32)
                    Stepper("안쪽 여백 \(inset) px", value: $inset, in: 0...64)

                    Button("격자 적용") {
                        applyGrid()
                    }
                    .disabled(rows * columns > 1_000)
                }
                .padding(6)
            }

            GroupBox("배경") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("선택한 배경색 제거", isOn: $removesBackground)
                        .disabled(document.hasTransparentBackground)
                        .onChange(of: removesBackground) {
                            refreshPreview()
                        }

                    ColorPicker(
                        "배경색",
                        selection: backgroundColorBinding,
                        supportsOpacity: false
                    )
                    .disabled(!removesBackground || document.hasTransparentBackground)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("허용 범위")
                            Spacer()
                            Text("\(Int(tolerance.rounded()))")
                                .monospacedDigit()
                        }
                        Slider(
                            value: $tolerance,
                            in: 0...120,
                            step: 1,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    refreshPreview()
                                }
                            }
                        )
                    }
                    .disabled(!removesBackground || document.hasTransparentBackground)

                    Button("배경 미리보기 갱신") {
                        refreshPreview()
                    }
                    .disabled(!removesBackground || document.hasTransparentBackground)

                    Text(
                        document.hasTransparentBackground
                            ? "이미 투명한 입력은 원본 알파를 보존하며 추가 배경 제거를 적용하지 않습니다."
                            : "배경 제거는 원본을 바꾸지 않으며, 가져오는 프레임에만 적용됩니다."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            if document.hasTransparentBackground {
                Label(
                    "투명 배경을 감지해 원본 가장자리 픽셀을 보존합니다.",
                    systemImage: "checkmark.circle"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Text("정적 PNG·WebP만 지원하며 animated WebP와 APNG는 지원하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("취소", role: .cancel) {
                dismiss()
            }

            Button("프레임 저장 및 추가") {
                importSelectedFrames()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRegions.isEmpty)
            .accessibilityIdentifier("monglepet.spriteSheet.import")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedRegions: [PixelRect] {
        regions.compactMap { $0.isSelected ? $0.rect : nil }
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: Double(backgroundColor.red) / 255,
                    green: Double(backgroundColor.green) / 255,
                    blue: Double(backgroundColor.blue) / 255
                )
            },
            set: { newValue in
                guard let color = NSColor(newValue).usingColorSpace(.deviceRGB) else {
                    return
                }
                backgroundColor = SpriteSheetColor(
                    red: byte(color.redComponent),
                    green: byte(color.greenComponent),
                    blue: byte(color.blueComponent),
                    alpha: 255
                )
            }
        )
    }

    private func byte(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255).rounded()))
    }

    private func useSuggestedRegions() {
        regions = document.suggestedRegions.map {
            SelectableSpriteRegion(rect: $0)
        }
        rows = 1
        columns = max(1, regions.count)
        inset = 0
        errorMessage = nil
    }

    private func applyGrid() {
        do {
            let grid = try SpriteSheetFrameExtractor().uniformGridRegions(
                pixelSize: document.pixelSize,
                rows: rows,
                columns: columns,
                inset: inset
            )
            regions = grid.map { SelectableSpriteRegion(rect: $0) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPreview() {
        do {
            previewImage = try SpriteSheetFrameExtractor().processedImage(
                from: document,
                removingBackground: backgroundRemoval
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var backgroundRemoval: SpriteSheetBackgroundRemoval? {
        guard removesBackground, !document.hasTransparentBackground else {
            return nil
        }
        return SpriteSheetBackgroundRemoval(
            color: backgroundColor,
            tolerance: Int(tolerance.rounded())
        )
    }

    private func importSelectedFrames() {
        do {
            let images = try SpriteSheetFrameExtractor().extractFrames(
                from: document,
                regions: selectedRegions,
                removingBackground: backgroundRemoval
            )
            let sourceName = document.sourceURL.deletingPathExtension().lastPathComponent
            onImport(
                images.enumerated().map { index, image in
                    UserPetSourceImage(
                        displayName: "\(sourceName) \(index + 1)",
                        image: image
                    )
                }
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SelectableSpriteRegion: Identifiable {
    let id = UUID()
    let rect: PixelRect
    var isSelected = true
}

private struct SpriteSheetRegionPreview: View {
    let image: CGImage
    let pixelSize: PixelSize
    @Binding var regions: [SelectableSpriteRegion]

    var body: some View {
        GeometryReader { geometry in
            let imageFrame = aspectFitFrame(in: geometry.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)

                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    let frame = displayFrame(for: region.rect, in: imageFrame)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            region.isSelected
                                ? Color.accentColor.opacity(0.14)
                                : Color.black.opacity(0.24)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    region.isSelected ? Color.accentColor : Color.secondary,
                                    lineWidth: region.isSelected ? 2 : 1
                                )
                        }
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    region.isSelected ? Color.accentColor : Color.secondary,
                                    in: Capsule()
                                )
                                .padding(4)
                        }
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture {
                            regions[index].isSelected.toggle()
                        }
                        .accessibilityLabel("\(index + 1)번 프레임")
                        .accessibilityValue(region.isSelected ? "선택됨" : "제외됨")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(minHeight: 470)
    }

    private func aspectFitFrame(in size: CGSize) -> CGRect {
        let sourceRatio = CGFloat(pixelSize.width) / CGFloat(pixelSize.height)
        let availableRatio = size.width / max(1, size.height)
        if sourceRatio > availableRatio {
            let height = size.width / sourceRatio
            return CGRect(
                x: 0,
                y: (size.height - height) / 2,
                width: size.width,
                height: height
            )
        }
        let width = size.height * sourceRatio
        return CGRect(
            x: (size.width - width) / 2,
            y: 0,
            width: width,
            height: size.height
        )
    }

    private func displayFrame(for rect: PixelRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX
                + CGFloat(rect.x) / CGFloat(pixelSize.width) * imageFrame.width,
            y: imageFrame.minY
                + CGFloat(rect.y) / CGFloat(pixelSize.height) * imageFrame.height,
            width: CGFloat(rect.width) / CGFloat(pixelSize.width) * imageFrame.width,
            height: CGFloat(rect.height) / CGFloat(pixelSize.height) * imageFrame.height
        )
    }
}

struct SpriteSheetPromptCopyButton: View {
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.prompt, forType: .string)
            copied = true
        } label: {
            Label(
                copied ? "프롬프트 복사됨" : "AI 제작 프롬프트 복사",
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
        }
        .help("정적 스프라이트 시트 제작용 일반 프롬프트를 복사합니다.")
    }

    static let prompt = """
    하나의 일관된 반려 캐릭터로 데스크톱 펫 애니메이션용 정적 스프라이트 시트를 만들어 주세요.
    총 10프레임을 5열 × 2행의 동일한 셀에 왼쪽 위부터 재생 순서대로 배치해 주세요.
    모든 프레임에서 캐릭터의 디자인, 크기, 기준선, 시점, 조명과 여백을 동일하게 유지해 주세요.
    프레임 사이에는 분명한 빈 간격을 두고 캐릭터가 셀 경계를 넘지 않게 해 주세요.
    번호, 글자, 격자선, 그림자, 장식 테두리는 넣지 말아 주세요.
    배경은 캐릭터에 사용되지 않은 단일 고채도 색으로 채워 주세요.
    결과는 animated WebP가 아닌 한 장의 정적 PNG 또는 정적 WebP 이미지로 제공해 주세요.
    """
}
