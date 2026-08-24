import CoreGraphics
import Foundation

nonisolated enum ImageCropHandle: CaseIterable, Hashable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var movesLeftEdge: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    var movesRightEdge: Bool {
        self == .topRight || self == .bottomRight || self == .right
    }

    var movesTopEdge: Bool {
        self == .topLeft || self == .topRight || self == .top
    }

    var movesBottomEdge: Bool {
        self == .bottomLeft || self == .bottomRight || self == .bottom
    }
}

nonisolated struct ImageCropGeometry {
    let minimumDimension: Int

    init(minimumDimension: Int = 1) {
        self.minimumDimension = max(1, minimumDimension)
    }

    func clamped(_ rect: PixelRect, to pixelSize: PixelSize) -> PixelRect {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return PixelRect(x: 0, y: 0, width: 1, height: 1)
        }
        let minimumWidth = min(minimumDimension, pixelSize.width)
        let minimumHeight = min(minimumDimension, pixelSize.height)
        let width = min(pixelSize.width, max(minimumWidth, rect.width))
        let height = min(pixelSize.height, max(minimumHeight, rect.height))
        return PixelRect(
            x: min(max(0, rect.x), pixelSize.width - width),
            y: min(max(0, rect.y), pixelSize.height - height),
            width: width,
            height: height
        )
    }

    func moving(
        _ rect: PixelRect,
        byX deltaX: Int,
        y deltaY: Int,
        in pixelSize: PixelSize
    ) -> PixelRect {
        let rect = clamped(rect, to: pixelSize)
        return PixelRect(
            x: min(max(0, rect.x + deltaX), pixelSize.width - rect.width),
            y: min(max(0, rect.y + deltaY), pixelSize.height - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    func resizing(
        _ rect: PixelRect,
        handle: ImageCropHandle,
        byX deltaX: Int,
        y deltaY: Int,
        in pixelSize: PixelSize
    ) -> PixelRect {
        let rect = clamped(rect, to: pixelSize)
        var left = rect.x
        var top = rect.y
        var right = rect.x + rect.width
        var bottom = rect.y + rect.height

        if handle.movesLeftEdge {
            left = min(max(0, left + deltaX), right - minimumDimension)
        }
        if handle.movesRightEdge {
            right = max(
                min(pixelSize.width, right + deltaX),
                left + minimumDimension
            )
        }
        if handle.movesTopEdge {
            top = min(max(0, top + deltaY), bottom - minimumDimension)
        }
        if handle.movesBottomEdge {
            bottom = max(
                min(pixelSize.height, bottom + deltaY),
                top + minimumDimension
            )
        }

        return PixelRect(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }
}

nonisolated struct ImageCropProcessor {
    func crop(_ image: CGImage, to rect: PixelRect) -> CGImage? {
        let pixelSize = PixelSize(width: image.width, height: image.height)
        guard rect.isContained(in: pixelSize) else {
            return nil
        }
        return image.cropping(
            to: CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        )
    }

    func transformed(
        _ image: CGImage,
        flipsHorizontally: Bool,
        flipsVertically: Bool
    ) -> CGImage? {
        guard flipsHorizontally || flipsVertically else {
            return image
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.translateBy(
            x: flipsHorizontally ? CGFloat(image.width) : 0,
            y: flipsVertically ? CGFloat(image.height) : 0
        )
        context.scaleBy(
            x: flipsHorizontally ? -1 : 1,
            y: flipsVertically ? -1 : 1
        )
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context.makeImage()
    }

    func cropAndTransform(
        _ image: CGImage,
        to rect: PixelRect,
        flipsHorizontally: Bool,
        flipsVertically: Bool
    ) -> CGImage? {
        guard let cropped = crop(image, to: rect) else {
            return nil
        }
        return transformed(
            cropped,
            flipsHorizontally: flipsHorizontally,
            flipsVertically: flipsVertically
        )
    }
}
