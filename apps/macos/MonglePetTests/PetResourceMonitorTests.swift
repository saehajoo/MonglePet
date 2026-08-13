import XCTest
@testable import MonglePet

final class PetResourceMonitorTests: XCTestCase {
    func testEvaluatorIgnoresSinglePetPressure() {
        var evaluator = PetResourcePressureEvaluator(
            cpuThreshold: 10,
            memoryThreshold: 100,
            requiredPressureSamples: 1
        )

        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0, memoryBytes: 200),
                uptime: 1,
                activePetCount: 1,
                movingPetCount: 1
            )
        )
        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 1, memoryBytes: 200),
                uptime: 2,
                activePetCount: 1,
                movingPetCount: 1
            )
        )
    }

    func testEvaluatorRequiresSustainedCPUPressure() throws {
        var evaluator = PetResourcePressureEvaluator(
            cpuThreshold: 30,
            memoryThreshold: .max,
            requiredPressureSamples: 2
        )

        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0),
                uptime: 1,
                activePetCount: 3,
                movingPetCount: 2
            )
        )
        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0.4),
                uptime: 2,
                activePetCount: 3,
                movingPetCount: 2
            )
        )
        let warning = try XCTUnwrap(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0.8),
                uptime: 3,
                activePetCount: 3,
                movingPetCount: 2
            )
        )

        XCTAssertEqual(warning.reasons, [.sustainedCPU])
        XCTAssertEqual(warning.cpuPercentage, 40, accuracy: 0.001)
        XCTAssertEqual(warning.activePetCount, 3)
        XCTAssertEqual(warning.movingPetCount, 2)
    }

    func testEvaluatorReportsHighMemoryAndClearsAfterRecovery() throws {
        var evaluator = PetResourcePressureEvaluator(
            cpuThreshold: .greatestFiniteMagnitude,
            memoryThreshold: 500,
            requiredPressureSamples: 2
        )

        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0, memoryBytes: 600),
                uptime: 1,
                activePetCount: 2,
                movingPetCount: 0
            )
        )
        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0, memoryBytes: 600),
                uptime: 2,
                activePetCount: 2,
                movingPetCount: 0
            )
        )
        let warning = try XCTUnwrap(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0, memoryBytes: 600),
                uptime: 3,
                activePetCount: 2,
                movingPetCount: 0
            )
        )
        XCTAssertEqual(warning.reasons, [.highMemory])

        XCTAssertNil(
            evaluator.evaluate(
                sample: sample(cpuSeconds: 0, memoryBytes: 100),
                uptime: 4,
                activePetCount: 2,
                movingPetCount: 0
            )
        )
    }

    private func sample(
        cpuSeconds: Double,
        memoryBytes: UInt64 = 0
    ) -> PetProcessResourceSample {
        PetProcessResourceSample(
            cumulativeCPUTimeNanoseconds: UInt64(
                cpuSeconds * 1_000_000_000
            ),
            residentMemoryBytes: memoryBytes
        )
    }
}
