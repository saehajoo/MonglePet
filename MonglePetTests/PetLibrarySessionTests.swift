import Foundation
import XCTest
@testable import MonglePet

@MainActor
final class PetLibrarySessionTests: XCTestCase {
    private let firstID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111"
    )!
    private let secondID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!

    func testReloadKeepsBuiltInFirstSortsInstalledPetsAndRestoresSelection() {
        let packages = [
            makeInstalled(id: secondID, name: "나비"),
            makeInstalled(id: firstID, name: "가람")
        ]
        let session = makeSession(packages: packages)

        let restoredID = session.reload(preferredInstallationID: secondID)

        XCTAssertEqual(restoredID, secondID)
        XCTAssertEqual(session.selection, .installed(secondID))
        XCTAssertEqual(
            session.items.map(\.metadata.displayName),
            ["몽글이", "가람", "나비"]
        )
    }

    func testReloadFallsBackToBuiltInWhenSavedInstallationIsMissing() {
        let session = makeSession(packages: [makeInstalled(id: firstID, name: "가람")])

        let restoredID = session.reload(preferredInstallationID: secondID)

        XCTAssertNil(restoredID)
        XCTAssertEqual(session.selection, .builtIn)
        XCTAssertTrue(session.selectedItem.isBuiltIn)
    }

    func testSelectionPublishesSelectedItemAndRejectsUnknownInstallation() {
        let installed = makeInstalled(id: firstID, name: "가람")
        let session = makeSession(packages: [installed])
        _ = session.reload(preferredInstallationID: nil)
        var receivedItems: [PetLibraryItem] = []
        session.onSelectionChange = { receivedItems.append($0) }

        XCTAssertTrue(session.select(.installed(firstID)))
        XCTAssertEqual(receivedItems.map(\.selection), [.installed(firstID)])
        XCTAssertFalse(session.select(.installed(secondID)))
        XCTAssertEqual(session.selection, .installed(firstID))
    }

    func testRemovingSelectedInstallationReturnsToBuiltInAndNotifiesRuntime() {
        let installed = makeInstalled(id: firstID, name: "가람")
        var packages = [installed]
        var removedIDs: [UUID] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { installationID in
                removedIDs.append(installationID)
                packages.removeAll { $0.installationID == installationID }
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var selections: [PetLibrarySelection] = []
        var removedInstallationIDs: [UUID] = []
        session.onSelectionChange = { selections.append($0.selection) }
        session.onInstallationRemoved = { removedInstallationIDs.append($0) }

        XCTAssertTrue(session.removeSelectedInstallation())
        XCTAssertEqual(removedIDs, [firstID])
        XCTAssertEqual(removedInstallationIDs, [firstID])
        XCTAssertEqual(selections, [.builtIn])
        XCTAssertEqual(session.items.map(\.selection), [.builtIn])
        XCTAssertEqual(session.selection, .builtIn)
    }

    func testInstallingPackageReloadsSelectsAndNotifiesRuntime() {
        let sourceURL = URL(fileURLWithPath: "/tmp/test.monglepet")
        let installed = makeInstalled(id: firstID, name: "가람")
        var packages: [InstalledPetPackage] = []
        var requestedModes: [PetPackageInstallationMode] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            packageInstaller: { url, mode in
                XCTAssertEqual(url, sourceURL)
                requestedModes.append(mode)
                packages = [installed]
                return installed
            }
        )
        var selections: [PetLibrarySelection] = []
        session.onSelectionChange = { selections.append($0.selection) }

        XCTAssertTrue(session.installPackage(from: sourceURL))
        XCTAssertEqual(requestedModes, [.rejectDuplicate])
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(selections, [.installed(firstID)])
        XCTAssertNil(session.errorMessage)
    }

    func testDuplicateInstallCanRetryAsSeparateCopyOrReplacement() {
        let sourceURL = URL(fileURLWithPath: "/tmp/test.monglepet")
        let thirdID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        var requestedModes: [PetPackageInstallationMode] = []
        let first = makeInstalled(
            id: firstID,
            name: "가람 편집본",
            packageID: "test.pet",
            version: "1.0.0"
        )
        let second = makeInstalled(
            id: secondID,
            name: "가람 읽기 전용",
            packageID: "test.pet",
            version: "1.5.0"
        )
        let incoming = makeInstalled(
            id: thirdID,
            name: "가람 새 버전",
            packageID: "test.pet",
            version: "2.0.0"
        )
        var packages = [first, second]
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            packageInstaller: { _, mode in
                requestedModes.append(mode)
                if mode == .rejectDuplicate {
                    throw PetLibraryError.duplicatePackage(
                        metadata: incoming.package.metadata,
                        installationIDs: [self.firstID]
                            + [self.secondID]
                    )
                }
                let installed: InstalledPetPackage
                switch mode {
                case .rejectDuplicate:
                    XCTFail("중복 거부 모드는 위에서 오류를 발생시켜야 합니다.")
                    installed = incoming
                case .installSeparately:
                    installed = incoming
                case let .replace(installationID):
                    installed = self.makeInstalled(
                        id: installationID,
                        name: incoming.package.metadata.displayName,
                        packageID: incoming.package.metadata.id,
                        version: incoming.package.metadata.version
                    )
                }
                packages = [installed]
                return installed
            },
            editablePackageProvider: { $0.installationID == self.firstID }
        )
        _ = session.reload(preferredInstallationID: secondID)

        XCTAssertFalse(session.installPackage(from: sourceURL))
        guard let duplicateRequest = session.duplicateInstallRequest else {
            return XCTFail("중복 설치 선택 요청이 필요합니다.")
        }
        XCTAssertEqual(duplicateRequest.packageID, "test.pet")
        XCTAssertEqual(duplicateRequest.incomingMetadata.version, "2.0.0")
        XCTAssertEqual(
            duplicateRequest.candidates.map(\.installationID),
            [secondID, firstID]
        )
        XCTAssertEqual(
            duplicateRequest.preferredReplacementInstallationID,
            secondID
        )
        XCTAssertEqual(
            duplicateRequest.candidates.map(\.isEditable),
            [false, true]
        )
        session.installDuplicateSeparately()
        XCTAssertEqual(requestedModes, [.rejectDuplicate, .installSeparately])
        XCTAssertNil(session.duplicateInstallRequest)

        packages = [first, second]
        _ = session.reload(preferredInstallationID: secondID)
        XCTAssertFalse(session.installPackage(from: sourceURL))
        session.replaceDuplicateInstallation(firstID)
        XCTAssertEqual(
            requestedModes,
            [
                .rejectDuplicate,
                .installSeparately,
                .rejectDuplicate,
                .replace(installationID: firstID)
            ]
        )
        XCTAssertEqual(session.selection, .installed(firstID))
    }

    func testCreatingUserPetReloadsSelectsAndMarksEditableItem() {
        let installed = makeInstalled(id: firstID, name: "사용자 펫")
        var packages: [InstalledPetPackage] = []
        let request = UserPetCreationRequest(
            displayName: "사용자 펫",
            animationName: "기본",
            frameDurationMilliseconds: 120,
            loops: true,
            sourceURLs: [URL(fileURLWithPath: "/tmp/frame.png")]
        )
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { $0.installationID == self.firstID },
            userPetCreator: { receivedRequest in
                XCTAssertEqual(receivedRequest, request)
                packages = [installed]
                return installed
            }
        )
        var selections: [PetLibrarySelection] = []
        session.onSelectionChange = { selections.append($0.selection) }

        XCTAssertTrue(session.createUserPet(request))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertTrue(session.selectedItem.isEditable)
        XCTAssertEqual(selections, [.installed(firstID)])
    }

    func testCreatingEditableCopyReloadsSelectsAndNotifiesRuntime() {
        let original = makeInstalled(id: firstID, name: "가져온 펫")
        let copy = makeInstalled(id: secondID, name: "편집용 펫")
        var packages = [original]
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { $0.installationID == self.secondID },
            editableCopyCreator: { receivedPackage, displayName in
                XCTAssertEqual(receivedPackage, original)
                XCTAssertEqual(displayName, "편집용 펫")
                packages.append(copy)
                return copy
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var selections: [PetLibrarySelection] = []
        session.onSelectionChange = { selections.append($0.selection) }

        XCTAssertTrue(
            session.createEditableCopyOfSelectedPet(displayName: "편집용 펫")
        )
        XCTAssertEqual(session.selection, .installed(secondID))
        XCTAssertTrue(session.selectedItem.isEditable)
        XCTAssertEqual(session.items.map(\.selection), [
            .builtIn,
            .installed(firstID),
            .installed(secondID)
        ])
        XCTAssertEqual(selections, [.installed(secondID)])
        XCTAssertNil(session.errorMessage)
    }

    func testCreatingEditableCopyFromEditablePetIsRejected() {
        let installed = makeInstalled(id: firstID, name: "사용자 펫")
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [installed] },
            installationRemover: { _ in },
            editablePackageProvider: { _ in true }
        )
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertFalse(
            session.createEditableCopyOfSelectedPet(displayName: "사본")
        )
        XCTAssertEqual(
            session.errorMessage,
            UserPetEditingError.petIsAlreadyEditable.localizedDescription
        )
        XCTAssertEqual(session.selection, .installed(firstID))
    }

    func testUpdatingSelectedPetDetailsReloadsSameInstallationAndNotifiesRuntime() {
        let original = makeInstalled(id: firstID, name: "처음 이름")
        let updated = makeInstalled(id: firstID, name: "새 이름")
        var packages = [original]
        let request = UserPetDetailsRequest(
            displayName: "새 이름",
            version: "2.0.0",
            author: "새 제작자",
            license: "Test",
            description: "새 설명",
            defaultMotionID: "idle"
        )
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { $0.installationID == self.firstID },
            detailsUpdater: { receivedRequest, receivedPackage in
                XCTAssertEqual(receivedRequest, request)
                XCTAssertEqual(receivedPackage, original)
                packages = [updated]
                return updated
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var selections: [PetLibraryItem] = []
        session.onSelectionChange = { selections.append($0) }

        XCTAssertTrue(session.updateSelectedPetDetails(request))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(session.selectedItem.metadata.displayName, "새 이름")
        XCTAssertEqual(selections.map(\.metadata.displayName), ["새 이름"])
        XCTAssertNil(session.errorMessage)
    }

    func testUpdatingReadOnlyPetDetailsIsRejected() {
        let installed = makeInstalled(id: firstID, name: "가져온 펫")
        let session = makeSession(packages: [installed])
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertFalse(
            session.updateSelectedPetDetails(
                UserPetDetailsRequest(
                    displayName: "변경",
                    version: "2.0.0",
                    author: "제작자",
                    license: "Test",
                    description: nil,
                    defaultMotionID: "idle"
                )
            )
        )
        XCTAssertEqual(session.selectedItem.metadata.displayName, "가져온 펫")
        XCTAssertEqual(
            session.errorMessage,
            UserPetEditingError.importedPackageIsReadOnly.localizedDescription
        )
    }

    func testAnimationChangesReloadAndPublishReferenceUpdates() {
        let original = makeInstalled(
            id: firstID,
            name: "사용자 펫",
            motionIDs: ["idle", "wave"]
        )
        let renamed = makeInstalled(
            id: firstID,
            name: "사용자 펫",
            motionIDs: ["idle", "hello"]
        )
        let removed = makeInstalled(
            id: firstID,
            name: "사용자 펫",
            motionIDs: ["idle"]
        )
        var packages = [original]
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { _ in true },
            animationUpdater: { request, installedPackage in
                XCTAssertEqual(request.animationID, "wave")
                XCTAssertEqual(request.animationName, "  hello  ")
                XCTAssertEqual(installedPackage, original)
                packages = [renamed]
                return renamed
            },
            animationRemover: { animationID, installedPackage in
                XCTAssertEqual(animationID, "hello")
                XCTAssertEqual(installedPackage, renamed)
                packages = [removed]
                return removed
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var changes: [PetAnimationReferenceChange] = []
        session.onAnimationReferenceChange = { changes.append($0) }

        XCTAssertTrue(
            session.updateSelectedPetAnimation(
                UserPetAnimationDetailsRequest(
                    animationID: "wave",
                    animationName: "  hello  ",
                    loops: false,
                    frames: [
                        UserPetAnimationFrameRequest(
                            source: .existing(index: 0),
                            durationMilliseconds: 120
                        )
                    ]
                )
            )
        )
        XCTAssertEqual(session.selectedItem.definition.motions.map(\.id), ["idle", "hello"])
        XCTAssertTrue(session.removeSelectedPetAnimation(id: "hello"))
        XCTAssertEqual(session.selectedItem.definition.motions.map(\.id), ["idle"])
        XCTAssertEqual(
            changes,
            [
                .renamed(from: "wave", to: "hello"),
                .removed("hello")
            ]
        )
    }

    func testBuiltInPetCannotStartSharingReview() {
        var reviewCallCount = 0
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in },
            packageShareReviewer: { _, _ in
                reviewCallCount += 1
                throw PetLibraryError.fileOperationFailed
            }
        )

        XCTAssertNil(session.reviewSelectedPetForSharing())
        XCTAssertEqual(reviewCallCount, 0)
        XCTAssertNil(session.errorMessage)
    }

    func testSharingReviewUsesSelectedInstalledPet() {
        let installed = makeInstalled(id: firstID, name: "공유 펫")
        let behaviorProfile = makeBehaviorProfile(installationID: firstID)
        let expectedReview = PetPackageSharingPolicy.review(
            metadata: installed.package.metadata
        )
        var reviewedPackages: [InstalledPetPackage] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [installed] },
            installationRemover: { _ in },
            packageShareReviewer: { receivedPackage, receivedProfile in
                reviewedPackages.append(receivedPackage)
                XCTAssertEqual(receivedProfile, behaviorProfile)
                return expectedReview
            }
        )
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertEqual(
            session.reviewSelectedPetForSharing(
                behaviorProfile: behaviorProfile
            ),
            expectedReview
        )
        XCTAssertEqual(reviewedPackages, [installed])
        XCTAssertNil(session.errorMessage)
    }

    func testExportingSelectedPetForwardsConfirmedReviewAndTracksBusyState() {
        let installed = makeInstalled(id: firstID, name: "공유 펫")
        let review = PetPackageSharingPolicy.review(
            metadata: installed.package.metadata
        )
        let destinationURL = URL(fileURLWithPath: "/tmp/shared.monglepet")
        let options = PetPackageShareOptions(
            includesRecommendedProfile: true,
            includesApplicationRules: true
        )
        var receivedConfirmation = false
        var session: PetLibrarySession!
        session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [installed] },
            installationRemover: { _ in },
            packageShareExporter: {
                receivedPackage,
                receivedReview,
                receivedOptions,
                isConfirmed,
                receivedDestinationURL in
                XCTAssertTrue(session.isExporting)
                XCTAssertEqual(receivedPackage, installed)
                XCTAssertEqual(receivedReview, review)
                XCTAssertEqual(receivedOptions, options)
                XCTAssertEqual(receivedDestinationURL, destinationURL)
                receivedConfirmation = isConfirmed
                return receivedDestinationURL
            }
        )
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertTrue(
            session.exportSelectedPet(
                reviewed: review,
                options: options,
                isConfirmed: true,
                to: destinationURL
            )
        )
        XCTAssertTrue(receivedConfirmation)
        XCTAssertFalse(session.isExporting)
        XCTAssertNil(session.errorMessage)
    }

    func testExportingSelectedPetPublishesSharingError() {
        let installed = makeInstalled(id: firstID, name: "공유 펫")
        let review = PetPackageSharingPolicy.review(
            metadata: installed.package.metadata
        )
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [installed] },
            installationRemover: { _ in },
            packageShareExporter: { _, _, _, _, _ in
                throw PetPackageSharingError.confirmationRequired
            }
        )
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertFalse(
            session.exportSelectedPet(
                reviewed: review,
                isConfirmed: false,
                to: URL(fileURLWithPath: "/tmp/shared.monglepet")
            )
        )
        XCTAssertFalse(session.isExporting)
        XCTAssertEqual(
            session.errorMessage,
            PetPackageSharingError.confirmationRequired.localizedDescription
        )
    }

    private var builtInDefinition: PetDefinition {
        BuiltInPet.mongleDefinition(
            atlasPixelSize: PixelSize(width: 192, height: 208)
        )
    }

    private func makeBehaviorProfile(
        installationID: UUID
    ) -> BehaviorProfile {
        BehaviorProfile(
            petKey: .installed(installationID),
            mode: .manual,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [
                        BehaviorStep(motionID: "idle", repeatCount: 1)
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: .default,
            pettingMotionID: nil
        )
    }

    private func makeSession(packages: [InstalledPetPackage]) -> PetLibrarySession {
        PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in }
        )
    }

    private func makeInstalled(
        id: UUID,
        name: String,
        motionIDs: [String] = ["idle"],
        defaultMotionID: String = "idle",
        packageID: String? = nil,
        version: String = "1.0.0"
    ) -> InstalledPetPackage {
        let rootURL = URL(fileURLWithPath: "/tmp/\(id.uuidString)", isDirectory: true)
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
            duration: .milliseconds(120)
        )
        let definition = PetDefinition(
            id: packageID ?? "test.\(id.uuidString)",
            displayName: name,
            defaultMotionID: defaultMotionID,
            motions: motionIDs.map {
                PetMotion(id: $0, loops: true, frames: [frame])
            }
        )
        let package = LoadedPetPackage(
            packageRootURL: rootURL,
            metadata: PetPackageMetadata(
                id: definition.id,
                displayName: name,
                version: version,
                author: "Tester",
                license: "Test",
                description: nil
            ),
            previewURL: rootURL.appendingPathComponent("preview.png"),
            atlases: [
                PetAtlasResource(
                    id: "main",
                    fileURL: rootURL.appendingPathComponent("atlas.png"),
                    pixelSize: PixelSize(width: 10, height: 10),
                    format: .png
                )
            ],
            definition: definition
        )
        return InstalledPetPackage(
            installationID: id,
            rootURL: rootURL,
            package: package
        )
    }
}
