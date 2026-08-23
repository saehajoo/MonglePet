import SwiftUI

struct PNGFrameCropPresentation: Identifiable {
    let id = UUID()
    let images: [UserPetSourceImage]
}

struct PNGFrameCropEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UserPetSourceImage]
    let onImport: ([UserPetSourceImage]) -> Void

    @State private var drafts: [PNGFrameCropDraft]
    @State private var selectedIDs: Set<UUID>
    @State private var focusedID: UUID?
    @State private var errorMessage: String?

    init(
        images: [UserPetSourceImage],
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        self.images = images
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

            HStack(alignment: .top, spacing: 16) {
                selectedPreview
                    .frame(minWidth: 440, maxWidth: .infinity)

                sidebar
                    .frame(width: 280)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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

                SingleImageCropPreview(
                    image: selectedDraftBinding.wrappedValue.source.image,
                    cropRect: selectedDraftBinding.cropRect
                )
                .frame(minHeight: selectedIDs.count > 1 ? 330 : 470)
                .accessibilityIdentifier("monglepet.pngCrop.preview")

                Text("파란 경계 안을 드래그해 이동하고 모서리·변의 핸들로 크기를 조절합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                                    cropRect: draft.cropRect
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

    private var selectedCropsPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("선택한 PNG 미리보기")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(
                        drafts.filter { selectedIDs.contains($0.id) }
                    ) { draft in
                        VStack(spacing: 4) {
                            CroppedImagePreview(
                                image: draft.source.image,
                                cropRect: draft.cropRect
                            )
                            .frame(width: 92, height: 92)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        draft.id == focusedID
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.35),
                                        lineWidth: draft.id == focusedID ? 2 : 1
                                    )
                            }

                            Text(draft.source.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 92)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            focusedID = draft.id
                        }
                    }
                }
            }
            .frame(height: 118)
        }
    }

    private func importCroppedImages() {
        do {
            let cropped = try drafts.map { draft in
                guard let image = ImageCropProcessor().crop(
                    draft.source.image,
                    to: draft.cropRect
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

    var body: some View {
        GeometryReader { geometry in
            let pixelSize = PixelSize(width: image.width, height: image.height)
            let imageFrame = ImageCropDisplayGeometry.aspectFitFrame(
                pixelSize: pixelSize,
                in: geometry.size
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .coordinateSpace(name: ImageCropDisplayGeometry.coordinateSpaceName)
        }
    }
}

struct CroppedImagePreview: View {
    let image: CGImage
    let cropRect: PixelRect

    var body: some View {
        Canvas { context, size in
            let targetFrame = ImageCropDisplayGeometry.sourceImageFrame(
                imageSize: PixelSize(width: image.width, height: image.height),
                cropRect: cropRect,
                previewSize: size
            )
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.draw(Image(decorative: image, scale: 1), in: targetFrame)
        }
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(
            "자른 이미지 미리보기, \(cropRect.width)×\(cropRect.height) 픽셀"
        )
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
