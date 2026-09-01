# Windows 데스크톱 펫·설치한 펫 UX 인계

> 이 문서의 `데스크톱 펫`/`설치한 펫` 분리 UI는 D-111과 D-112가 대체했다. installation·instance 데이터 분리와 항상 새 설치 원칙만 참고하고, Windows의 최종 UI·transaction·편집·행동·말풍선 구현은 `WINDOWS_MY_PETS_RUNTIME_POLISH_HANDOFF.md`를 우선한다.

## 목적

macOS에서 먼저 확정한 설치 콘텐츠와 실행 인스턴스의 역할 분리, 항상 새 설치 가져오기와 설정 화면 정보 구조를 Windows 네이티브 UI에 같은 사용자 결과로 반영한다.

## 기준 결정

- 공통 결정: D-076, D-110
- macOS 작업 계획: `../work_plans/tasks/2026-09-01-desktop-pet-library-ux.md`
- 공통 명세: `../specifications/PET_PACKAGE.md`, `../specifications/SETTINGS_SCHEMA.md`
- `.monglepet` formatVersion, 권장 프로필 v11과 로컬 settings schema-v15는 변경하지 않는다.

## 확정 용어와 역할

### 설치한 펫

- 다운로드·파일 가져오기 또는 앱 제작으로 라이브러리에 저장된 콘텐츠다.
- package ID와 별개인 installation UUID를 갖는다.
- 미리보기, 메타데이터, 애니메이션, 편집 가능한 사본, 패키지 저장과 설치 삭제를 제공한다.
- 목록을 고르는 행위는 탐색·관리 대상을 바꿀 뿐 현재 데스크톱 펫을 교체하지 않는다.

### 데스크톱 펫

- 화면에서 실행되는 active instance다.
- instance UUID와 독립 behavior profile UUID, overlay, 표시 상태와 순서를 갖는다.
- 같은 설치한 펫으로 여러 마리를 추가할 수 있고 각 마리의 크기·행동·이동·쓰다듬기·말풍선 설정은 독립적이다.
- 데스크톱에서 제거하면 installation은 남고 해당 instance와 profile만 삭제된다.

## 필수 사용자 결과

1. 설정 첫 목적지 명칭을 `데스크톱 펫`으로 표시한다.
2. 보관함 목적지 명칭을 `설치한 펫`으로 표시한다.
3. 설치한 펫 목록 선택은 `selectedPetInstanceID`나 선택 인스턴스의 `petKey`를 바꾸지 않는다.
4. 설치한 펫 화면에는 명시적인 `데스크톱에 추가` 작업을 제공한다.
5. 같은 installation을 여러 번 추가할 때마다 새 instance UUID와 새 profile UUID를 만든다.
6. 일반 로컬·웹 가져오기는 package ID 중복 여부와 관계없이 항상 새 installation UUID를 만든다.
7. 일반 가져오기에서 기존 설치 교체 대상 선택과 파괴적 교체 버튼을 제거한다.
8. 데스크톱 펫 제거 확인에는 다음 결과를 명시한다.
   - 크기, 행동, 이동, 쓰다듬기와 말풍선 등 해당 인스턴스의 개인 설정도 삭제됨
   - 설치한 펫은 남음
   - 지금 설정은 복원되지 않음
9. 설치 항목 삭제는 데스크톱 제거와 다른 작업으로 유지하고, 참조 중인 instance가 있으면 개수를 표시해 차단하거나 명시적 후속 처리를 요구한다.

## 설정 NavigationView 정보 구조

WinUI 네이티브 `NavigationView`를 유지하고 macOS와 같은 역할을 다음 목적지로 제공한다.

- 데스크톱
  - 데스크톱 펫
  - 일반
- 선택한 펫
  - 화면 표시
  - 평상시 행동
  - 이동
  - 상호작용
  - 행동 편집
  - 말풍선
  - 규칙 설정
- 라이브러리
  - 설치한 펫

`상호작용`에는 쓰다듬기와 포인터 관련 표시 옵션을 배치한다. Windows의 Mica, grouped card, ToggleSwitch와 Slider 스타일은 유지하며 SwiftUI 구현을 직역하지 않는다.

## Domain·저장 경계

- `installationID`, `instanceID`, `behaviorProfileID`의 현재 분리를 유지한다.
- 설치한 펫 탐색 선택은 UI 전용 상태이며 공통 settings schema에 추가하지 않는다.
- active instance 추가·제거는 기존 원자적 전체 settings 저장을 사용한다.
- 가져오기 설치는 기존 staging 검증과 rename 경계를 유지하되 일반 모드는 항상 별도 설치를 선택한다.
- package ID, 웹 slug와 installation UUID를 합치거나 자동 업데이트 의미로 재해석하지 않는다.
- 앱 PFN, exe 이름, 경로와 Win32 HWND를 공통 데이터에 추가하지 않는다.

## 필수 자동 테스트

1. 설치한 펫 목록 선택이 선택 instance와 `petKey`를 바꾸지 않음
2. 같은 package ID를 연속 두 번 가져오면 서로 다른 installation UUID 두 개가 생성됨
3. 가져오기에서 기존 installation 내용과 연결 profile이 바뀌지 않음
4. 같은 installation을 두 번 데스크톱에 추가하면 독립 instance/profile/overlay가 생성됨
5. 한 instance 설정 변경이 다른 instance에 전파되지 않음
6. 데스크톱 제거 후 installation과 다른 instance는 유지되고 제거 profile만 정리됨
7. 재실행 후 탐색 선택과 무관하게 선택 instance와 모든 독립 설정이 유지됨
8. 로컬·웹 가져오기가 같은 항상 새 설치 경로를 사용함
9. 기존 schema-v1~v15 이관과 권장 프로필 v1~v11 회귀 테스트
10. 전체 Debug·Release 테스트와 빌드

## 실제 Windows QA

- 설치한 펫을 여러 항목 둘러보면서 현재 데스크톱 펫이 바뀌지 않는지 확인
- 같은 파일과 같은 웹 펫을 각각 두 번 가져와 네 설치 항목이 독립적으로 남는지 확인
- 각 설치 항목에서 데스크톱 펫을 추가하고 서로 다른 크기·이동·말풍선을 저장한 뒤 재실행
- 데스크톱 펫 제거 경고의 문구와 실제 데이터 범위 확인
- 설치한 펫 삭제가 참조 중 instance를 조용히 깨뜨리지 않는지 확인
- 좁은 창, 다크·라이트 테마, 키보드 탐색과 Narrator에서 새 NavigationView 목적지 확인

## Windows에서 변경하지 않을 항목

- macOS SwiftUI sidebar 구현을 C#으로 직역하지 않는다.
- 기존 Win32 overlay·Composition, 클릭 통과와 HWND 복구 코드를 변경하지 않는다.
- package schema, 권장 프로필 schema와 settings schema를 이 UI 작업 때문에 올리지 않는다.
- 자동 업데이트·기존 설치 교체를 일반 가져오기 화면에 추가하지 않는다.

## 완료 보고

- 변경한 WinUI 화면과 탐색 상태 분리
- 항상 새 설치 importer 경계
- instance/profile 추가·제거 결과
- 자동 테스트와 Debug·Release 빌드 결과
- 실제 Windows QA와 남은 접근성·DPI 위험
- macOS와의 교차 시나리오 결과
- git status와 커밋·푸시 상태
