import SwiftUI

struct ExistingPetFramePickerPresentation: Identifiable {
    let id = UUID()
    let petName: String
    let groups: [ExistingPetFrameGroup]
}

nonisolated struct ExistingPetFrameID: Hashable, Sendable {
    let motionID: String
    let frameIndex: Int
}

nonisolated struct ExistingPetFrameAsset: Identifiable, @unchecked Sendable {
    let id: ExistingPetFrameID
    let motionID: String
    let frameIndex: Int
    let durationMilliseconds: Int
    let image: CGImage
    let centeredPreviewImage: CGImage
}

nonisolated struct ExistingPetFrameGroup: Identifiable, @unchecked Sendable {
    let id: String
    let frames: [ExistingPetFrameAsset]
}

nonisolated struct ExistingPetFrameSelection: @unchecked Sendable {
    let image: UserPetSourceImage
    let durationMilliseconds: Int
}

nonisolated enum ExistingPetFrameLibraryError: Error, Equatable, Sendable {
    case cannotLoadAtlases
    case cannotReadFrame(String, Int)
}

extension ExistingPetFrameLibraryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotLoadAtlases:
            "현재 펫의 애니메이션 이미지를 불러오지 못했습니다."
        case let .cannotReadFrame(motionID, frameIndex):
            "\(motionID) 애니메이션의 \(frameIndex + 1)번 프레임을 읽지 못했습니다."
        }
    }
}

@MainActor
enum ExistingPetFrameLibrary {
    static func load(from item: PetLibraryItem) throws
        -> [ExistingPetFrameGroup] {
        let atlases: [PetAtlasImage]
        do {
            atlases = try PetPresentationResourceLoader.loadAtlases(for: item)
        } catch {
            throw ExistingPetFrameLibraryError.cannotLoadAtlases
        }
        let atlasImages = Dictionary(
            uniqueKeysWithValues: atlases.map { ($0.id, $0.image) }
        )
        return try item.definition.motions.map { motion in
            let frames = try motion.frames.enumerated().map { index, frame in
                guard let image = atlasImages[frame.atlasID]?.cropping(
                    to: CGRect(
                        x: frame.sourceRect.x,
                        y: frame.sourceRect.y,
                        width: frame.sourceRect.width,
                        height: frame.sourceRect.height
                    )
                ) else {
                    throw ExistingPetFrameLibraryError.cannotReadFrame(
                        motion.id,
                        index
                    )
                }
                return ExistingPetFrameAsset(
                    id: ExistingPetFrameID(
                        motionID: motion.id,
                        frameIndex: index
                    ),
                    motionID: motion.id,
                    frameIndex: index,
                    durationMilliseconds: durationMilliseconds(frame.duration),
                    image: image,
                    centeredPreviewImage: centeredPreviewImage(from: image)
                )
            }
            return ExistingPetFrameGroup(id: motion.id, frames: frames)
        }
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: value)
    }

    private static func centeredPreviewImage(from image: CGImage) -> CGImage {
        (try? FrameCanvasComposer().transparentContent(in: image).image) ?? image
    }
}

struct ExistingPetFramePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let petName: String
    let groups: [ExistingPetFrameGroup]
    let onImport: ([ExistingPetFrameSelection]) -> Void

    @State private var selectionOrder: [ExistingPetFrameID] = []

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("현재 펫 프레임에서 추가")
                    .font(.title2.weight(.semibold))
                Text("\(petName)의 애니메이션 프레임을 누른 순서대로 새 애니메이션에 추가합니다.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.id)
                                        .font(.headline)
                                    Text("\(group.frames.count)프레임")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("이 애니메이션 모두 선택") {
                                        appendUnselected(group.frames)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }

                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(group.frames) { frame in
                                        frameButton(frame)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("선택 순서 미리보기")
                            .font(.headline)
                        Spacer()
                        Text("\(selectionOrder.count)개")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    ExistingPetFrameSequencePreview(frames: selectedFrames)
                        .frame(height: 220)

                    if selectionOrder.isEmpty {
                        Text("왼쪽 프레임을 누르면 선택 순서가 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                ForEach(Array(selectedFrames.enumerated()), id: \.element.id) {
                                    index,
                                    frame in
                                    VStack(spacing: 3) {
                                        Image(
                                            decorative: frame.centeredPreviewImage,
                                            scale: 1
                                        )
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 48, height: 48)
                                        Text("\(index + 1)")
                                            .font(.caption2.monospacedDigit())
                                    }
                                }
                            }
                        }
                        .frame(height: 72)
                    }

                    Text("기존 프레임 간격을 유지합니다. 추가 후 좌우·상하 반전, 복사, 순서와 간격을 다시 편집할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack {
                        Button("전체 선택") {
                            appendUnselected(groups.flatMap(\.frames))
                        }
                        Button("전체 해제") {
                            selectionOrder.removeAll()
                        }
                        .disabled(selectionOrder.isEmpty)
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 20)
                .padding(.trailing, 20)
                .frame(width: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("선택한 프레임 추가") {
                    onImport(selectedFrames.map { frame in
                        ExistingPetFrameSelection(
                            image: UserPetSourceImage(
                                displayName: "\(frame.motionID) \(frame.frameIndex + 1)",
                                image: frame.image
                            ),
                            durationMilliseconds: frame.durationMilliseconds
                        )
                    })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectionOrder.isEmpty)
                .accessibilityIdentifier(
                    "monglepet.existingFrames.addSelection"
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 880, idealWidth: 980, minHeight: 620, idealHeight: 720)
    }

    private var framesByID: [ExistingPetFrameID: ExistingPetFrameAsset] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap(\.frames).map { ($0.id, $0) }
        )
    }

    private var selectedFrames: [ExistingPetFrameAsset] {
        let framesByID = framesByID
        return selectionOrder.compactMap { framesByID[$0] }
    }

    private func frameButton(_ frame: ExistingPetFrameAsset) -> some View {
        let selectionNumber = selectionOrder.firstIndex(of: frame.id).map { $0 + 1 }
        return Button {
            toggle(frame.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    CheckerboardCanvas(cellSize: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Image(
                        decorative: frame.centeredPreviewImage,
                        scale: 1
                    )
                        .resizable()
                        .scaledToFit()
                        .padding(5)

                    if let selectionNumber {
                        Text("\(selectionNumber)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .padding(5)
                    }
                }
                .frame(height: 82)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            selectionNumber == nil
                                ? Color.secondary.opacity(0.35)
                                : Color.accentColor,
                            lineWidth: selectionNumber == nil ? 1 : 2
                        )
                }

                HStack {
                    Text("#\(frame.frameIndex + 1)")
                    Spacer()
                    Text("\(frame.durationMilliseconds)ms")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(frame.motionID) \(frame.frameIndex + 1)번 프레임, \(frame.durationMilliseconds)밀리초"
        )
        .accessibilityValue(
            selectionNumber.map { "선택 순서 \($0)" } ?? "선택 안 함"
        )
    }

    private func toggle(_ id: ExistingPetFrameID) {
        if let index = selectionOrder.firstIndex(of: id) {
            selectionOrder.remove(at: index)
        } else {
            selectionOrder.append(id)
        }
    }

    private func appendUnselected(_ frames: [ExistingPetFrameAsset]) {
        for frame in frames where !selectionOrder.contains(frame.id) {
            selectionOrder.append(frame.id)
        }
    }
}

private struct ExistingPetFrameSequencePreview: View {
    let frames: [ExistingPetFrameAsset]

    var body: some View {
        ZStack {
            CheckerboardCanvas(cellSize: 10)
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)

            if frames.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let frame = frame(at: context.date)
                    Image(
                        decorative: frame.centeredPreviewImage,
                        scale: 1
                    )
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("선택한 프레임 재생 미리보기")
    }

    private func frame(at date: Date) -> ExistingPetFrameAsset {
        let totalDuration = max(
            1,
            frames.reduce(0) { $0 + max(1, $1.durationMilliseconds) }
        )
        let elapsed = Int(
            (date.timeIntervalSinceReferenceDate * 1_000).rounded(.down)
        ) % totalDuration
        var boundary = 0
        for frame in frames {
            boundary += max(1, frame.durationMilliseconds)
            if elapsed < boundary {
                return frame
            }
        }
        return frames[frames.index(before: frames.endIndex)]
    }
}

private struct CheckerboardCanvas: View {
    let cellSize: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.secondary.opacity(0.035))
            )
            let columns = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cellSize,
                                y: CGFloat(row) * cellSize,
                                width: cellSize,
                                height: cellSize
                            )
                        ),
                        with: .color(Color.secondary.opacity(0.075))
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
