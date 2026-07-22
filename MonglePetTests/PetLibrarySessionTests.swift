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
        session.onSelectionChange = { selections.append($0.selection) }

        XCTAssertTrue(session.removeSelectedInstallation())
        XCTAssertEqual(removedIDs, [firstID])
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
        var requestedModes: [PetPackageInstallationMode] = []
        let installed = makeInstalled(id: secondID, name: "가람 사본")
        var packages: [InstalledPetPackage] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            packageInstaller: { _, mode in
                requestedModes.append(mode)
                if mode == .rejectDuplicate {
                    throw PetLibraryError.duplicatePackage(
                        packageID: "test.pet",
                        installationIDs: [self.firstID]
                    )
                }
                packages = [installed]
                return installed
            }
        )

        XCTAssertFalse(session.installPackage(from: sourceURL))
        XCTAssertEqual(session.duplicateInstallRequest?.packageID, "test.pet")
        session.installDuplicateSeparately()
        XCTAssertEqual(requestedModes, [.rejectDuplicate, .installSeparately])
        XCTAssertNil(session.duplicateInstallRequest)

        packages = []
        XCTAssertFalse(session.installPackage(from: sourceURL))
        session.replaceDuplicateInstallation()
        XCTAssertEqual(
            requestedModes,
            [
                .rejectDuplicate,
                .installSeparately,
                .rejectDuplicate,
                .replace(installationID: firstID)
            ]
        )
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
                    loops: false
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

    private var builtInDefinition: PetDefinition {
        BuiltInPet.mongleDefinition(
            atlasPixelSize: PixelSize(width: 192, height: 208)
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
        defaultMotionID: String = "idle"
    ) -> InstalledPetPackage {
        let rootURL = URL(fileURLWithPath: "/tmp/\(id.uuidString)", isDirectory: true)
        let frame = MotionFrame(
            atlasID: "main",
            sourceRect: PixelRect(x: 0, y: 0, width: 10, height: 10),
            duration: .milliseconds(120)
        )
        let definition = PetDefinition(
            id: "test.\(id.uuidString)",
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
                version: "1.0.0",
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
