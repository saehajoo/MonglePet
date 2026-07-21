import AppKit

@MainActor
final class PetOverlayView: NSView {
    let atlasPixelSize: PixelSize

    private let atlasID: String
    private var displayedFrame: MotionFrame?

    init?(atlasID: String, image: NSImage) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        self.atlasID = atlasID
        atlasPixelSize = PixelSize(width: cgImage.width, height: cgImage.height)
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
            frame.atlasID == atlasID,
            frame.sourceRect.isContained(in: atlasPixelSize)
        else {
            return false
        }

        guard displayedFrame != frame else {
            return true
        }

        let sourceRect = frame.sourceRect
        let atlasWidth = CGFloat(atlasPixelSize.width)
        let atlasHeight = CGFloat(atlasPixelSize.height)
        let normalizedRect = CGRect(
            x: CGFloat(sourceRect.x) / atlasWidth,
            y: CGFloat(atlasPixelSize.height - sourceRect.y - sourceRect.height) / atlasHeight,
            width: CGFloat(sourceRect.width) / atlasWidth,
            height: CGFloat(sourceRect.height) / atlasHeight
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsRect = normalizedRect
        CATransaction.commit()
        displayedFrame = frame
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
