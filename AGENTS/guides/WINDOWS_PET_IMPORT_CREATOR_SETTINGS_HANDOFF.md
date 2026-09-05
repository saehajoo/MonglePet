# Windows 펫 가져오기 호환성 차단과 제작자 설정 자동 적용 인계

> 2026-09-05 D-121이 D-118의 미래·손상 제작자 설정 fallback을 대체한다. 아래 체크포인트의 과거 구현 결과보다 이 문서의 최신 확정 사용자 결과와 후속 구현 항목을 우선한다.

## 목적

macOS에서 D-121로 확정한 완전한 제작자 설정 가져오기, 최소 앱 버전 차단과 요약 중심 검토 화면을 Windows WinUI 3 앱에 반영한다. Windows 소스 변경·빌드·실제 QA는 Windows 환경에서 진행한다. `.monglepet` formatVersion, 로컬 schema-v16과 제작자 설정 schema-v12는 변경하지 않는다.

## 먼저 확인할 기준

- 제품 결정: `AGENTS/project/DECISIONS.md`의 D-118과 이를 대체하는 D-121
- 공통 패키지 계약: `AGENTS/specifications/PET_PACKAGE.md`의 `제작자 설정 가져오기`
- 저장 계약: `AGENTS/specifications/SETTINGS_SCHEMA.md`
- macOS 기준 구현: `apps/macos/MonglePet/PetLibrary/PetLibrarySession.swift`, `apps/macos/MonglePet/SettingsView.swift`
- Windows 현재 설치 transaction: `apps/windows/src/MonglePet.Windows/App.xaml.cs`의 `ImportReviewedPackage`
- Windows 현재 검토 UI: `apps/windows/src/MonglePet.Windows/MainPage.xaml.cs`의 `ReviewAndImportPackageAsync`, `ShowImportReview`
- URL 다운로드·임시 수명: `AGENTS/guides/WINDOWS_WEB_PET_IMPORT_HANDOFF.md`

## 확정 사용자 결과

1. 로컬 파일과 웹 URL 모두 같은 검토 화면을 사용한다.
2. 제목은 `펫 추가`, 설명은 `펫과 제작자가 구성한 행동·이동·말풍선 설정을 함께 추가합니다. 추가한 뒤 모든 설정을 자유롭게 변경할 수 있습니다.`로 표시한다.
3. `기본 설정으로 추가`, `권장 설정으로 추가`와 적용 범위 선택을 모두 제거한다.
4. 호환 가능한 펫의 최종 동작은 primary `펫 추가`와 cancel `취소`뿐이다.
5. 유효한 `RecommendedProfile`이 있으면 그 안에 존재하는 휴대 가능한 설정 전체를 새 펫에 자동 적용한다.
6. 제작자 설정 파일이 없는 레거시 패키지는 `이전 방식으로 만든 펫이라 움직임과 행동 설정이 포함되어 있지 않습니다. MonglePet 기본 동작으로 추가됩니다.`를 핵심 영역에 표시하고 안전한 최소 profile·overlay로 추가한다.
7. package 또는 웹 게시 metadata의 최소 앱 버전이 현재 앱보다 높으면 설치를 차단한다. primary `MonglePet 업데이트`는 `https://mapleroom.kr/monglepet/download`를 사용자의 기본 브라우저로 열고 자동 다운로드·설치는 하지 않는다.
8. 미래 제작자 설정 schema는 업데이트 필요 상태로 설치를 차단한다. unreadable 또는 의미상 손상된 제작자 설정은 잘못된 펫 파일로 표시하고 다시 내려받거나 제작자에게 알리도록 안내한다.
9. 일반 가져오기에는 `설정 없이 추가`, `애니메이션만 추가` 또는 최소 profile로 강행하는 우회 동작을 제공하지 않는다. 애니메이션 자산 가져오기는 펫 제작·편집 화면의 별도 기능이다.
10. 사용자 화면에서는 파일명 `recommended-profile.json`이나 `권장 프로필` 대신 `제작자 설정`을 사용한다. C# 타입과 JSON 파일명은 바꾸지 않는다.
11. 같은 패키지를 반복 추가하면 매번 독립 installation·instance·behavior profile을 만든다.
12. 기존 펫의 profile·overlay와 전역 설정은 변경하지 않는다.

## Windows Domain·저장 변경

- `PetRecommendedProfileApplyOptions`와 `None`을 가져오기 사용자 선택 모델로 사용하지 않는다. 다른 내부 용도가 없다면 제거한다.
- `App.ImportReviewedPackage`는 apply options를 받지 않고 검토된 `PetPackageImportReview` 하나로 정책을 결정한다.
- `review.RecommendedProfile`이 유효하면 현재 부분 선택 분기를 없애고 다음을 모두 새 `BehaviorProfile`에 복사한다.
  - `StationaryBehaviorMode`, `StationarySequenceId`, `RandomSequenceIds`
  - 행동 `Sequences`
  - 입력 없음·앱 사용을 포함해 패키지에 실제 포함된 `AutomaticRules`와 `AutomaticRulePriorityOrder`
  - 독립된 전체 `Movement`
  - 방향별 행동과 도망가기 평상시 자유 이동
  - `PettingBehaviorId`
  - 전체 `Speech`
  - v10+ 휴대 표시 설정 전체
- `RecommendedProfile`이 nil이면서 제작자 설정 파일도 없는 경우에만 `BehaviorProfileDefaults.Create(new PetBehaviorKey.Installed(...))`와 `OverlaySettings.Default`를 사용한다.
- package·게시 최소 버전 부족, 미래 schema, unreadable, 의미상 손상 상태를 설치 가능 여부와 차단 사유가 있는 Domain 결과로 구분한다. 문자열 UI 검사로 정책을 판단하지 않는다.
- `App.ImportReviewedPackage`는 UI와 별개로 install 직전에 `CanInstall`을 다시 검사한다. 차단 상태에서는 library store와 settings transaction을 시작하지 않는다.
- `CommitNewPet`의 새 instance/profile UUID 생성과 원자적 settings 저장을 유지한다. profile과 overlay는 기존 인스턴스의 mutable 객체를 재사용하지 않는다.
- settings 저장 실패 시 이미 설치한 installation을 제거하는 기존 catch/rollback을 유지한다. 제거까지 실패한 복합 오류도 기존 복구 메시지와 진단 식별자를 유지한다.
- review 뒤 package 내용 재검증과 hash 비교를 유지한다. 초기 review와 설치 시점의 제작자 설정이 다르면 설치하지 않는다.

## WinUI 변경

- `선택한 펫` NavigationView에서 `행동 편집`을 `펫 정보·애니메이션` 바로 다음에 배치한다. 사용자가 애니메이션을 준비한 뒤 이를 조합해 행동을 만드는 순서를 탐색 구조에서도 이해할 수 있어야 한다.
- `ShowImportReview`의 반환값은 사용자 적용 옵션이 아니라 `bool`/확정 여부 또는 nullable review confirmation처럼 단순화한다.
- 펫 이름·제작자·버전, 호환 결과와 한 줄 핵심 문구는 항상 표시한다. 전체 호환 버전, 평상시 행동·규칙·이동·방향·쓰다듬기·말풍선·휴대 표시 요약은 기본으로 접힌 `자세히 보기`에 둔다.
- 유효한 제작자 설정의 핵심 문구는 `제작자가 구성한 행동·이동·말풍선 설정이 함께 적용됩니다.`로 표시한다. checkbox, secondary 적용 버튼과 범위 선택은 제공하지 않는다.
- 최소 버전 부족과 미래 schema는 차단 사유를 접힌 영역 밖에 표시한다. `ContentDialog.PrimaryButtonText = "MonglePet 업데이트"`로 두고 `Windows.System.Launcher.LaunchUriAsync`로 고정 공식 URL을 연다. 패키지나 API가 준 임의 다운로드 URL을 이 버튼에 사용하지 않는다.
- unreadable·손상 제작자 설정은 접힌 영역 밖에 `펫 파일의 행동과 이동 설정에 문제가 있어 추가할 수 없습니다. 파일을 다시 내려받거나 제작자에게 알려 주세요.`를 표시하고 설치 primary 버튼을 제공하지 않는다.
- 호환 가능한 경우에만 `ContentDialog.Title = "펫 추가"`, `PrimaryButtonText = "펫 추가"`, `CloseButtonText = "취소"`, `DefaultButton = ContentDialogButton.Primary`로 둔다. 차단 상태의 close는 `닫기`로 표시할 수 있다.
- 내부 필드명, enum 문자열과 schema codec 예외를 그대로 표시하지 않는다. `invalidField("behavior.sequences")` 같은 값은 사용자가 이해할 수 있는 설명으로 매핑한다.
- 로컬 오류는 기존 library InfoBar, 웹 다운로드 오류는 기존 URL 영역 InfoBar를 유지한다.

## 유지할 보안·호환 경계

- 실행 파일·스크립트, path traversal·symlink, 손상 자산, 허용하지 않는 확장자, 압축·크기 제한, 지원하지 않는 package format은 계속 전체 설치를 차단한다.
- 제작자 설정 1 MiB 초과도 계속 전체 설치를 차단한다.
- 제작자 설정 파일이 없는 레거시 패키지만 최소 profile 호환 대상으로 취급한다. 미래·손상 제작자 설정은 설치 차단이다.
- 기본 애니메이션, 삭제할 수 없는 최소 기본 행동과 사라진 참조 fallback을 제거하지 않는다.
- 화면 좌표·디스플레이 식별자·모든 펫 공통 이동 범위·깨움 상태·로그인 실행·설치/인스턴스 ID는 가져오지 않는다.
- macOS Bundle Identifier를 Windows exe/PFN 규칙으로 변환하지 않는다. 공통 codec이 해당 플랫폼에서 유효하다고 판정해 패키지에 남긴 조건 규칙만 적용한다.
- Windows HWND·Composition·DPI 코드와 overlay runtime은 이 작업 범위가 아니다.

## 필수 자동 테스트

1. 유효한 제작자 설정이 별도 선택 없이 행동·평상시·규칙·이동·방향·쓰다듬기·말풍선·표시에 모두 적용된다.
2. 앱 사용 규칙을 포함한 유효 profile은 기존 부분 선택 때문에 조용히 빠지지 않는다.
3. 설정이 없는 패키지는 최소 profile·overlay로 추가된다.
4. 미래 schema는 업데이트 필요 상태이고 손상 제작자 설정은 잘못된 파일 상태이며 둘 다 설치되지 않는다.
5. 1 MiB 초과 제작자 설정과 기존 package 보안 실패는 설치되지 않는다.
6. 기존 `기본 설정으로 추가`·`권장 설정으로 추가` 옵션 경로가 제거된다.
7. 기존 펫의 profile·overlay와 전역 설정은 전후 동일하다.
8. 같은 패키지 두 번 추가 시 installation·instance·profile ID가 모두 다르다.
9. settings 저장 실패 시 새 installation·instance·profile이 남지 않고 이전 선택이 유지된다.
10. 검토 취소 시 library·settings·temp session이 바뀌지 않는다.
11. package 최소 버전과 웹 게시 최소 버전 중 하나라도 높으면 더 높은 버전으로 설치를 차단한다.
12. 제작 앱 버전만 높고 최소 버전과 schema가 호환되면 설치한다.
13. 업데이트 버튼은 고정 공식 HTTPS 주소만 기본 브라우저로 열며 자동 다운로드나 임의 URL 실행을 하지 않는다.
14. 로컬 파일과 URL 다운로드 완료가 같은 import policy 함수를 호출한다.
15. 검토 뒤 패키지 내용 변경 거부와 URL temp 정리 회귀를 통과한다.

## 실제 Windows QA

- 유효·설정 없음 패키지는 `펫 추가`, 최소 버전 부족·미래 schema는 `MonglePet 업데이트`, 손상 설정은 설치 버튼 없음으로 표시되는지 확인한다.
- `자세히 보기`가 기본으로 접혀 있고 핵심 적용 결과와 차단 사유는 항상 보이는지 확인한다.
- 유효 패키지 추가 직후 행동·이동·방향·쓰다듬기·말풍선·크기·투명도·클릭 통과를 확인한다.
- 기존 펫과 새 펫 값을 서로 다르게 편집하고 재실행해 독립성을 확인한다.
- 같은 로컬 파일과 같은 웹 펫을 각각 두 번 추가해 네 개의 독립 펫이 남는지 확인한다.
- 취소와 settings 오류 주입에서 installation·instance·profile·temp 파일이 남지 않는지 확인한다.
- macOS에서 내보낸 v11 패키지를 Windows로 가져오고 Windows에서 다시 내보낸 결과를 macOS에 가져와 휴대 설정을 비교한다.
- keyboard, Narrator, 좁은 설정 창과 라이트·다크 테마에서 dialog 정보 순서와 primary/cancel 동작을 확인한다.

## Windows 구현 체크포인트

- 2026-09-04: `PetRecommendedProfileApplyOptions`를 제거하고 Settings Domain의 `CreatorSettingsImportStatus`·`AddImportedPetInstance`로 유효 제작자 설정 전체와 휴대 표시의 독립 복사, 설정 없음과 적용 불가 fallback을 구분했다.
- `App.ImportReviewedPackage`는 검토 하나만 받아 같은 패키지를 별도 installation로 설치하고 새 instance/profile settings 저장을 완료한다. 기존 fingerprint 재검증과 settings 실패 시 installation 제거·복합 오류 경계는 유지한다.
- 로컬 파일과 웹 URL은 같은 `ReviewAndImportPackageAsync`를 사용한다. 검토 dialog는 정보용 요약과 단일 `펫 추가`·`취소`만 제공하며 적용 불가 fallback은 성공 InfoBar에서 별도로 알린다.
- `행동 편집`은 `펫 정보·애니메이션` 바로 다음으로 이동했다. 사용자 화면의 관련 용어는 `제작자 설정`으로 통일하고 내부 JSON 파일명과 C# codec 이름은 유지한다.
- 브라우저가 시작한 보조 프로세스는 검증된 기존 MonglePet PID에 전면 전환 권한을 넘긴 뒤 protocol payload를 전달한다. 실행 중 앱이 링크를 받았지만 settings 창이 브라우저 뒤에 남아 응답이 없는 것처럼 보이는 경로를 막는다.
- Debug·Release 각각 Activity 27개, Core 64개, Packages 28개, PetLibrary 90개, Settings 88개, Shell 23개로 총 320개 테스트와 전체 빌드가 경고·오류 없이 통과했다. 운영 웹의 반복 실행과 설치 업데이트·데이터 보존을 확인해 `windows-v1.6.0-preview.4`로 게시했다. 실제 Narrator·반복 로컬 추가와 macOS 교차 왕복은 아직 남아 있다.
- 위 체크포인트는 D-118 구현 당시 기록이다. D-121 호환성 차단·업데이트 링크·접힌 상세 UI의 Windows 구현과 실제 QA는 새 후속 작업으로 진행해야 한다.

## 완료 보고

- 제거한 선택 모델과 변경한 Domain·저장 transaction
- 제작자 설정 자동 적용 범위와 호환성 차단 결과 모델
- 로컬·웹 공통 경로
- 테스트 통과 수와 Debug·Release 빌드 결과
- 실제 Windows QA와 macOS 교차 왕복 결과
- 남은 위험, git status와 커밋·푸시 상태

Windows 구현과 실제 QA가 끝나기 전에는 `PLATFORM_PARITY.md`를 동등 완료로 바꾸지 않는다.
