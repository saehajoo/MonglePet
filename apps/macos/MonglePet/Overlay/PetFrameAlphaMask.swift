import CoreGraphics

nonisolated struct PetFrameAlphaMask: Equatable, Sendable {
    let width: Int
    let height: Int
    let alphaValues: [UInt8]

    init(width: Int, height: Int, alphaValues: [UInt8]) {
        precondition(width > 0)
        precondition(height > 0)
        precondition(alphaValues.count == width * height)
        self.width = width
        self.height = height
        self.alphaValues = alphaValues
    }

    func containsVisiblePixel(
        normalizedX: Double,
        normalizedY: Double
    ) -> Bool {
        guard normalizedX.isFinite,
              normalizedY.isFinite,
              (0...1).contains(normalizedX),
              (0...1).contains(normalizedY) else {
            return false
        }

        let x = min(Int(normalizedX * Double(width)), width - 1)
        let y = min(Int(normalizedY * Double(height)), height - 1)
        return alphaValues[y * width + x] > 0
    }

    static func normalizedContentPoint(
        pointX: Double,
        pointY: Double,
        boundsWidth: Double,
        boundsHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) -> (x: Double, y: Double)? {
        guard pointX.isFinite,
              pointY.isFinite,
              boundsWidth.isFinite,
              boundsHeight.isFinite,
              contentWidth.isFinite,
              contentHeight.isFinite,
              boundsWidth > 0,
              boundsHeight > 0,
              contentWidth > 0,
              contentHeight > 0 else {
            return nil
        }

        let scale = min(
            boundsWidth / contentWidth,
            boundsHeight / contentHeight
        )
        let displayedWidth = contentWidth * scale
        let displayedHeight = contentHeight * scale
        let minimumX = (boundsWidth - displayedWidth) / 2
        let minimumY = (boundsHeight - displayedHeight) / 2

        guard pointX >= minimumX,
              pointX <= minimumX + displayedWidth,
              pointY >= minimumY,
              pointY <= minimumY + displayedHeight else {
            return nil
        }

        return (
            x: (pointX - minimumX) / displayedWidth,
            y: (pointY - minimumY) / displayedHeight
        )
    }
}

@MainActor
enum PetFrameAlphaMaskBuilder {
    static let maximumDimension = 64

    static func make(
        atlasImage: CGImage,
        sourceRect: PixelRect
    ) -> PetFrameAlphaMask? {
        guard sourceRect.isContained(
            in: PixelSize(
                width: atlasImage.width,
                height: atlasImage.height
            )
        ) else {
            return nil
        }

        let cropRect = CGRect(
            x: sourceRect.x,
            y: sourceRect.y,
            width: sourceRect.width,
            height: sourceRect.height
        )
        guard let croppedImage = atlasImage.cropping(to: cropRect) else {
            return nil
        }

        let scale = min(
            1,
            Double(maximumDimension)
                / Double(max(sourceRect.width, sourceRect.height))
        )
        let width = max(1, Int((Double(sourceRect.width) * scale).rounded()))
        let height = max(1, Int((Double(sourceRect.height) * scale).rounded()))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        let didDraw = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(
                croppedImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didDraw else {
            return nil
        }

        var alphaValues = [UInt8](repeating: 0, count: width * height)
        for index in alphaValues.indices {
            alphaValues[index] = rgba[index * 4 + 3]
        }
        return PetFrameAlphaMask(
            width: width,
            height: height,
            alphaValues: alphaValues
        )
    }
}
