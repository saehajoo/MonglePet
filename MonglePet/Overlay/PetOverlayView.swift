import AppKit

@MainActor
struct PetAtlasImage {
    let id: String
    let image: CGImage
    let pixelSize: PixelSize
}

@MainActor
final class PetOverlayView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var onPetting: (() -> Void)?
    var allowsWindowDragging = true

    private var atlases: [String: PetAtlasImage]
    private(set) var displayedAtlasID: String?
    private var displayedFrame: MotionFrame?

    var atlasPixelSize: PixelSize {
        atlases.values.first?.pixelSize ?? PixelSize(width: 1, height: 1)
    }

    init?(atlasID: String, image: NSImage) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let atlas = PetAtlasImage(
            id: atlasID,
            image: cgImage,
            pixelSize: PixelSize(width: cgImage.width, height: cgImage.height)
        )
        atlases = [atlasID: atlas]
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contents = cgImage
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("몽글이")
        setAccessibilityIdentifier("monglepet.overlay.pet")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func display(_ frame: MotionFrame) -> Bool {
        guard
            let atlas = atlases[frame.atlasID],
            frame.sourceRect.isContained(in: atlas.pixelSize)
        else {
            return false
        }

        guard displayedFrame != frame else {
            return true
        }

        let sourceRect = frame.sourceRect
        let atlasWidth = CGFloat(atlas.pixelSize.width)
        let atlasHeight = CGFloat(atlas.pixelSize.height)
        let normalizedRect = CGRect(
            x: CGFloat(sourceRect.x) / atlasWidth,
            y: CGFloat(atlas.pixelSize.height - sourceRect.y - sourceRect.height) / atlasHeight,
            width: CGFloat(sourceRect.width) / atlasWidth,
            height: CGFloat(sourceRect.height) / atlasHeight
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if displayedAtlasID != atlas.id {
            layer?.contents = atlas.image
            displayedAtlasID = atlas.id
        }
        layer?.contentsRect = normalizedRect
        CATransaction.commit()
        displayedFrame = frame
        return true
    }

    func replaceAtlases(_ atlases: [PetAtlasImage], accessibilityLabel: String) {
        self.atlases = Dictionary(uniqueKeysWithValues: atlases.map { ($0.id, $0) })
        displayedAtlasID = nil
        displayedFrame = nil
        layer?.contents = nil
        layer?.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        setAccessibilityLabel(accessibilityLabel)
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsWindowDragging else {
            return
        }
        let initialOrigin = window?.frame.origin
        onDragBegan?()
        window?.performDrag(with: event)
        let finalOrigin = window?.frame.origin
        let didMove = Self.didMove(
            from: initialOrigin,
            to: finalOrigin
        )
        onDragEnded?(didMove)
        if !didMove {
            onPetting?()
        }
    }

    nonisolated static func didMove(
        from initialOrigin: NSPoint?,
        to finalOrigin: NSPoint?,
        threshold: CGFloat = 3
    ) -> Bool {
        guard
            let initialOrigin,
            let finalOrigin,
            threshold.isFinite,
            threshold >= 0
        else {
            return false
        }
        return hypot(
            finalOrigin.x - initialOrigin.x,
            finalOrigin.y - initialOrigin.y
        ) >= threshold
    }
}
