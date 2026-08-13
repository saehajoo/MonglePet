import Darwin
import Foundation

nonisolated struct PetProcessResourceSample: Equatable, Sendable {
    let cumulativeCPUTimeNanoseconds: UInt64
    let residentMemoryBytes: UInt64
}

nonisolated protocol PetProcessResourceSampling: Sendable {
    func sample() -> PetProcessResourceSample?
}

nonisolated struct SystemPetProcessResourceSampler:
    PetProcessResourceSampling,
    Sendable
{
    func sample() -> PetProcessResourceSample? {
        var information = proc_taskinfo()
        let expectedSize = MemoryLayout<proc_taskinfo>.size
        let readSize = withUnsafeMutablePointer(to: &information) {
            pointer in
            proc_pidinfo(
                getpid(),
                PROC_PIDTASKINFO,
                0,
                pointer,
                Int32(expectedSize)
            )
        }
        guard readSize == Int32(expectedSize) else {
            return nil
        }
        return PetProcessResourceSample(
            cumulativeCPUTimeNanoseconds:
                information.pti_total_user
                    + information.pti_total_system,
            residentMemoryBytes: information.pti_resident_size
        )
    }
}

nonisolated enum PetResourceWarningReason: Equatable, Sendable {
    case sustainedCPU
    case highMemory
}

nonisolated struct PetResourceWarning: Equatable, Sendable {
    let reasons: Set<PetResourceWarningReason>
    let cpuPercentage: Double
    let residentMemoryBytes: UInt64
    let activePetCount: Int
    let movingPetCount: Int
}

nonisolated struct PetResourcePressureEvaluator: Sendable {
    static let defaultCPUThreshold = 30.0
    static let defaultMemoryThreshold: UInt64 = 512 * 1_024 * 1_024
    static let defaultRequiredPressureSamples = 2

    private let cpuThreshold: Double
    private let memoryThreshold: UInt64
    private let requiredPressureSamples: Int
    private var previousSample: PetProcessResourceSample?
    private var previousUptime: TimeInterval?
    private var consecutivePressureSamples = 0

    init(
        cpuThreshold: Double = Self.defaultCPUThreshold,
        memoryThreshold: UInt64 = Self.defaultMemoryThreshold,
        requiredPressureSamples: Int = Self.defaultRequiredPressureSamples
    ) {
        self.cpuThreshold = cpuThreshold
        self.memoryThreshold = memoryThreshold
        self.requiredPressureSamples = max(requiredPressureSamples, 1)
    }

    mutating func evaluate(
        sample: PetProcessResourceSample,
        uptime: TimeInterval,
        activePetCount: Int,
        movingPetCount: Int
    ) -> PetResourceWarning? {
        defer {
            previousSample = sample
            previousUptime = uptime
        }
        guard
            activePetCount > 1,
            let previousSample,
            let previousUptime,
            uptime > previousUptime
        else {
            consecutivePressureSamples = 0
            return nil
        }

        let cpuDelta = sample.cumulativeCPUTimeNanoseconds
            >= previousSample.cumulativeCPUTimeNanoseconds
            ? sample.cumulativeCPUTimeNanoseconds
                - previousSample.cumulativeCPUTimeNanoseconds
            : 0
        let elapsedNanoseconds = (uptime - previousUptime)
            * 1_000_000_000
        let cpuPercentage = min(
            max(Double(cpuDelta) / elapsedNanoseconds * 100, 0),
            9_999
        )
        var reasons: Set<PetResourceWarningReason> = []
        if cpuPercentage >= cpuThreshold {
            reasons.insert(.sustainedCPU)
        }
        if sample.residentMemoryBytes >= memoryThreshold {
            reasons.insert(.highMemory)
        }

        if reasons.isEmpty {
            consecutivePressureSamples = 0
            return nil
        }
        consecutivePressureSamples += 1
        guard consecutivePressureSamples >= requiredPressureSamples else {
            return nil
        }
        return PetResourceWarning(
            reasons: reasons,
            cpuPercentage: cpuPercentage,
            residentMemoryBytes: sample.residentMemoryBytes,
            activePetCount: activePetCount,
            movingPetCount: movingPetCount
        )
    }

    mutating func reset() {
        previousSample = nil
        previousUptime = nil
        consecutivePressureSamples = 0
    }
}

@MainActor
final class PetResourceMonitor {
    typealias RuntimeCountsProvider = () -> (
        activePetCount: Int,
        movingPetCount: Int
    )

    private let sampler: any PetProcessResourceSampling
    private let uptimeProvider: () -> TimeInterval
    private let runtimeCountsProvider: RuntimeCountsProvider
    private let onWarningChange: (PetResourceWarning?) -> Void
    private var evaluator: PetResourcePressureEvaluator
    private var timer: Timer?
    private var latestWarning: PetResourceWarning?

    init(
        sampler: any PetProcessResourceSampling =
            SystemPetProcessResourceSampler(),
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        runtimeCountsProvider: @escaping RuntimeCountsProvider,
        onWarningChange: @escaping (PetResourceWarning?) -> Void
    ) {
        self.sampler = sampler
        self.uptimeProvider = uptimeProvider
        self.runtimeCountsProvider = runtimeCountsProvider
        self.onWarningChange = onWarningChange
        evaluator = PetResourcePressureEvaluator()
    }

    func updateActivePetCount(_ activePetCount: Int) {
        if activePetCount > 1 {
            startIfNeeded()
        } else {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        evaluator.reset()
        publish(nil)
    }

    private func startIfNeeded() {
        guard timer == nil else {
            return
        }
        sample()
        let timer = Timer(
            timeInterval: 5,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc
    private func timerDidFire() {
        sample()
    }

    private func sample() {
        guard let sample = sampler.sample() else {
            return
        }
        let counts = runtimeCountsProvider()
        let warning = evaluator.evaluate(
            sample: sample,
            uptime: uptimeProvider(),
            activePetCount: counts.activePetCount,
            movingPetCount: counts.movingPetCount
        )
        publish(warning)
    }

    private func publish(_ warning: PetResourceWarning?) {
        guard warning != latestWarning else {
            return
        }
        latestWarning = warning
        onWarningChange(warning)
    }
}
