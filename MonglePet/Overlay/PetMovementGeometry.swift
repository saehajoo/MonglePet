import Foundation

nonisolated struct PetMovementPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

nonisolated struct PetMovementSize: Equatable, Sendable {
    let width: Double
    let height: Double

    var isValid: Bool {
        width.isFinite && width > 0
            && height.isFinite && height > 0
    }
}

nonisolated struct PetMovementRect: Equatable, Sendable {
    let origin: PetMovementPoint
    let size: PetMovementSize

    init(x: Double, y: Double, width: Double, height: Double) {
        origin = PetMovementPoint(x: x, y: y)
        size = PetMovementSize(width: width, height: height)
    }

    var minX: Double { origin.x }
    var minY: Double { origin.y }
    var maxX: Double { origin.x + size.width }
    var maxY: Double { origin.y + size.height }
    var midX: Double { origin.x + (size.width / 2) }
    var midY: Double { origin.y + (size.height / 2) }
    var center: PetMovementPoint { PetMovementPoint(x: midX, y: midY) }

    var isValid: Bool {
        origin.isFinite && size.isValid && maxX.isFinite && maxY.isFinite
    }

    func contains(_ point: PetMovementPoint) -> Bool {
        isValid && point.isFinite
            && point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }
}

nonisolated struct PetMovementScreen: Equatable, Sendable {
    let id: String
    let visibleFrame: PetMovementRect
}

nonisolated struct PetMovementWindow: Equatable, Sendable {
    let frame: PetMovementRect
}

nonisolated struct PetMovementRandomSample: Equatable, Sendable {
    let screen: Double
    let horizontal: Double
    let vertical: Double
}

nonisolated struct PetMovementOriginBounds: Equatable, Sendable {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    func contains(_ point: PetMovementPoint) -> Bool {
        point.isFinite
            && point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }

    func clamped(_ point: PetMovementPoint) -> PetMovementPoint {
        PetMovementPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    func point(horizontal: Double, vertical: Double) -> PetMovementPoint {
        let normalizedHorizontal = Self.normalizedUnitValue(horizontal)
        let normalizedVertical = Self.normalizedUnitValue(vertical)
        return PetMovementPoint(
            x: minX + ((maxX - minX) * normalizedHorizontal),
            y: minY + ((maxY - minY) * normalizedVertical)
        )
    }

    func intersection(
        with other: PetMovementOriginBounds
    ) -> PetMovementOriginBounds? {
        let intersectionMinX = max(minX, other.minX)
        let intersectionMaxX = min(maxX, other.maxX)
        let intersectionMinY = max(minY, other.minY)
        let intersectionMaxY = min(maxY, other.maxY)
        guard intersectionMinX <= intersectionMaxX,
              intersectionMinY <= intersectionMaxY else {
            return nil
        }
        return PetMovementOriginBounds(
            minX: intersectionMinX,
            maxX: intersectionMaxX,
            minY: intersectionMinY,
            maxY: intersectionMaxY
        )
    }

    private static func normalizedUnitValue(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
}

nonisolated struct PetMovementAdvance: Equatable, Sendable {
    let origin: PetMovementPoint
    let didMove: Bool
    let hasArrived: Bool
}

nonisolated struct PetMovementScreenTransition: Equatable, Sendable {
    let sourceScreenID: String
    let targetScreenID: String
    let exitOrigin: PetMovementPoint
    let entryOrigin: PetMovementPoint
}

nonisolated struct PetMovementCursorRoute: Equatable, Sendable {
    let targetOrigin: PetMovementPoint
    let transition: PetMovementScreenTransition?
}

nonisolated enum PetMovementGeometry {
    static func safeOriginBounds(
        in visibleFrame: PetMovementRect,
        petSize: PetMovementSize,
        inset: Double
    ) -> PetMovementOriginBounds? {
        guard visibleFrame.isValid, petSize.isValid, inset.isFinite else {
            return nil
        }

        let safeInset = max(0, inset)
        let minimumX = visibleFrame.minX + safeInset
        let maximumX = visibleFrame.maxX - safeInset - petSize.width
        let minimumY = visibleFrame.minY + safeInset
        let maximumY = visibleFrame.maxY - safeInset - petSize.height

        let centeredX = visibleFrame.midX - (petSize.width / 2)
        let centeredY = visibleFrame.midY - (petSize.height / 2)
        return PetMovementOriginBounds(
            minX: minimumX <= maximumX ? minimumX : centeredX,
            maxX: minimumX <= maximumX ? maximumX : centeredX,
            minY: minimumY <= maximumY ? minimumY : centeredY,
            maxY: minimumY <= maximumY ? maximumY : centeredY
        )
    }

    static func cursorFollowingTargetOrigin(
        pointer: PetMovementPoint,
        currentOrigin: PetMovementPoint,
        petSize: PetMovementSize,
        cursorDistance: Double,
        screenInset: Double,
        screens: [PetMovementScreen]
    ) -> PetMovementPoint? {
        cursorFollowingRoute(
            pointer: pointer,
            currentOrigin: currentOrigin,
            petSize: petSize,
            cursorDistance: cursorDistance,
            screenInset: screenInset,
            screens: screens
        )?.targetOrigin
    }

    static func cursorFollowingRoute(
        pointer: PetMovementPoint,
        currentOrigin: PetMovementPoint,
        petSize: PetMovementSize,
        cursorDistance: Double,
        screenInset: Double,
        screens: [PetMovementScreen]
    ) -> PetMovementCursorRoute? {
        guard pointer.isFinite, currentOrigin.isFinite, petSize.isValid,
              cursorDistance.isFinite, cursorDistance >= 0,
              let targetScreen = screen(
                  containingOrNearestTo: pointer,
                  in: screens
              ),
              let bounds = safeOriginBounds(
                  in: targetScreen.visibleFrame,
                  petSize: petSize,
                  inset: screenInset
              ) else {
            return nil
        }

        let currentCenter = PetMovementPoint(
            x: currentOrigin.x + (petSize.width / 2),
            y: currentOrigin.y + (petSize.height / 2)
        )
        let deltaX = pointer.x - currentCenter.x
        let deltaY = pointer.y - currentCenter.y
        let distance = hypot(deltaX, deltaY)

        let targetCenter: PetMovementPoint
        if distance > 0 {
            targetCenter = PetMovementPoint(
                x: pointer.x - ((deltaX / distance) * cursorDistance),
                y: pointer.y - ((deltaY / distance) * cursorDistance)
            )
        } else {
            targetCenter = pointer
        }

        let targetOrigin = bounds.clamped(
            PetMovementPoint(
                x: targetCenter.x - (petSize.width / 2),
                y: targetCenter.y - (petSize.height / 2)
            )
        )
        guard
            let sourceScreen = screen(
                containingOrNearestTo: currentCenter,
                in: screens
            ),
            sourceScreen.id != targetScreen.id,
            let sourceBounds = safeOriginBounds(
                in: sourceScreen.visibleFrame,
                petSize: petSize,
                inset: 0
            ),
            let targetBounds = safeOriginBounds(
                in: targetScreen.visibleFrame,
                petSize: petSize,
                inset: 0
            )
        else {
            return PetMovementCursorRoute(
                targetOrigin: targetOrigin,
                transition: nil
            )
        }

        let horizontalTransition = closestTransitionCoordinates(
            sourceMinimum: sourceBounds.minX,
            sourceMaximum: sourceBounds.maxX,
            targetMinimum: targetBounds.minX,
            targetMaximum: targetBounds.maxX,
            preferred: currentOrigin.x
        )
        let verticalTransition = closestTransitionCoordinates(
            sourceMinimum: sourceBounds.minY,
            sourceMaximum: sourceBounds.maxY,
            targetMinimum: targetBounds.minY,
            targetMaximum: targetBounds.maxY,
            preferred: currentOrigin.y
        )
        return PetMovementCursorRoute(
            targetOrigin: targetOrigin,
            transition: PetMovementScreenTransition(
                sourceScreenID: sourceScreen.id,
                targetScreenID: targetScreen.id,
                exitOrigin: PetMovementPoint(
                    x: horizontalTransition.source,
                    y: verticalTransition.source
                ),
                entryOrigin: PetMovementPoint(
                    x: horizontalTransition.target,
                    y: verticalTransition.target
                )
            )
        )
    }

    static func freeRoamingTargetOrigin(
        screens: [PetMovementScreen],
        petSize: PetMovementSize,
        screenInset: Double,
        preferredWindow: PetMovementWindow?,
        sample: PetMovementRandomSample
    ) -> PetMovementPoint? {
        let validScreens = screens.filter { $0.visibleFrame.isValid }
        guard !validScreens.isEmpty, petSize.isValid else {
            return nil
        }

        if let preferredWindow,
           let preferredBounds = preferredOriginBounds(
               for: preferredWindow,
               screens: validScreens,
               petSize: petSize,
               screenInset: screenInset
           ) {
            return preferredBounds.point(
                horizontal: sample.horizontal,
                vertical: sample.vertical
            )
        }

        let screenIndex = randomIndex(sample.screen, count: validScreens.count)
        guard let bounds = safeOriginBounds(
            in: validScreens[screenIndex].visibleFrame,
            petSize: petSize,
            inset: screenInset
        ) else {
            return nil
        }
        return bounds.point(
            horizontal: sample.horizontal,
            vertical: sample.vertical
        )
    }

    static func advance(
        from currentOrigin: PetMovementPoint,
        toward targetOrigin: PetMovementPoint,
        speed: Double,
        elapsedSeconds: Double,
        stopRadius: Double
    ) -> PetMovementAdvance {
        guard currentOrigin.isFinite, targetOrigin.isFinite,
              speed.isFinite, speed > 0,
              elapsedSeconds.isFinite, elapsedSeconds > 0,
              stopRadius.isFinite, stopRadius >= 0 else {
            return PetMovementAdvance(
                origin: currentOrigin,
                didMove: false,
                hasArrived: false
            )
        }

        let deltaX = targetOrigin.x - currentOrigin.x
        let deltaY = targetOrigin.y - currentOrigin.y
        let distance = hypot(deltaX, deltaY)
        guard distance > stopRadius else {
            return PetMovementAdvance(
                origin: currentOrigin,
                didMove: false,
                hasArrived: true
            )
        }

        let travelDistance = speed * elapsedSeconds
        guard travelDistance.isFinite, travelDistance > 0 else {
            return PetMovementAdvance(
                origin: currentOrigin,
                didMove: false,
                hasArrived: false
            )
        }

        if travelDistance >= distance {
            return PetMovementAdvance(
                origin: targetOrigin,
                didMove: true,
                hasArrived: true
            )
        }

        let progress = travelDistance / distance
        let nextOrigin = PetMovementPoint(
            x: currentOrigin.x + (deltaX * progress),
            y: currentOrigin.y + (deltaY * progress)
        )
        return PetMovementAdvance(
            origin: nextOrigin,
            didMove: true,
            hasArrived: (distance - travelDistance) <= stopRadius
        )
    }

    private static func screen(
        containingOrNearestTo point: PetMovementPoint,
        in screens: [PetMovementScreen]
    ) -> PetMovementScreen? {
        let validScreens = screens.filter { $0.visibleFrame.isValid }
        if let containingScreen = validScreens.first(where: {
            $0.visibleFrame.contains(point)
        }) {
            return containingScreen
        }
        return validScreens.min { lhs, rhs in
            squaredDistance(from: point, to: lhs.visibleFrame)
                < squaredDistance(from: point, to: rhs.visibleFrame)
        }
    }

    private static func preferredOriginBounds(
        for window: PetMovementWindow,
        screens: [PetMovementScreen],
        petSize: PetMovementSize,
        screenInset: Double
    ) -> PetMovementOriginBounds? {
        guard window.frame.isValid,
              window.frame.size.width >= petSize.width,
              window.frame.size.height >= petSize.height,
              let screen = screens.max(by: { lhs, rhs in
                  intersectionArea(lhs.visibleFrame, window.frame)
                      < intersectionArea(rhs.visibleFrame, window.frame)
              }),
              intersectionArea(screen.visibleFrame, window.frame) > 0,
              let screenBounds = safeOriginBounds(
                  in: screen.visibleFrame,
                  petSize: petSize,
                  inset: screenInset
              ),
              let windowBounds = safeOriginBounds(
                  in: window.frame,
                  petSize: petSize,
                  inset: 0
              ) else {
            return nil
        }
        return screenBounds.intersection(with: windowBounds)
    }

    private static func randomIndex(_ value: Double, count: Int) -> Int {
        guard value.isFinite else {
            return 0
        }
        let normalized = min(max(value, 0), 1)
        return min(Int(normalized * Double(count)), count - 1)
    }

    private static func closestTransitionCoordinates(
        sourceMinimum: Double,
        sourceMaximum: Double,
        targetMinimum: Double,
        targetMaximum: Double,
        preferred: Double
    ) -> (source: Double, target: Double) {
        if sourceMaximum < targetMinimum {
            return (sourceMaximum, targetMinimum)
        }
        if targetMaximum < sourceMinimum {
            return (sourceMinimum, targetMaximum)
        }

        let sharedMinimum = max(sourceMinimum, targetMinimum)
        let sharedMaximum = min(sourceMaximum, targetMaximum)
        let sharedCoordinate = min(
            max(preferred, sharedMinimum),
            sharedMaximum
        )
        return (sharedCoordinate, sharedCoordinate)
    }

    private static func squaredDistance(
        from point: PetMovementPoint,
        to rect: PetMovementRect
    ) -> Double {
        let nearestX = min(max(point.x, rect.minX), rect.maxX)
        let nearestY = min(max(point.y, rect.minY), rect.maxY)
        let deltaX = point.x - nearestX
        let deltaY = point.y - nearestY
        return (deltaX * deltaX) + (deltaY * deltaY)
    }

    private static func intersectionArea(
        _ lhs: PetMovementRect,
        _ rhs: PetMovementRect
    ) -> Double {
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        return width * height
    }
}
