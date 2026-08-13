import Foundation
import XCTest
@testable import MonglePet

@MainActor
final class PetStartupRecoveryTests: XCTestCase {
    func testStoreRoundTripsRestoreAndSafeModeRecords() throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.directoryURL) }
        let store = PetStartupRecoveryStore(journalURL: environment.journalURL)
        let instanceID = UUID()

        try store.markRestoring(instanceID)

        XCTAssertEqual(
            store.pendingRecord(),
            PetStartupRecoveryRecord(
                restoringInstanceID: instanceID,
                reason: .interruptedRestore
            )
        )

        try store.markSafeMode(instanceID)

        XCTAssertEqual(
            store.pendingRecord(),
            PetStartupRecoveryRecord(
                restoringInstanceID: instanceID,
                reason: .userRequestedSafeMode
            )
        )

        try store.clear()
        XCTAssertNil(store.pendingRecord())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.journalURL.path
            )
        )
    }

    func testStoreRejectsMalformedAndOversizedJournals() throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.directoryURL) }
        let store = PetStartupRecoveryStore(journalURL: environment.journalURL)

        try Data("not-json".utf8).write(to: environment.journalURL)
        XCTAssertNil(store.pendingRecord())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.journalURL.path
            )
        )

        try Data(
            repeating: 0,
            count: PetStartupRecoveryStore.maximumFileSize + 1
        ).write(to: environment.journalURL)
        XCTAssertNil(store.pendingRecord())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: environment.journalURL.path
            )
        )
    }

    func testRestorerMarksEachInstanceBeforeRestoreAndClearsAfterward() throws {
        let store = FakePetStartupRecoveryStore()
        let restorer = PetStartupRestorer(recoveryStore: store)
        let instanceIDs = [UUID(), UUID(), UUID()]
        var restoredIDs: [UUID] = []

        try restorer.restore(instanceIDs: instanceIDs) { instanceID in
            XCTAssertEqual(store.record?.restoringInstanceID, instanceID)
            XCTAssertEqual(store.record?.reason, .interruptedRestore)
            restoredIDs.append(instanceID)
        }

        XCTAssertEqual(restoredIDs, instanceIDs)
        XCTAssertEqual(store.markedRestoringIDs, instanceIDs)
        XCTAssertEqual(store.clearCallCount, instanceIDs.count)
        XCTAssertNil(store.pendingRecord())
    }

    func testRestorerLeavesCurrentInstanceMarkedWhenRestoreThrows() {
        let store = FakePetStartupRecoveryStore()
        let restorer = PetStartupRestorer(recoveryStore: store)
        let instanceID = UUID()

        XCTAssertThrowsError(
            try restorer.restore(instanceIDs: [instanceID]) { _ in
                throw TestFailure.expected
            }
        )

        XCTAssertEqual(store.record?.restoringInstanceID, instanceID)
        XCTAssertEqual(store.record?.reason, .interruptedRestore)
        XCTAssertEqual(store.clearCallCount, 0)
    }

    func testCoordinatorStartsWithoutPetsAfterInterruptedRestoreAndLetsUserRestore() throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.directoryURL) }
        let settingsStore = AppSettingsStore(
            settingsURL: environment.directoryURL
                .appendingPathComponent("settings.json")
        )
        try settingsStore.save(.default)
        let selectedID = AppSettings.default.selectedPetInstanceID
        let recoveryStore = FakePetStartupRecoveryStore()
        try recoveryStore.markRestoring(selectedID)
        let runtimeControlSession = PetRuntimeControlSession()
        let coordinator = AppCoordinator(
            settingsStore: settingsStore,
            petLibraryStore: PetLibraryStore(
                libraryRootURL: environment.directoryURL
                    .appendingPathComponent("Library", isDirectory: true)
            ),
            activityMonitor: StartupRecoveryActivityMonitor(),
            runtimeControlSession: runtimeControlSession,
            startupRecoveryStore: recoveryStore
        )

        coordinator.start()
        defer { coordinator.stop() }

        XCTAssertTrue(coordinator.activePetInstanceIDs.isEmpty)
        XCTAssertEqual(
            runtimeControlSession.pendingRecoveryInstanceID,
            selectedID
        )
        XCTAssertTrue(runtimeControlSession.restoredInstanceIDs.isEmpty)

        runtimeControlSession.restoreAll()

        XCTAssertEqual(coordinator.activePetInstanceIDs, [selectedID])
        XCTAssertNil(runtimeControlSession.pendingRecoveryInstanceID)
        XCTAssertEqual(runtimeControlSession.restoredInstanceIDs, [selectedID])
        XCTAssertNil(recoveryStore.pendingRecord())
    }

    private func makeEnvironment() throws -> (
        directoryURL: URL,
        journalURL: URL
    ) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return (
            directoryURL,
            directoryURL.appendingPathComponent("startup-recovery.json")
        )
    }
}

private enum TestFailure: Error {
    case expected
}

@MainActor
private final class StartupRecoveryActivityMonitor:
    ActivitySnapshotMonitoring
{
    private(set) var latestSnapshot: ActivitySnapshot?
    private(set) var isRunning = false

    func start(onSnapshot: @escaping (ActivitySnapshot) -> Void) {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}

private final class FakePetStartupRecoveryStore:
    PetStartupRecoveryStoring,
    @unchecked Sendable
{
    private(set) var record: PetStartupRecoveryRecord?
    private(set) var markedRestoringIDs: [UUID] = []
    private(set) var clearCallCount = 0

    func pendingRecord() -> PetStartupRecoveryRecord? {
        record
    }

    func markRestoring(_ instanceID: UUID) throws {
        markedRestoringIDs.append(instanceID)
        record = PetStartupRecoveryRecord(
            restoringInstanceID: instanceID,
            reason: .interruptedRestore
        )
    }

    func markSafeMode(_ instanceID: UUID) throws {
        record = PetStartupRecoveryRecord(
            restoringInstanceID: instanceID,
            reason: .userRequestedSafeMode
        )
    }

    func clear() throws {
        clearCallCount += 1
        record = nil
    }
}
