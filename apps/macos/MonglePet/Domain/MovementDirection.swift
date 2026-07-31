import Foundation

nonisolated enum MovementDirection: String, CaseIterable, Hashable, Sendable {
    case left
    case right
    case up
    case down
    case upLeft
    case upRight
    case downLeft
    case downRight

    static let cardinalCases: [MovementDirection] = [
        .left,
        .right,
        .up,
        .down
    ]

    static let diagonalCases: [MovementDirection] = [
        .upLeft,
        .upRight,
        .downLeft,
        .downRight
    ]

    var isDiagonal: Bool {
        switch self {
        case .left, .right, .up, .down:
            false
        case .upLeft, .upRight, .downLeft, .downRight:
            true
        }
    }
}

nonisolated struct DirectionalMotionIDs: Equatable, Sendable {
    let left: String?
    let right: String?
    let up: String?
    let down: String?
    let upLeft: String?
    let upRight: String?
    let downLeft: String?
    let downRight: String?

    init(
        left: String? = nil,
        right: String? = nil,
        up: String? = nil,
        down: String? = nil,
        upLeft: String? = nil,
        upRight: String? = nil,
        downLeft: String? = nil,
        downRight: String? = nil
    ) {
        self.left = left
        self.right = right
        self.up = up
        self.down = down
        self.upLeft = upLeft
        self.upRight = upRight
        self.downLeft = downLeft
        self.downRight = downRight
    }

    static let empty = DirectionalMotionIDs()

    subscript(direction: MovementDirection) -> String? {
        switch direction {
        case .left:
            left
        case .right:
            right
        case .up:
            up
        case .down:
            down
        case .upLeft:
            upLeft
        case .upRight:
            upRight
        case .downLeft:
            downLeft
        case .downRight:
            downRight
        }
    }

    func replacing(
        _ direction: MovementDirection,
        with motionID: String?
    ) -> DirectionalMotionIDs {
        DirectionalMotionIDs(
            left: direction == .left ? motionID : left,
            right: direction == .right ? motionID : right,
            up: direction == .up ? motionID : up,
            down: direction == .down ? motionID : down,
            upLeft: direction == .upLeft ? motionID : upLeft,
            upRight: direction == .upRight ? motionID : upRight,
            downLeft: direction == .downLeft ? motionID : downLeft,
            downRight: direction == .downRight ? motionID : downRight
        )
    }

    var allMotionIDs: [String?] {
        [
            left,
            right,
            up,
            down,
            upLeft,
            upRight,
            downLeft,
            downRight
        ]
    }
}

nonisolated struct MovementAnimationSettings: Equatable, Sendable {
    private static let minimumAutomaticAlignment = 0.05

    let fallbackMotionID: String?
    let usesDirectionalMotions: Bool
    let usesDiagonalMotions: Bool
    let directionMotionIDs: DirectionalMotionIDs

    init(
        fallbackMotionID: String? = nil,
        usesDirectionalMotions: Bool = false,
        usesDiagonalMotions: Bool = false,
        directionMotionIDs: DirectionalMotionIDs = .empty
    ) {
        self.fallbackMotionID = fallbackMotionID
        self.usesDirectionalMotions = usesDirectionalMotions
        self.usesDiagonalMotions = usesDiagonalMotions
        self.directionMotionIDs = directionMotionIDs
    }

    static let `default` = MovementAnimationSettings()

    static func single(_ motionID: String?) -> MovementAnimationSettings {
        MovementAnimationSettings(fallbackMotionID: motionID)
    }

    var isValid: Bool {
        (!usesDiagonalMotions || usesDirectionalMotions)
            && Self.isValidOptionalMotionID(fallbackMotionID)
            && directionMotionIDs.allMotionIDs.allSatisfy(
                Self.isValidOptionalMotionID
            )
    }

    func resolvedMotionID(
        for direction: MovementDirection?,
        deltaX: Double,
        deltaY: Double
    ) -> String? {
        guard usesDirectionalMotions, let direction else {
            return fallbackMotionID
        }
        if let exact = directionMotionIDs[direction] {
            return exact
        }
        if let automaticMotionID = closestUsableMotionID(
            deltaX: deltaX,
            deltaY: deltaY
        ) {
            return automaticMotionID
        }
        return fallbackMotionID
    }

    private func closestUsableMotionID(
        deltaX: Double,
        deltaY: Double
    ) -> String? {
        let magnitude = hypot(deltaX, deltaY)
        guard
            deltaX.isFinite,
            deltaY.isFinite,
            magnitude > MovementDirectionClassifier.minimumVectorLength
        else {
            return nil
        }

        let directions = usesDiagonalMotions
            ? MovementDirection.cardinalCases
                + MovementDirection.diagonalCases
            : MovementDirection.cardinalCases
        var bestMotionID: String?
        var bestAlignment = Self.minimumAutomaticAlignment

        for candidate in directions {
            guard
                let motionID = directionMotionIDs[candidate],
                isCompatible(
                    candidate,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            else {
                continue
            }
            let vector = unitVector(for: candidate)
            let alignment = (
                deltaX * vector.x
                    + deltaY * vector.y
            ) / magnitude
            if alignment > bestAlignment {
                bestAlignment = alignment
                bestMotionID = motionID
            }
        }

        return bestMotionID
    }

    private func isCompatible(
        _ direction: MovementDirection,
        deltaX: Double,
        deltaY: Double
    ) -> Bool {
        let vector = unitVector(for: direction)
        return !(vector.x != 0 && deltaX * vector.x < 0)
            && !(vector.y != 0 && deltaY * vector.y < 0)
    }

    private func unitVector(
        for direction: MovementDirection
    ) -> (x: Double, y: Double) {
        let diagonal = 1 / sqrt(2.0)
        return switch direction {
        case .left:
            (-1, 0)
        case .right:
            (1, 0)
        case .up:
            (0, 1)
        case .down:
            (0, -1)
        case .upLeft:
            (-diagonal, diagonal)
        case .upRight:
            (diagonal, diagonal)
        case .downLeft:
            (-diagonal, -diagonal)
        case .downRight:
            (diagonal, -diagonal)
        }
    }

    private static func isValidOptionalMotionID(_ motionID: String?) -> Bool {
        guard let motionID else {
            return true
        }
        let trimmed = motionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == motionID
    }
}

nonisolated struct MovementDirectionClassifier: Equatable, Sendable {
    static let defaultHysteresisDegrees = 8.0
    static let minimumVectorLength = 0.000_1

    private(set) var currentDirection: MovementDirection?
    let hysteresisDegrees: Double

    init(
        currentDirection: MovementDirection? = nil,
        hysteresisDegrees: Double = defaultHysteresisDegrees
    ) {
        self.currentDirection = currentDirection
        self.hysteresisDegrees = max(hysteresisDegrees, 0)
    }

    mutating func classify(
        deltaX: Double,
        deltaY: Double,
        usesDiagonals: Bool
    ) -> MovementDirection? {
        guard
            deltaX.isFinite,
            deltaY.isFinite,
            hypot(deltaX, deltaY) > Self.minimumVectorLength
        else {
            return currentDirection
        }

        let angle = normalizedDegrees(
            atan2(deltaY, deltaX) * 180 / .pi
        )
        let allowedDirections = usesDiagonals
            ? MovementDirection.allCases
            : MovementDirection.cardinalCases
        let halfSector = usesDiagonals ? 22.5 : 45.0

        if let currentDirection,
           allowedDirections.contains(currentDirection),
           angularDistance(
               from: angle,
               to: centerAngle(for: currentDirection)
           ) <= halfSector + hysteresisDegrees {
            return currentDirection
        }

        let resolved = allowedDirections.min { lhs, rhs in
            angularDistance(from: angle, to: centerAngle(for: lhs))
                < angularDistance(from: angle, to: centerAngle(for: rhs))
        }
        currentDirection = resolved
        return resolved
    }

    mutating func reset() {
        currentDirection = nil
    }

    private func centerAngle(for direction: MovementDirection) -> Double {
        switch direction {
        case .right:
            0
        case .upRight:
            45
        case .up:
            90
        case .upLeft:
            135
        case .left:
            180
        case .downLeft:
            225
        case .down:
            270
        case .downRight:
            315
        }
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func angularDistance(from lhs: Double, to rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
