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

    func testBuiltInMongleUsesPublishedMetadataAndMotions() {
        let session = makeSession(packages: [])

        XCTAssertEqual(session.selectedItem.metadata.id, BuiltInPet.id)
        XCTAssertEqual(session.selectedItem.metadata.displayName, "몽글이")
        XCTAssertEqual(session.selectedItem.metadata.version, "1.0.3")
        XCTAssertEqual(session.selectedItem.metadata.author, "운영자")
        XCTAssertEqual(
            session.selectedItem.metadata.description,
            "MonglePet에서 기본으로 제공되는 몽글펫입니다."
        )
        XCTAssertEqual(session.selectedItem.definition.motions.count, 13)
        XCTAssertEqual(
            session.selectedItem.definition.defaultMotionID,
            "기본"
        )
    }

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

    func testItemLookupResolvesBuiltInAndInstalledPetsWithoutChangingSelection() {
        let session = makeSession(
            packages: [makeInstalled(id: firstID, name: "가람")]
        )
        _ = session.reload(preferredInstallationID: nil)

        XCTAssertEqual(session.item(for: .builtIn)?.selection, .builtIn)
        XCTAssertEqual(
            session.item(for: .installed(firstID))?.selection,
            .installed(firstID)
        )
        XCTAssertNil(session.item(for: .installed(secondID)))
        XCTAssertEqual(session.selection, .builtIn)
    }

    func testBrowseSelectionDoesNotPublishInstalledContentChange() {
        let installed = makeInstalled(id: firstID, name: "가람")
        let session = makeSession(packages: [installed])
        _ = session.reload(preferredInstallationID: nil)
        var receivedItems: [PetLibraryItem] = []
        session.onInstalledContentChange = { receivedItems.append($0) }

        XCTAssertTrue(session.select(.installed(firstID)))
        XCTAssertTrue(receivedItems.isEmpty)
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
        session.onInstalledContentChange = { selections.append($0.selection) }
        session.onInstallationRemoved = { removedInstallationIDs.append($0) }

        XCTAssertTrue(session.removeSelectedInstallation())
        XCTAssertEqual(removedIDs, [firstID])
        XCTAssertEqual(removedInstallationIDs, [firstID])
        XCTAssertTrue(selections.isEmpty)
        XCTAssertEqual(session.items.map(\.selection), [.builtIn])
        XCTAssertEqual(session.selection, .builtIn)
    }

    func testInstallingPackageCreatesSeparateContentAndRequestsActivePet() {
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
        var purposes: [NewUserPetInstallationPurpose] = []
        session.onInstalledContentChange = { selections.append($0.selection) }
        session.onNewUserPetInstallation = { _, purpose in
            purposes.append(purpose)
        }

        XCTAssertTrue(session.installPackage(from: sourceURL))
        XCTAssertEqual(requestedModes, [.installSeparately])
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(selections, [.installed(firstID)])
        XCTAssertEqual(
            purposes,
            [.imported(recommendedProfile: nil)]
        )
        XCTAssertNil(session.errorMessage)
    }

    func testReviewedImportAutomaticallyAppliesCreatorSettings() {
        let sourceURL = URL(fileURLWithPath: "/tmp/recommended.monglepet")
        let installed = makeInstalled(id: firstID, name: "추천 펫")
        let profile = makeRecommendedProfile()
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: installed,
            profile: profile
        )
        var packages: [InstalledPetPackage] = []
        var selectedIDs: [UUID?] = []
        var purposes: [NewUserPetInstallationPurpose] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            packageImportReviewer: { receivedURL in
                XCTAssertEqual(receivedURL, sourceURL)
                return review
            },
            reviewedPackageInstaller: {
                receivedURL,
                mode,
                expectedReview in
                XCTAssertEqual(receivedURL, sourceURL)
                XCTAssertEqual(mode, .installSeparately)
                XCTAssertEqual(expectedReview, review)
                packages = [installed]
                return PetPackageInstallationResult(
                    installedPackage: installed,
                    importReview: review
                )
            }
        )
        session.onInstalledContentChange = {
            selectedIDs.append($0.selection.installationID)
        }
        session.onNewUserPetInstallation = { _, purpose in
            purposes.append(purpose)
        }
        XCTAssertEqual(session.reviewPackageForImport(from: sourceURL), review)
        XCTAssertTrue(session.installReviewedPackage(review))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(selectedIDs, [firstID])
        XCTAssertEqual(
            purposes,
            [.imported(recommendedProfile: profile)]
        )
        XCTAssertNil(session.errorMessage)
        XCTAssertNil(session.importNoticeMessage)
    }

    func testCancellingAfterReviewLeavesExistingLibraryAndSettingsUntouched() {
        let sourceURL = URL(fileURLWithPath: "/tmp/cancelled.monglepet")
        let existing = makeInstalled(id: firstID, name: "기존 펫")
        let incoming = makeInstalled(id: secondID, name: "취소할 펫")
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: incoming,
            profile: makeRecommendedProfile()
        )
        let packages = [existing]
        var installedContentChanges: [PetLibrarySelection] = []
        var installationPurposes: [NewUserPetInstallationPurpose] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in XCTFail("취소 시 설치를 제거하면 안 됩니다.") },
            packageImportReviewer: { _ in review },
            reviewedPackageInstaller: { _, _, _ in
                XCTFail("취소 시 설치를 시작하면 안 됩니다.")
                throw PetLibraryError.fileOperationFailed
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        session.onInstalledContentChange = {
            installedContentChanges.append($0.selection)
        }
        session.onNewUserPetInstallation = { _, purpose in
            installationPurposes.append(purpose)
        }

        XCTAssertEqual(session.reviewPackageForImport(from: sourceURL), review)

        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(session.items.map(\.selection), [.builtIn, .installed(firstID)])
        XCTAssertTrue(installedContentChanges.isEmpty)
        XCTAssertTrue(installationPurposes.isEmpty)
        XCTAssertNil(session.errorMessage)
    }

    func testReviewedImportCanInstallPetWithoutRecommendedProfile() {
        let sourceURL = URL(fileURLWithPath: "/tmp/pet-only.monglepet")
        let installed = makeInstalled(id: firstID, name: "기본 설치 펫")
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: installed,
            profile: nil
        )
        var packages: [InstalledPetPackage] = []
        var purposes: [NewUserPetInstallationPurpose] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            reviewedPackageInstaller: { _, _, _ in
                packages = [installed]
                return PetPackageInstallationResult(
                    installedPackage: installed,
                    importReview: review
                )
            }
        )
        session.onNewUserPetInstallation = { _, purpose in
            purposes.append(purpose)
        }
        XCTAssertTrue(session.installReviewedPackage(review))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(purposes, [.imported(recommendedProfile: nil)])
        XCTAssertNil(session.importNoticeMessage)
    }

    func testReviewedImportRejectsInvalidCreatorSettingsBeforeInstallation() {
        let sourceURL = URL(fileURLWithPath: "/tmp/no-profile.monglepet")
        let installed = makeInstalled(id: firstID, name: "권장 설정 없음")
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: installed,
            profile: nil,
            profileIssue: .invalidField("behavior.sequences")
        )
        var packages: [InstalledPetPackage] = []
        var purposes: [NewUserPetInstallationPurpose] = []
        var attemptedInstall = false
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            reviewedPackageInstaller: { _, _, _ in
                attemptedInstall = true
                packages = [installed]
                return PetPackageInstallationResult(
                    installedPackage: installed,
                    importReview: review
                )
            }
        )
        session.onNewUserPetInstallation = { _, purpose in
            purposes.append(purpose)
        }

        XCTAssertFalse(session.installReviewedPackage(review))
        XCTAssertFalse(attemptedInstall)
        XCTAssertTrue(packages.isEmpty)
        XCTAssertTrue(purposes.isEmpty)
        XCTAssertEqual(
            session.errorMessage,
            "펫 파일의 행동과 이동 설정에 문제가 있어 추가할 수 없습니다. 파일을 다시 내려받거나 제작자에게 알려 주세요."
        )
        XCTAssertNil(session.importNoticeMessage)
    }

    func testDuplicateReviewedImportInstallsSeparately() {
        let sourceURL = URL(fileURLWithPath: "/tmp/duplicate-profile.monglepet")
        let existing = makeInstalled(
            id: firstID,
            name: "기존 펫",
            packageID: "test.duplicate"
        )
        let separate = makeInstalled(
            id: secondID,
            name: "새 설치 펫",
            packageID: "test.duplicate"
        )
        let profile = makeRecommendedProfile()
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: separate,
            profile: profile
        )
        var packages = [existing]
        var requestedModes: [PetPackageInstallationMode] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            reviewedPackageInstaller: { _, mode, _ in
                requestedModes.append(mode)
                if mode == .rejectDuplicate {
                    throw PetLibraryError.duplicatePackage(
                        metadata: review.metadata,
                        installationIDs: [self.firstID]
                    )
                }
                packages.append(separate)
                return PetPackageInstallationResult(
                    installedPackage: separate,
                    importReview: review
                )
            }
        )
        XCTAssertTrue(session.installReviewedPackage(review))

        XCTAssertEqual(requestedModes, [.installSeparately])
        XCTAssertEqual(session.selection, .installed(secondID))
    }

    func testDuplicateReviewedImportDoesNotReplaceExistingInstallation() {
        let sourceURL = URL(fileURLWithPath: "/tmp/replacement-profile.monglepet")
        let existing = makeInstalled(
            id: firstID,
            name: "기존 펫",
            packageID: "test.replacement",
            version: "1.0.0"
        )
        let replacement = makeInstalled(
            id: secondID,
            name: "새 설치 펫",
            packageID: "test.replacement",
            version: "2.0.0"
        )
        let profile = makeRecommendedProfile()
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: replacement,
            profile: profile
        )
        var packages = [existing]
        var requestedModes: [PetPackageInstallationMode] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            reviewedPackageInstaller: { _, mode, _ in
                requestedModes.append(mode)
                packages.append(replacement)
                return PetPackageInstallationResult(
                    installedPackage: replacement,
                    importReview: review
                )
            }
        )
        XCTAssertTrue(session.installReviewedPackage(review))
        XCTAssertEqual(requestedModes, [.installSeparately])
        XCTAssertEqual(packages.map(\.installationID), [firstID, secondID])
        XCTAssertEqual(packages.first?.package.metadata.version, "1.0.0")
    }

    func testReviewedImportRequestsNewActivePetWithRecommendedProfile() {
        let sourceURL = URL(fileURLWithPath: "/tmp/profile.monglepet")
        let installed = makeInstalled(id: secondID, name: "권장 펫")
        let profile = makeRecommendedProfile()
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: installed,
            profile: profile
        )
        var packages: [InstalledPetPackage] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            reviewedPackageInstaller: { _, _, _ in
                packages.append(installed)
                return PetPackageInstallationResult(
                    installedPackage: installed,
                    importReview: review
                )
            }
        )
        var purposes: [NewUserPetInstallationPurpose] = []
        session.onNewUserPetInstallation = { _, purpose in
            purposes.append(purpose)
        }

        XCTAssertTrue(session.installReviewedPackage(review))
        XCTAssertEqual(
            purposes,
            [.imported(recommendedProfile: profile)]
        )
        XCTAssertEqual(session.selection, .installed(secondID))
    }

    func testReviewedImportRollsBackInstallationWhenSettingsSaveFails() {
        let sourceURL = URL(fileURLWithPath: "/tmp/rollback.monglepet")
        let original = makeInstalled(id: firstID, name: "기존 펫")
        let installed = makeInstalled(id: secondID, name: "실패 펫")
        let review = makeImportReview(
            sourceURL: sourceURL,
            installed: installed,
            profile: nil
        )
        var packages = [original]
        var removedIDs: [UUID] = []
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { installationID in
                removedIDs.append(installationID)
                packages.removeAll { $0.installationID == installationID }
            },
            reviewedPackageInstaller: { _, _, _ in
                packages.append(installed)
                return PetPackageInstallationResult(
                    installedPackage: installed,
                    importReview: review
                )
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        session.onNewUserPetInstallation = { _, _ in
            throw AppSettingsMutationError.saveFailed("테스트 실패")
        }

        XCTAssertFalse(session.installReviewedPackage(review))
        XCTAssertEqual(removedIDs, [secondID])
        XCTAssertEqual(packages.map(\.installationID), [firstID])
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertTrue(session.errorMessage?.contains("되돌렸습니다") == true)
    }

    func testDuplicatePackageIDInstallsImmediatelyAsSeparateCopy() {
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
                packages.append(incoming)
                return incoming
            },
            editablePackageProvider: { $0.installationID == self.firstID }
        )
        _ = session.reload(preferredInstallationID: secondID)

        XCTAssertTrue(session.installPackage(from: sourceURL))
        XCTAssertEqual(requestedModes, [.installSeparately])
        XCTAssertEqual(
            packages.map(\.installationID),
            [firstID, secondID, thirdID]
        )
        XCTAssertEqual(session.selection, .installed(thirdID))
        for (index, item) in session.items.filter({ !$0.isBuiltIn }).enumerated() {
            XCTAssertEqual(
                session.libraryDisplayLabel(for: item),
                "\(item.metadata.displayName) · \(item.metadata.version) · 설치 \(index + 1)"
            )
        }
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
        var purposes: [NewUserPetInstallationPurpose] = []
        session.onInstalledContentChange = { selections.append($0.selection) }
        session.onNewUserPetInstallation = { received, purpose in
            XCTAssertEqual(received, installed)
            purposes.append(purpose)
        }

        XCTAssertTrue(session.createUserPet(request))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertTrue(session.selectedItem.isEditable)
        XCTAssertEqual(selections, [.installed(firstID)])
        XCTAssertEqual(purposes, [.newPet])
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
        var purposes: [NewUserPetInstallationPurpose] = []
        session.onInstalledContentChange = { selections.append($0.selection) }
        session.onNewUserPetInstallation = { received, purpose in
            XCTAssertEqual(received, copy)
            purposes.append(purpose)
        }

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
        XCTAssertEqual(
            purposes,
            [.editableCopy(sourcePetKey: .installed(firstID))]
        )
        XCTAssertNil(session.errorMessage)
    }

    func testNewPetInstallationRollsBackWhenSettingsSaveFails() {
        let original = makeInstalled(id: firstID, name: "기존 펫")
        let created = makeInstalled(id: secondID, name: "새 펫")
        var packages = [original]
        var removedIDs: [UUID] = []
        let request = UserPetCreationRequest(
            displayName: "새 펫",
            animationName: "기본",
            frameDurationMilliseconds: 120,
            loops: true,
            sourceURLs: [URL(fileURLWithPath: "/tmp/frame.png")]
        )
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { installationID in
                removedIDs.append(installationID)
                packages.removeAll { $0.installationID == installationID }
            },
            userPetCreator: { _ in
                packages.append(created)
                return created
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var selections: [PetLibrarySelection] = []
        session.onInstalledContentChange = { selections.append($0.selection) }
        session.onNewUserPetInstallation = { _, _ in
            throw AppSettingsMutationError.saveFailed("테스트 실패")
        }

        XCTAssertFalse(session.createUserPet(request))
        XCTAssertEqual(removedIDs, [secondID])
        XCTAssertEqual(packages.map(\.installationID), [firstID])
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertTrue(selections.isEmpty)
        XCTAssertTrue(session.errorMessage?.contains("되돌렸습니다") == true)
    }

    func testFailedRollbackKeepsInstallationDiscoverableWithRecoveryMessage() {
        let original = makeInstalled(id: firstID, name: "기존 펫")
        let created = makeInstalled(id: secondID, name: "정리 실패 펫")
        var packages = [original]
        let request = UserPetCreationRequest(
            displayName: "정리 실패 펫",
            animationName: "기본",
            frameDurationMilliseconds: 120,
            loops: true,
            sourceURLs: [URL(fileURLWithPath: "/tmp/frame.png")]
        )
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in
                throw PetLibraryError.fileOperationFailed
            },
            userPetCreator: { _ in
                packages.append(created)
                return created
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        session.onNewUserPetInstallation = { _, _ in
            throw AppSettingsMutationError.saveFailed("테스트 실패")
        }

        XCTAssertFalse(session.createUserPet(request))
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertEqual(
            Set(session.items.compactMap { $0.selection.installationID }),
            Set([firstID, secondID])
        )
        XCTAssertTrue(
            session.errorMessage?.contains(
                "앱을 다시 시작한 뒤 내 펫에서 확인"
            ) == true
        )
    }

    func testCreatingEditableCopyFromEditablePetKeepsOriginal() {
        let installed = makeInstalled(id: firstID, name: "사용자 펫")
        let copy = makeInstalled(id: secondID, name: "사본")
        var packages = [installed]
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { _ in true },
            editableCopyCreator: { received, displayName in
                XCTAssertEqual(received, installed)
                XCTAssertEqual(displayName, "사본")
                packages.append(copy)
                return copy
            }
        )
        _ = session.reload(preferredInstallationID: firstID)

        XCTAssertTrue(
            session.createEditableCopyOfSelectedPet(displayName: "사본")
        )
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.selection, .installed(secondID))
        XCTAssertEqual(packages.map(\.installationID), [firstID, secondID])
    }

    func testUpdatingSelectedPetDetailsReloadsSameInstallationAndNotifiesRuntime() {
        let original = makeInstalled(id: firstID, name: "처음 이름")
        let updated = makeInstalled(id: firstID, name: "새 이름")
        var packages = [original]
        let request = UserPetDetailsRequest(
            displayName: "새 이름",
            version: "2.0.0",
            author: "새 제작자",
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
        session.onInstalledContentChange = { selections.append($0) }

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

    func testDuplicatingAnimationUsesNextCopyNameWithoutPublishingReferenceChange() {
        let original = makeInstalled(
            id: firstID,
            name: "사용자 펫",
            motionIDs: ["idle", "wave", "wave 복사본", "wave 복사본 2"]
        )
        let duplicated = makeInstalled(
            id: firstID,
            name: "사용자 펫",
            motionIDs: [
                "idle",
                "wave",
                "wave 복사본",
                "wave 복사본 2",
                "wave 복사본 3"
            ]
        )
        var packages = [original]
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { packages },
            installationRemover: { _ in },
            editablePackageProvider: { _ in true },
            animationDuplicator: {
                sourceID,
                duplicateID,
                installedPackage in
                XCTAssertEqual(sourceID, "wave 복사본 2")
                XCTAssertEqual(duplicateID, "wave 복사본 3")
                XCTAssertEqual(installedPackage, original)
                packages = [duplicated]
                return duplicated
            }
        )
        _ = session.reload(preferredInstallationID: firstID)
        var referenceChanges: [PetAnimationReferenceChange] = []
        session.onAnimationReferenceChange = { referenceChanges.append($0) }

        let duplicateID = session.duplicateSelectedPetAnimation(
            id: "wave 복사본 2"
        )

        XCTAssertEqual(duplicateID, "wave 복사본 3")
        XCTAssertEqual(
            session.selectedItem.definition.motions.map(\.id),
            ["idle", "wave", "wave 복사본", "wave 복사본 2", "wave 복사본 3"]
        )
        XCTAssertEqual(session.selection, .installed(firstID))
        XCTAssertTrue(referenceChanges.isEmpty)
        XCTAssertNil(session.errorMessage)
    }

    func testBuiltInPetCannotStartSharingReview() {
        var reviewCallCount = 0
        let session = PetLibrarySession(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in },
            packageShareReviewer: { _, _, _ in
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
            packageShareReviewer: { receivedPackage, receivedProfile, _ in
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
        BuiltInPet.mongleDefinition()
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

    private func makeRecommendedProfile() -> RecommendedPetProfile {
        RecommendedPetProfile(
            mode: .manual,
            manualSequenceID: "default",
            sequences: [
                BehaviorSequence(
                    id: "default",
                    steps: [
                        BehaviorStep(motionID: "idle", repeatCount: 2)
                    ],
                    repeats: true
                )
            ],
            automaticRules: [],
            movement: PetMovementSettings(
                mode: .freeRoaming,
                speed: 180,
                cursorDistance: 96,
                stopRadius: 16,
                freeRoamingDwellMilliseconds: 6_000,
                prefersFrontmostWindow: true,
                cursorFollowingMotionID: nil,
                freeRoamingMotionID: "idle"
            ),
            pettingMotionID: "idle"
        )
    }

    private func makeImportReview(
        sourceURL: URL,
        installed: InstalledPetPackage,
        profile: RecommendedPetProfile?,
        profileIssue: RecommendedPetProfileError? = nil
    ) -> PetPackageImportReview {
        PetPackageImportReview(
            sourceURL: sourceURL,
            metadata: installed.package.metadata,
            definition: installed.package.definition,
            containsRecommendedProfile: profile != nil || profileIssue != nil,
            recommendedProfile: profile,
            recommendedProfileIssue: profileIssue
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
