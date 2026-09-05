import AppKit
import SwiftUI

struct SpriteSheetImportPresentation: Identifiable {
    let id = UUID()
    let document: SpriteSheetDocument
}

private enum SpriteSheetFrameOrderMode: String, CaseIterable, Identifiable {
    case reading
    case clicked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reading:
            "읽기 순서"
        case .clicked:
            "클릭 순서"
        }
    }
}

private enum SpriteSheetInteractionMode: String, CaseIterable, Identifiable {
    case selection
    case bounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection:
            "프레임 선택"
        case .bounds:
            "범위 편집"
        }
    }
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
    @State private var frameOrderMode = SpriteSheetFrameOrderMode.reading
    @State private var clickedRegionOrder: [Int] = []
    @State private var interactionMode = SpriteSheetInteractionMode.selection
    @State private var editingRegionID: UUID?
    @State private var previewRegionID: UUID?
    @State private var zoomScale = 1.0
    @State private var isProcessing = false
    @State private var previewRevision = 0
    @State private var hasEdits = false
    @State private var showsDiscardConfirmation = false

    init(
        document: SpriteSheetDocument,
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        self.document = document
        self.onImport = onImport
        let suggestedRegions = document.suggestedRegions.map {
            SelectableSpriteRegion(rect: $0)
        }
        let dimensions = SpriteSheetFrameExtractor().inferredGridDimensions(
            for: document.suggestedRegions
        )
        _regions = State(initialValue: suggestedRegions)
        _editingRegionID = State(initialValue: suggestedRegions.first?.id)
        _previewRegionID = State(initialValue: suggestedRegions.first?.id)
        _rows = State(initialValue: dimensions.rows)
        _columns = State(initialValue: dimensions.columns)
        _backgroundColor = State(initialValue: document.suggestedBackgroundColor)
        _previewImage = State(initialValue: document.image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            GeometryReader { geometry in
                let contentWidth = max(
                    420,
                    geometry.size.width
                        - SpriteSheetEditorLayout.sidebarWidth
                        - SpriteSheetEditorLayout.columnSpacing
                        - SpriteSheetEditorLayout.horizontalPadding
                )
                let canvasHeight = SpriteSheetEditorLayout.canvasHeight(
                    pixelSize: document.pixelSize,
                    availableWidth: contentWidth,
                    availableHeight: max(
                        SpriteSheetEditorLayout.minimumCanvasHeight,
                        geometry.size.height
                            - SpriteSheetEditorLayout.verticalPadding
                            - SpriteSheetEditorLayout.previewChromeHeight
                    )
                )

                HStack(alignment: .top, spacing: 18) {
                    preview(canvasHeight: canvasHeight)
                        .frame(minWidth: 420, maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 12) {
                        selectedRegionPreview

                        Divider()

                        ScrollView(.vertical) {
                            settingsControls
                                .padding(.trailing, 4)
                        }
                        .scrollIndicators(.visible)
                        .accessibilityIdentifier(
                            "monglepet.spriteSheet.settingsScroll"
                        )
                    }
                    .frame(width: SpriteSheetEditorLayout.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .accessibilityIdentifier("monglepet.spriteSheet.error")
            }

            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 920, minHeight: 590, idealHeight: 700)
        .onChange(of: regions) {
            hasEdits = true
        }
        .onChange(of: editingRegionID) { _, newValue in
            guard let newValue,
                  let region = regions.first(where: { $0.id == newValue }),
                  region.isSelected else {
                return
            }
            previewRegionID = newValue
        }
        .interactiveDismissDisabled(hasEdits)
        .confirmationDialog(
            "편집 중인 변경사항을 버릴까요?",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("변경사항 버리기", role: .destructive) {
                dismiss()
            }
            Button("계속 편집", role: .cancel) {}
        } message: {
            Text("프레임 선택과 경계 변경은 아직 애니메이션에 추가되지 않았습니다.")
        }
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

    private func preview(canvasHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("프레임 경계")
                    .font(.headline)
                Spacer()

                Text("\(selectedRegions.count)개 선택")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier(
                        "monglepet.spriteSheet.selectedCount"
                    )
            }

            HStack {
                Picker("경계 작업", selection: $interactionMode) {
                    ForEach(SpriteSheetInteractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .labelsHidden()
                .accessibilityIdentifier("monglepet.spriteSheet.interactionMode")

                ControlGroup {
                    Button("전체 선택") {
                        setAllRegionsSelected(true)
                    }
                    .disabled(regions.allSatisfy(\.isSelected))
                    .accessibilityIdentifier(
                        "monglepet.spriteSheet.selectAll"
                    )

                    Button("전체 해제") {
                        setAllRegionsSelected(false)
                    }
                    .disabled(regions.allSatisfy { !$0.isSelected })
                    .accessibilityIdentifier(
                        "monglepet.spriteSheet.deselectAll"
                    )
                }
                .controlSize(.small)
            }

            ImageEditorZoomControls(zoomScale: $zoomScale)

            SpriteSheetRegionPreview(
                image: previewImage,
                pixelSize: document.pixelSize,
                regions: $regions,
                editingRegionID: $editingRegionID,
                zoomScale: zoomScale,
                interactionMode: interactionMode,
                orderNumber: displayedOrderNumber,
                onToggleRegion: toggleRegion
            )
            .frame(height: canvasHeight)
            .accessibilityIdentifier("monglepet.spriteSheet.preview")

            Text(frameSelectionHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedRegionPreview: some View {
        GroupBox("선택 영역 미리보기") {
            VStack(alignment: .leading, spacing: 8) {
                if let previewRegionBinding,
                   let previewRegionPosition {
                    HStack {
                        Button {
                            movePreviewRegion(by: -1)
                        } label: {
                            Label("이전 프레임", systemImage: "chevron.left")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(orderedSelectedRegionIndices.count < 2)
                        .accessibilityIdentifier(
                            "monglepet.spriteSheet.previousSelectedRegion"
                        )

                        Spacer()

                        Text(
                            "\(previewRegionPosition + 1) / "
                                + "\(orderedSelectedRegionIndices.count)"
                        )
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel(
                            "선택 영역 \(previewRegionPosition + 1) / "
                                + "\(orderedSelectedRegionIndices.count)"
                        )

                        Spacer()

                        Button {
                            movePreviewRegion(by: 1)
                        } label: {
                            Label("다음 프레임", systemImage: "chevron.right")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(orderedSelectedRegionIndices.count < 2)
                        .accessibilityIdentifier(
                            "monglepet.spriteSheet.nextSelectedRegion"
                        )
                    }

                    Button {
                        movePreviewRegion(by: 1)
                    } label: {
                        CroppedImagePreview(
                            image: previewImage,
                            cropRect: previewRegionBinding.wrappedValue.rect,
                            flipsHorizontally: previewRegionBinding
                                .wrappedValue.flipsHorizontally,
                            flipsVertically: previewRegionBinding
                                .wrappedValue.flipsVertically,
                            canvasSize: commonPreviewCanvasSize
                        )
                        .frame(height: 130)
                        .overlay(alignment: .bottomTrailing) {
                            Text(
                                "\(previewRegionBinding.wrappedValue.rect.width)×"
                                    + "\(previewRegionBinding.wrappedValue.rect.height) px"
                            )
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("다음 선택 프레임 미리보기")
                    .accessibilityIdentifier(
                        "monglepet.spriteSheet.selectedRegionPreview"
                    )

                    HStack {
                        Button {
                            previewRegionBinding.wrappedValue
                                .flipsHorizontally.toggle()
                        } label: {
                            Label(
                                previewRegionBinding.wrappedValue.flipsHorizontally
                                    ? "좌우 뒤집기 해제"
                                    : "좌우 뒤집기",
                                systemImage: "arrow.left.and.right"
                            )
                        }
                        .accessibilityIdentifier(
                            "monglepet.spriteSheet.flipHorizontal"
                        )

                        Button {
                            previewRegionBinding.wrappedValue
                                .flipsVertically.toggle()
                        } label: {
                            Label(
                                previewRegionBinding.wrappedValue.flipsVertically
                                    ? "상하 뒤집기 해제"
                                    : "상하 뒤집기",
                                systemImage: "arrow.up.and.down"
                            )
                        }
                        .accessibilityIdentifier(
                            "monglepet.spriteSheet.flipVertical"
                        )
                    }
                    .controlSize(.small)

                    Text("파란 경계는 선택한 프레임의 공통 캔버스입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "가져올 프레임을 선택하면 여기에서 확인할 수 있습니다.",
                        systemImage: "rectangle.dashed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .accessibilityIdentifier("monglepet.spriteSheet.selectedRegionPanel")
    }

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("경계 설정") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("자동 제안으로 되돌리기") {
                        useSuggestedRegions()
                    }

                    Divider()

                    Text("일정한 격자로 다시 나누기")
                        .font(.subheadline.weight(.semibold))

                    HStack {
                        Text("행")
                        Spacer()
                        TextField("행", value: rowsBinding, format: .number)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("monglepet.spriteSheet.rows")
                        Stepper("", value: rowsBinding, in: 1...32)
                            .labelsHidden()
                    }

                    HStack {
                        Text("열")
                        Spacer()
                        TextField("열", value: columnsBinding, format: .number)
                            .frame(width: 48)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("monglepet.spriteSheet.columns")
                        Stepper("", value: columnsBinding, in: 1...32)
                            .labelsHidden()
                    }
                    Stepper("안쪽 여백 \(inset) px", value: $inset, in: 0...64)

                    Button("격자 적용") {
                        applyGrid()
                    }
                    .disabled(rows * columns > 1_000)
                }
                .padding(6)
            }

            if interactionMode == .bounds {
                GroupBox("선택한 범위") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let editingRegionBinding {
                            CropRectNumericControls(
                                rect: editingRegionBinding.rect,
                                pixelSize: document.pixelSize
                            )

                            Button("모든 경계에 이 크기 적용") {
                                applyEditingRegionSizeToAll()
                            }

                            Text("경계 안을 드래그해 이동하고 모서리·변의 핸들로 크기를 조절할 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("편집할 경계를 선택해 주세요.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
            }

            GroupBox("프레임 순서") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("순서 지정", selection: $frameOrderMode) {
                        ForEach(SpriteSheetFrameOrderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("monglepet.spriteSheet.orderMode")
                    .onChange(of: frameOrderMode) {
                        preserveSelectionForOrderMode()
                    }

                    Text(
                        frameOrderMode == .reading
                            ? "선택한 프레임을 위에서 아래, 왼쪽에서 오른쪽 순서로 가져옵니다."
                            : "경계를 누른 순서대로 1, 2, 3… 재생 순서를 지정합니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                requestDismissal()
            }

            Button {
                importSelectedFrames()
            } label: {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("선택한 프레임 추가")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRegions.isEmpty || isProcessing)
            .accessibilityIdentifier("monglepet.spriteSheet.import")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedRegions: [SpriteSheetFrameSelection] {
        orderedSelectedRegionIndices.map { index in
            SpriteSheetFrameSelection(
                rect: regions[index].rect,
                flipsHorizontally: regions[index].flipsHorizontally,
                flipsVertically: regions[index].flipsVertically
            )
        }
    }

    private var commonPreviewCanvasSize: PixelSize {
        ImageCropResultPreviewGeometry.commonCanvasSize(
            for: selectedRegions.map(\.rect)
        )
    }

    private var orderedSelectedRegionIndices: [Int] {
        SpriteSheetFrameExtractor().orderedSelectedRegionIndices(
            regionCount: regions.count,
            selectedIndices: Set(
                regions.indices.filter { regions[$0].isSelected }
            ),
            clickedOrder: frameOrderMode == .clicked ? clickedRegionOrder : nil
        )
    }

    private var frameSelectionHelp: String {
        frameOrderMode == .reading
            ? "경계를 클릭해 가져올 프레임을 선택하거나 제외할 수 있습니다."
            : "가져올 프레임을 원하는 재생 순서대로 클릭해 주세요. 다시 누르면 제외됩니다."
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

    private var rowsBinding: Binding<Int> {
        gridDimensionBinding(value: $rows)
    }

    private var columnsBinding: Binding<Int> {
        gridDimensionBinding(value: $columns)
    }

    private func gridDimensionBinding(value: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { min(32, max(1, value.wrappedValue)) },
            set: { value.wrappedValue = min(32, max(1, $0)) }
        )
    }

    private func byte(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255).rounded()))
    }

    private func useSuggestedRegions() {
        regions = document.suggestedRegions.map {
            SelectableSpriteRegion(rect: $0)
        }
        let dimensions = SpriteSheetFrameExtractor().inferredGridDimensions(
            for: document.suggestedRegions
        )
        rows = dimensions.rows
        columns = dimensions.columns
        inset = 0
        editingRegionID = regions.first?.id
        previewRegionID = regions.first?.id
        resetSelectionForCurrentOrderMode()
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
            editingRegionID = regions.first?.id
            previewRegionID = regions.first?.id
            resetSelectionForCurrentOrderMode()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setAllRegionsSelected(_ isSelected: Bool) {
        for index in regions.indices {
            regions[index].isSelected = isSelected
        }
        clickedRegionOrder = isSelected ? Array(regions.indices) : []
        normalizePreviewRegion()
    }

    private func preserveSelectionForOrderMode() {
        if frameOrderMode == .clicked {
            clickedRegionOrder = regions.indices.filter {
                regions[$0].isSelected
            }
        }
        normalizePreviewRegion()
        hasEdits = true
        errorMessage = nil
    }

    private func resetSelectionForCurrentOrderMode() {
        switch frameOrderMode {
        case .reading:
            setAllRegionsSelected(true)
        case .clicked:
            setAllRegionsSelected(false)
        }
    }

    private func toggleRegion(at index: Int) {
        guard regions.indices.contains(index) else {
            return
        }
        if regions[index].isSelected {
            regions[index].isSelected = false
            clickedRegionOrder.removeAll { $0 == index }
        } else {
            regions[index].isSelected = true
            if frameOrderMode == .clicked {
                clickedRegionOrder.append(index)
            }
            previewRegionID = regions[index].id
        }
        normalizePreviewRegion()
    }

    private func displayedOrderNumber(for index: Int) -> Int? {
        guard regions.indices.contains(index), regions[index].isSelected else {
            return nil
        }
        guard let orderIndex = orderedSelectedRegionIndices.firstIndex(of: index) else {
            return nil
        }
        return orderIndex + 1
    }

    private var editingRegionBinding: Binding<SelectableSpriteRegion>? {
        guard let editingRegionID,
              let index = regions.firstIndex(where: { $0.id == editingRegionID }) else {
            return nil
        }
        return $regions[index]
    }

    private var previewRegionBinding: Binding<SelectableSpriteRegion>? {
        guard let previewRegionID,
              let index = regions.firstIndex(where: { $0.id == previewRegionID }),
              regions[index].isSelected else {
            return nil
        }
        return $regions[index]
    }

    private var previewRegionPosition: Int? {
        guard let previewRegionID else {
            return nil
        }
        return orderedSelectedRegionIndices.firstIndex {
            regions[$0].id == previewRegionID
        }
    }

    private func normalizePreviewRegion() {
        let orderedIDs = orderedSelectedRegionIndices.map { regions[$0].id }
        guard !orderedIDs.isEmpty else {
            previewRegionID = nil
            return
        }
        if let previewRegionID, orderedIDs.contains(previewRegionID) {
            return
        }
        previewRegionID = orderedIDs.first
    }

    private func movePreviewRegion(by offset: Int) {
        let orderedIDs = orderedSelectedRegionIndices.map { regions[$0].id }
        guard !orderedIDs.isEmpty else {
            previewRegionID = nil
            return
        }
        guard let previewRegionID,
              let currentIndex = orderedIDs.firstIndex(of: previewRegionID) else {
            self.previewRegionID = orderedIDs.first
            return
        }
        let nextIndex = (currentIndex + offset + orderedIDs.count) % orderedIDs.count
        self.previewRegionID = orderedIDs[nextIndex]
    }

    private func applyEditingRegionSizeToAll() {
        guard let editingRegionBinding else {
            return
        }
        let selected = editingRegionBinding.wrappedValue.rect
        let geometry = ImageCropGeometry()
        for index in regions.indices {
            let region = regions[index].rect
            let centerX = region.x + region.width / 2
            let centerY = region.y + region.height / 2
            regions[index].rect = geometry.clamped(
                PixelRect(
                    x: centerX - selected.width / 2,
                    y: centerY - selected.height / 2,
                    width: selected.width,
                    height: selected.height
                ),
                to: document.pixelSize
            )
        }
    }

    private func refreshPreview() {
        previewRevision += 1
        let revision = previewRevision
        let document = document
        let backgroundRemoval = backgroundRemoval
        isProcessing = true
        errorMessage = nil
        hasEdits = true
        Task {
            do {
                let image = try await Task.detached {
                    try SpriteSheetFrameExtractor().processedImage(
                        from: document,
                        removingBackground: backgroundRemoval
                    )
                }.value
                guard revision == previewRevision else { return }
                previewImage = image
                isProcessing = false
            } catch {
                guard revision == previewRevision else { return }
                isProcessing = false
                errorMessage = error.localizedDescription
            }
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
        let selections = selectedRegions
        guard !selections.isEmpty else { return }
        let document = document
        let backgroundRemoval = backgroundRemoval
        let sourceName = document.sourceURL.deletingPathExtension().lastPathComponent
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let images = try await Task.detached {
                    try SpriteSheetFrameExtractor().extractFrames(
                        from: document,
                        selections: selections,
                        removingBackground: backgroundRemoval
                    )
                }.value
                isProcessing = false
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
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestDismissal() {
        if hasEdits {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

struct SpriteSheetEditorLayout {
    static let sidebarWidth: CGFloat = 290
    static let columnSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 40
    static let verticalPadding: CGFloat = 40
    static let previewChromeHeight: CGFloat = 118
    static let minimumCanvasHeight: CGFloat = 160

    static func canvasHeight(
        pixelSize: PixelSize,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> CGFloat {
        let sourceWidth = CGFloat(max(1, pixelSize.width))
        let sourceHeight = CGFloat(max(1, pixelSize.height))
        let aspectFitHeight = max(1, availableWidth) * sourceHeight / sourceWidth
        let upperBound = max(minimumCanvasHeight, availableHeight)
        return min(max(minimumCanvasHeight, aspectFitHeight), upperBound)
    }
}

private struct SelectableSpriteRegion: Identifiable, Equatable {
    let id = UUID()
    var rect: PixelRect
    var isSelected = true
    var flipsHorizontally = false
    var flipsVertically = false
}

private struct SpriteSheetRegionPreview: View {
    let image: CGImage
    let pixelSize: PixelSize
    @Binding var regions: [SelectableSpriteRegion]
    @Binding var editingRegionID: UUID?
    let zoomScale: Double
    let interactionMode: SpriteSheetInteractionMode
    let orderNumber: (Int) -> Int?
    let onToggleRegion: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentSize = CGSize(
                width: geometry.size.width * zoomScale,
                height: geometry.size.height * zoomScale
            )
            let imageFrame = aspectFitFrame(in: contentSize)
            Group {
                if ImageEditorViewportPolicy.usesInternalPan(at: zoomScale) {
                    ScrollView([.horizontal, .vertical]) {
                        regionEditorCanvas(
                            contentSize: contentSize,
                            imageFrame: imageFrame
                        )
                    }
                } else {
                    regionEditorCanvas(
                        contentSize: contentSize,
                        imageFrame: imageFrame
                    )
                }
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func regionEditorCanvas(
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

            ForEach(regions.indices, id: \.self) { index in
                let region = regions[index]
                let frame = displayFrame(for: region.rect, in: imageFrame)
                ZStack(alignment: .topLeading) {
                    if interactionMode == .bounds,
                       region.id == editingRegionID {
                        CropRectangleEditorOverlay(
                            cropRect: $regions[index].rect,
                            pixelSize: pixelSize,
                            imageFrame: imageFrame
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                region.isSelected
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.black.opacity(0.24)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        region.isSelected
                                            ? Color.accentColor
                                            : Color.secondary,
                                        lineWidth: region.isSelected ? 2 : 1
                                    )
                            }
                            .contentShape(Rectangle())
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .onTapGesture {
                                if interactionMode == .selection {
                                    onToggleRegion(index)
                                } else {
                                    editingRegionID = region.id
                                }
                            }
                    }

                    if let order = orderNumber(index) {
                        Text("\(order)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .position(
                                x: frame.minX + 16,
                                y: frame.minY + 14
                            )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .zIndex(region.id == editingRegionID ? 10 : 0)
                .accessibilityLabel("\(index + 1)번 경계")
                .accessibilityValue(
                    orderNumber(index).map { "재생 순서 \($0)" } ?? "제외됨"
                )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .coordinateSpace(name: ImageCropDisplayGeometry.coordinateSpaceName)
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
