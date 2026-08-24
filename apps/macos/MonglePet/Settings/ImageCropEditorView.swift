import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PNGFrameCropPresentation: Identifiable {
    let id = UUID()
    let images: [UserPetSourceImage]
}

struct PNGFrameCropEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UserPetSourceImage]
    let onImport: ([UserPetSourceImage]) -> Void
    private let initialScrollsToResultPreview: Bool

    @State private var drafts: [PNGFrameCropDraft]
    @State private var selectedIDs: Set<UUID>
    @State private var focusedID: UUID?
    @State private var errorMessage: String?
    @State private var zoomScale = 1.0

    init(
        images: [UserPetSourceImage],
        initialScrollsToResultPreview: Bool = false,
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        self.images = images
        self.initialScrollsToResultPreview = initialScrollsToResultPreview
        self.onImport = onImport
        let drafts = images.map(PNGFrameCropDraft.init)
        _drafts = State(initialValue: drafts)
        _selectedIDs = State(initialValue: Set(drafts.first.map { [$0.id] } ?? []))
        _focusedID = State(initialValue: drafts.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 16) {
                        selectedPreview
                            .frame(minWidth: 440, maxWidth: .infinity)

                        sidebar
                            .frame(width: 280)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("monglepet.pngCrop.contentScroll")
                .task {
                    guard initialScrollsToResultPreview else {
                        return
                    }
                    await Task.yield()
                    proxy.scrollTo(Self.resultPreviewScrollID, anchor: .bottom)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 860, idealWidth: 1_000, minHeight: 680, idealHeight: 780)
        .onChange(of: selectedIDs) { oldValue, newValue in
            updateFocusedSelection(from: oldValue, to: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PNG 프레임 자르기")
                .font(.title2.weight(.semibold))
            Text("여러 PNG를 선택해 함께 미리보고, 프레임마다 사용할 원본 범위를 조정합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var selectedPreview: some View {
        if let selectedDraftBinding {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selectedDraftBinding.wrappedValue.source.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(
                        "\(selectedDraftBinding.wrappedValue.source.image.width)×"
                            + "\(selectedDraftBinding.wrappedValue.source.image.height) px"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                ImageEditorZoomControls(zoomScale: $zoomScale)

                SingleImageCropPreview(
                    image: selectedDraftBinding.wrappedValue.source.image,
                    cropRect: selectedDraftBinding.cropRect,
                    zoomScale: zoomScale
                )
                .frame(minHeight: selectedIDs.count > 1 ? 330 : 470)
                .accessibilityIdentifier("monglepet.pngCrop.preview")

                Text("파란 경계 안을 드래그해 이동하고 모서리·변의 핸들로 크기를 조절합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                focusedCropResultPreview(selectedDraftBinding.wrappedValue)

                if selectedIDs.count > 1 {
                    selectedCropsPreview
                }
            }
        } else {
            ContentUnavailableView("선택한 PNG가 없습니다.", systemImage: "photo")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("선택 범위") {
                if let selectedDraftBinding {
                    CropRectNumericControls(
                        rect: selectedDraftBinding.cropRect,
                        pixelSize: selectedDraftBinding.wrappedValue.pixelSize
                    )

                    Divider()

                    Button("투명 여백 자동 맞춤") {
                        trimTransparentMargins(selectedDraftBinding)
                    }

                    Button("원본 전체로 되돌리기") {
                        selectedDraftBinding.wrappedValue.resetCrop()
                    }

                    Divider()

                    Button {
                        toggleHorizontalFlip()
                    } label: {
                        Label(
                            selectedDraftBinding.wrappedValue.flipsHorizontally
                                ? "선택한 PNG 좌우 뒤집기 해제"
                                : "선택한 PNG 좌우 뒤집기",
                            systemImage: "arrow.left.and.right"
                        )
                    }
                    .accessibilityIdentifier("monglepet.pngCrop.flipHorizontal")

                    Button {
                        toggleVerticalFlip()
                    } label: {
                        Label(
                            selectedDraftBinding.wrappedValue.flipsVertically
                                ? "선택한 PNG 상하 뒤집기 해제"
                                : "선택한 PNG 상하 뒤집기",
                            systemImage: "arrow.up.and.down"
                        )
                    }
                    .accessibilityIdentifier("monglepet.pngCrop.flipVertical")

                    if selectedIDs.count > 1 {
                        Divider()

                        Button("선택한 PNG에 현재 크기 적용") {
                            applyFocusedCropSizeToSelection()
                        }

                        Button("선택한 PNG 투명 여백 자동 맞춤") {
                            trimSelectedTransparentMargins()
                        }

                        Button("선택한 PNG를 원본 전체로") {
                            resetSelectedCrops()
                        }
                    }
                }
            }

            GroupBox("PNG 목록") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("전체 선택") {
                            selectedIDs = Set(drafts.map(\.id))
                            focusedID = drafts.first?.id
                        }

                        Button("전체 해제") {
                            selectedIDs.removeAll()
                            focusedID = nil
                        }

                        Spacer()

                        Text("\(selectedIDs.count)개 선택")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    List(selection: $selectedIDs) {
                        ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                            HStack(spacing: 8) {
                                CroppedImagePreview(
                                    image: draft.source.image,
                                    cropRect: draft.cropRect,
                                    flipsHorizontally: draft.flipsHorizontally,
                                    flipsVertically: draft.flipsVertically
                                )
                                .frame(width: 36, height: 36)
                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(draft.source.displayName)
                                    .lineLimit(1)
                            }
                            .tag(draft.id)
                        }
                    }
                    .frame(minHeight: 230)
                    .accessibilityIdentifier("monglepet.pngCrop.frames")

                    Button {
                        addPNGFiles()
                    } label: {
                        Label("PNG 더 추가…", systemImage: "plus")
                    }
                    .accessibilityIdentifier("monglepet.pngCrop.addFiles")

                    Text("⌘ 키를 누른 채 클릭하면 여러 PNG를 선택할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            Text("목록의 모든 PNG를 추가하며, 목록 선택은 함께 미리보고 일괄 편집할 대상을 정합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("취소", role: .cancel) {
                dismiss()
            }
            Button("잘라서 프레임 추가") {
                importCroppedImages()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(drafts.isEmpty)
            .accessibilityIdentifier("monglepet.pngCrop.import")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedDraftBinding: Binding<PNGFrameCropDraft>? {
        guard let focusedID,
              let index = drafts.firstIndex(where: { $0.id == focusedID }) else {
            return nil
        }
        return $drafts[index]
    }

    private func trimTransparentMargins(_ draft: Binding<PNGFrameCropDraft>) {
        guard let bounds = draft.wrappedValue.resolveTransparentBounds() else {
            return
        }
        draft.wrappedValue.cropRect = bounds
        errorMessage = nil
    }

    private func updateFocusedSelection(
        from oldValue: Set<UUID>,
        to newValue: Set<UUID>
    ) {
        if let focusedID,
           newValue.contains(focusedID),
           !oldValue.contains(focusedID) {
            return
        }
        if let added = newValue.subtracting(oldValue).first {
            focusedID = added
        } else if let focusedID, !newValue.contains(focusedID) {
            self.focusedID = drafts.first(where: { newValue.contains($0.id) })?.id
        } else if focusedID == nil {
            focusedID = drafts.first(where: { newValue.contains($0.id) })?.id
        }
    }

    private func applyFocusedCropSizeToSelection() {
        guard let focused = selectedDraftBinding?.wrappedValue else {
            return
        }
        let geometry = ImageCropGeometry()
        for index in drafts.indices where selectedIDs.contains(drafts[index].id) {
            let current = drafts[index].cropRect
            let centerX = current.x + current.width / 2
            let centerY = current.y + current.height / 2
            drafts[index].cropRect = geometry.clamped(
                PixelRect(
                    x: centerX - focused.cropRect.width / 2,
                    y: centerY - focused.cropRect.height / 2,
                    width: focused.cropRect.width,
                    height: focused.cropRect.height
                ),
                to: drafts[index].pixelSize
            )
        }
    }

    private func trimSelectedTransparentMargins() {
        for index in drafts.indices where selectedIDs.contains(drafts[index].id) {
            if let bounds = drafts[index].resolveTransparentBounds() {
                drafts[index].cropRect = bounds
            }
        }
        errorMessage = nil
    }

    private func resetSelectedCrops() {
        for index in drafts.indices where selectedIDs.contains(drafts[index].id) {
            drafts[index].resetCrop()
        }
        errorMessage = nil
    }

    private func toggleHorizontalFlip() {
        guard let focused = selectedDraftBinding?.wrappedValue else {
            return
        }
        let newValue = !focused.flipsHorizontally
        for index in drafts.indices where selectedIDs.contains(drafts[index].id) {
            drafts[index].flipsHorizontally = newValue
        }
    }

    private func toggleVerticalFlip() {
        guard let focused = selectedDraftBinding?.wrappedValue else {
            return
        }
        let newValue = !focused.flipsVertically
        for index in drafts.indices where selectedIDs.contains(drafts[index].id) {
            drafts[index].flipsVertically = newValue
        }
    }

    private func addPNGFiles() {
        let panel = NSOpenPanel()
        panel.title = "PNG 프레임 추가"
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
            let newDrafts = try panel.urls.map { sourceURL in
                let image = try SimpleAnimationPetPackageAdapter()
                    .loadStaticPNGWithSecurityScope(at: sourceURL)
                return PNGFrameCropDraft(
                    source: UserPetSourceImage(
                        displayName: sourceURL.lastPathComponent,
                        image: image
                    )
                )
            }
            drafts.append(contentsOf: newDrafts)
            selectedIDs = Set(newDrafts.map(\.id))
            focusedID = newDrafts.first?.id
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var selectedCropsPreview: some View {
        GroupBox("선택한 PNG 결과") {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(
                            drafts.filter { selectedIDs.contains($0.id) }
                        ) { draft in
                            VStack(spacing: 5) {
                                CroppedImagePreview(
                                    image: draft.source.image,
                                    cropRect: draft.cropRect,
                                    flipsHorizontally: draft.flipsHorizontally,
                                    flipsVertically: draft.flipsVertically
                                )
                                .frame(width: 104, height: 104)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            draft.id == focusedID
                                                ? Color.accentColor
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                }

                                Text(draft.source.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 104)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedID = draft.id
                            }
                        }
                    }
                }
                .frame(height: 132)

                Text("각 파란 경계가 실제로 추가될 PNG 프레임 전체 범위입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func focusedCropResultPreview(_ draft: PNGFrameCropDraft) -> some View {
        GroupBox("잘라낸 결과 미리보기") {
            VStack(alignment: .leading, spacing: 8) {
                CroppedImagePreview(
                    image: draft.source.image,
                    cropRect: draft.cropRect,
                    flipsHorizontally: draft.flipsHorizontally,
                    flipsVertically: draft.flipsVertically
                )
                .frame(height: 180)
                .accessibilityIdentifier("monglepet.pngCrop.resultPreview")

                HStack {
                    Label(
                        "파란 경계가 저장될 프레임 범위입니다.",
                        systemImage: "rectangle.dashed"
                    )
                    Spacer()
                    Text("\(draft.cropRect.width)×\(draft.cropRect.height) px")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(6)
        }
        .id(Self.resultPreviewScrollID)
    }

    private static let resultPreviewScrollID = "png-crop-result-preview"

    private func importCroppedImages() {
        do {
            let cropped = try drafts.map { draft in
                guard let image = ImageCropProcessor().cropAndTransform(
                    draft.source.image,
                    to: draft.cropRect,
                    flipsHorizontally: draft.flipsHorizontally,
                    flipsVertically: draft.flipsVertically
                ) else {
                    throw PNGFrameCropError.cannotCrop(draft.source.displayName)
                }
                return UserPetSourceImage(
                    id: draft.source.id,
                    displayName: draft.source.displayName,
                    image: image
                )
            }
            onImport(cropped)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PNGFrameCropDraft: Identifiable {
    let source: UserPetSourceImage
    var cropRect: PixelRect
    var flipsHorizontally = false
    var flipsVertically = false
    private var cachedTransparentBounds: PixelRect?
    private var hasResolvedTransparentBounds = false

    init(source: UserPetSourceImage) {
        self.source = source
        cropRect = PixelRect(
            x: 0,
            y: 0,
            width: source.image.width,
            height: source.image.height
        )
    }

    var id: UUID { source.id }

    var pixelSize: PixelSize {
        PixelSize(width: source.image.width, height: source.image.height)
    }

    mutating func resetCrop() {
        cropRect = PixelRect(
            x: 0,
            y: 0,
            width: pixelSize.width,
            height: pixelSize.height
        )
    }

    mutating func resolveTransparentBounds() -> PixelRect? {
        if !hasResolvedTransparentBounds {
            cachedTransparentBounds = try? FrameCanvasComposer().transparentContent(
                in: source.image
            ).sourceBounds
            hasResolvedTransparentBounds = true
        }
        return cachedTransparentBounds
    }
}

private enum PNGFrameCropError: LocalizedError {
    case cannotCrop(String)

    var errorDescription: String? {
        switch self {
        case let .cannotCrop(name):
            "PNG 범위를 자르지 못했습니다: \(name)"
        }
    }
}

struct CropRectNumericControls: View {
    @Binding var rect: PixelRect
    let pixelSize: PixelSize

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("X")
                numericField(value: xBinding)
                Text("Y")
                numericField(value: yBinding)
            }
            GridRow {
                Text("너비")
                numericField(value: widthBinding)
                Text("높이")
                numericField(value: heightBinding)
            }
        }
        .monospacedDigit()
    }

    private func numericField(value: Binding<Int>) -> some View {
        TextField("픽셀", value: value, format: .number)
            .frame(width: 62)
            .multilineTextAlignment(.trailing)
    }

    private var xBinding: Binding<Int> {
        componentBinding(\.x)
    }

    private var yBinding: Binding<Int> {
        componentBinding(\.y)
    }

    private var widthBinding: Binding<Int> {
        componentBinding(\.width)
    }

    private var heightBinding: Binding<Int> {
        componentBinding(\.height)
    }

    private func componentBinding(_ keyPath: KeyPath<PixelRect, Int>) -> Binding<Int> {
        Binding(
            get: { rect[keyPath: keyPath] },
            set: { value in
                let candidate = PixelRect(
                    x: keyPath == \.x ? value : rect.x,
                    y: keyPath == \.y ? value : rect.y,
                    width: keyPath == \.width ? value : rect.width,
                    height: keyPath == \.height ? value : rect.height
                )
                rect = ImageCropGeometry().clamped(candidate, to: pixelSize)
            }
        )
    }
}

struct SingleImageCropPreview: View {
    let image: CGImage
    @Binding var cropRect: PixelRect
    let zoomScale: Double

    var body: some View {
        GeometryReader { geometry in
            let pixelSize = PixelSize(width: image.width, height: image.height)
            let contentSize = CGSize(
                width: geometry.size.width * zoomScale,
                height: geometry.size.height * zoomScale
            )
            let imageFrame = ImageCropDisplayGeometry.aspectFitFrame(
                pixelSize: pixelSize,
                in: contentSize
            )
            Group {
                if ImageEditorViewportPolicy.usesInternalPan(at: zoomScale) {
                    ScrollView([.horizontal, .vertical]) {
                        cropEditorCanvas(
                            pixelSize: pixelSize,
                            contentSize: contentSize,
                            imageFrame: imageFrame
                        )
                    }
                } else {
                    cropEditorCanvas(
                        pixelSize: pixelSize,
                        contentSize: contentSize,
                        imageFrame: imageFrame
                    )
                }
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func cropEditorCanvas(
        pixelSize: PixelSize,
        contentSize: CGSize,
        imageFrame: CGRect
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.quaternary)

            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)

            CropRectangleEditorOverlay(
                cropRect: $cropRect,
                pixelSize: pixelSize,
                imageFrame: imageFrame
            )
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .coordinateSpace(name: ImageCropDisplayGeometry.coordinateSpaceName)
    }
}

struct CroppedImagePreview: View {
    let image: CGImage
    let cropRect: PixelRect
    let flipsHorizontally: Bool
    let flipsVertically: Bool

    init(
        image: CGImage,
        cropRect: PixelRect,
        flipsHorizontally: Bool = false,
        flipsVertically: Bool = false
    ) {
        self.image = image
        self.cropRect = cropRect
        self.flipsHorizontally = flipsHorizontally
        self.flipsVertically = flipsVertically
    }

    var body: some View {
        GeometryReader { geometry in
            if let previewImage = ImageCropProcessor().cropAndTransform(
                image,
                to: cropRect,
                flipsHorizontally: flipsHorizontally,
                flipsVertically: flipsVertically
            ) {
                let previewFrame = ImageCropResultPreviewGeometry.fittedFrame(
                    pixelSize: PixelSize(
                        width: previewImage.width,
                        height: previewImage.height
                    ),
                    in: geometry.size,
                    inset: 10
                )
                ZStack(alignment: .topLeading) {
                    ImagePreviewTransparencyGrid()

                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: previewFrame.width, height: previewFrame.height)
                        .position(x: previewFrame.midX, y: previewFrame.midY)

                    Rectangle()
                        .fill(.clear)
                        .overlay {
                            Rectangle()
                                .stroke(Color.accentColor, lineWidth: 2)
                        }
                        .frame(width: previewFrame.width, height: previewFrame.height)
                        .position(x: previewFrame.midX, y: previewFrame.midY)
                }
            } else {
                ZStack {
                    ImagePreviewTransparencyGrid()
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(
            "프레임 경계를 표시한 자른 이미지 미리보기, "
                + "\(cropRect.width)×\(cropRect.height) 픽셀"
        )
    }
}

struct ImageEditorZoomControls: View {
    @Binding var zoomScale: Double

    var body: some View {
        HStack(spacing: 8) {
            Label("확대", systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            zoomStepButton(
                systemImage: "minus",
                accessibilityLabel: "축소",
                accessibilityIdentifier: "monglepet.imageEditor.zoomOut",
                isDisabled: zoomScale <= 1
            ) {
                zoomScale = max(1, zoomScale - 0.5)
            }

            Slider(value: $zoomScale, in: 1...8, step: 0.5)
                .frame(maxWidth: 180)

            zoomStepButton(
                systemImage: "plus",
                accessibilityLabel: "확대",
                accessibilityIdentifier: "monglepet.imageEditor.zoomIn",
                isDisabled: zoomScale >= 8
            ) {
                zoomScale = min(8, zoomScale + 0.5)
            }

            Text("\(zoomScale, specifier: "%.1f")×")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)

            Button("맞춤") {
                zoomScale = 1
            }
            .disabled(zoomScale == 1)
        }
        .controlSize(.small)
    }

    private func zoomStepButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 5))
        .frame(width: 30, height: 24)
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct ImageCropResultPreviewGeometry {
    static func fittedFrame(
        pixelSize: PixelSize,
        in size: CGSize,
        inset: CGFloat
    ) -> CGRect {
        let inset = min(
            max(0, inset),
            max(0, min(size.width, size.height) * 0.08)
        )
        let availableSize = CGSize(
            width: max(1, size.width - inset * 2),
            height: max(1, size.height - inset * 2)
        )
        let fitted = ImageCropDisplayGeometry.aspectFitFrame(
            pixelSize: pixelSize,
            in: availableSize
        )
        return fitted.offsetBy(dx: inset, dy: inset)
    }
}

struct ImageEditorViewportPolicy {
    static func usesInternalPan(at zoomScale: Double) -> Bool {
        zoomScale > 1
    }
}

private struct ImagePreviewTransparencyGrid: View {
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

struct CropRectangleEditorOverlay: View {
    @Binding var cropRect: PixelRect
    let pixelSize: PixelSize
    let imageFrame: CGRect

    @State private var moveStartRect: PixelRect?

    var body: some View {
        let displayRect = ImageCropDisplayGeometry.displayRect(
            for: cropRect,
            pixelSize: pixelSize,
            imageFrame: imageFrame
        )
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

            ForEach(ImageCropHandle.allCases, id: \.self) { handle in
                CropResizeHandle(
                    cropRect: $cropRect,
                    pixelSize: pixelSize,
                    imageFrame: imageFrame,
                    handle: handle,
                    position: ImageCropDisplayGeometry.handlePosition(
                        handle,
                        in: displayRect
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named(ImageCropDisplayGeometry.coordinateSpaceName)
        )
            .onChanged { value in
                let start = moveStartRect ?? cropRect
                moveStartRect = start
                let delta = ImageCropDisplayGeometry.pixelDelta(
                    value.translation,
                    pixelSize: pixelSize,
                    imageFrame: imageFrame
                )
                let updated = ImageCropGeometry().moving(
                    start,
                    byX: delta.x,
                    y: delta.y,
                    in: pixelSize
                )
                if cropRect != updated {
                    cropRect = updated
                }
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }
}

private struct CropResizeHandle: View {
    @Binding var cropRect: PixelRect
    let pixelSize: PixelSize
    let imageFrame: CGRect
    let handle: ImageCropHandle
    let position: CGPoint

    @State private var resizeStartRect: PixelRect?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .overlay {
                    Circle().stroke(.white, lineWidth: 1)
                }
                .frame(width: 12, height: 12)
        }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .position(position)
            .gesture(resizeGesture)
            .accessibilityLabel("자르기 범위 크기 조절")
    }

    private var resizeGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(ImageCropDisplayGeometry.coordinateSpaceName)
        )
            .onChanged { value in
                let start = resizeStartRect ?? cropRect
                resizeStartRect = start
                let delta = ImageCropDisplayGeometry.pixelDelta(
                    value.translation,
                    pixelSize: pixelSize,
                    imageFrame: imageFrame
                )
                let updated = ImageCropGeometry().resizing(
                    start,
                    handle: handle,
                    byX: delta.x,
                    y: delta.y,
                    in: pixelSize
                )
                if cropRect != updated {
                    cropRect = updated
                }
            }
            .onEnded { _ in
                resizeStartRect = nil
            }
    }
}

enum ImageCropDisplayGeometry {
    static let coordinateSpaceName = "monglepet.imageCropEditor"

    static func aspectFitFrame(pixelSize: PixelSize, in size: CGSize) -> CGRect {
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

    static func displayRect(
        for rect: PixelRect,
        pixelSize: PixelSize,
        imageFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: imageFrame.minX
                + CGFloat(rect.x) / CGFloat(pixelSize.width) * imageFrame.width,
            y: imageFrame.minY
                + CGFloat(rect.y) / CGFloat(pixelSize.height) * imageFrame.height,
            width: CGFloat(rect.width) / CGFloat(pixelSize.width) * imageFrame.width,
            height: CGFloat(rect.height) / CGFloat(pixelSize.height) * imageFrame.height
        )
    }

    static func pixelDelta(
        _ translation: CGSize,
        pixelSize: PixelSize,
        imageFrame: CGRect
    ) -> (x: Int, y: Int) {
        (
            Int((translation.width / max(1, imageFrame.width)
                * CGFloat(pixelSize.width)).rounded()),
            Int((translation.height / max(1, imageFrame.height)
                * CGFloat(pixelSize.height)).rounded())
        )
    }

    static func sourceImageFrame(
        imageSize: PixelSize,
        cropRect: PixelRect,
        previewSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              cropRect.width > 0,
              cropRect.height > 0,
              previewSize.width > 0,
              previewSize.height > 0 else {
            return .zero
        }
        let scale = min(
            previewSize.width / CGFloat(cropRect.width),
            previewSize.height / CGFloat(cropRect.height)
        )
        let fittedCropWidth = CGFloat(cropRect.width) * scale
        let fittedCropHeight = CGFloat(cropRect.height) * scale
        let cropOriginX = (previewSize.width - fittedCropWidth) / 2
        let cropOriginY = (previewSize.height - fittedCropHeight) / 2
        return CGRect(
            x: cropOriginX - CGFloat(cropRect.x) * scale,
            y: cropOriginY - CGFloat(cropRect.y) * scale,
            width: CGFloat(imageSize.width) * scale,
            height: CGFloat(imageSize.height) * scale
        )
    }

    static func handlePosition(
        _ handle: ImageCropHandle,
        in rect: CGRect
    ) -> CGPoint {
        switch handle {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
