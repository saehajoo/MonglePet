# 내 펫 통합·행동 문맥별 재생·말풍선 배치 보정

## 상태

- 상태: in_progress
- 생성일: 2026-09-01
- 마지막 갱신: 2026-09-02

## 목표

- 설치 콘텐츠와 실행 인스턴스를 사용자가 별도 제품처럼 이해하지 않아도 되는 단일 `내 펫` 흐름을 제공한다.
- 행동 단위 반복 옵션을 제거하고 단계별 반복 횟수만으로 재생 길이를 정한다.
- 펫 이동 중 말풍선이 펫의 투명 여백 때문에 멀어지거나 위·아래로 불필요하게 흔들리지 않게 한다.
- macOS에서 확정한 결과를 Windows 네이티브 구현에 빠짐없이 전달한다.

## 범위

- 공통 행동 실행 의미와 레거시 `repeats` 호환 경계
- 로컬·웹 가져오기에서 설치·인스턴스·프로필 원자적 생성
- macOS 단일 `내 펫` 대시보드와 선택 펫 편집 동선
- 현재 프레임의 불투명 영역을 기준으로 한 macOS 말풍선 배치
- Windows Domain·저장·WinUI·overlay runtime 구현과 테스트·실제 QA

## 제외 범위

- `.monglepet` formatVersion, 권장 프로필 v11, 로컬 settings schema-v15 변경
- 설치 콘텐츠 자동 업데이트·기존 설치 교체
- 제거한 펫의 휴지통·복원 이력
- 이번 작업의 버전·빌드 번호 승격과 Release 게시

## 확정 결정

- 평상시 고정 행동은 깨어 있는 동안 단계 목록을 계속 순환하고 조건 규칙 행동은 한 번 통과한 뒤 마지막 프레임을 유지한다.
- 랜덤 평상시 행동은 한 번 통과한 뒤 shuffle bag의 다음 행동을 첫 프레임부터 시작한다.
- 쓰다듬기는 한 번 재생한 뒤 중단한 일반 계층으로 돌아간다.
- 이동 행동만 실제 좌표 이동이 계속되는 동안 별도 scheduler에서 반복한다.
- 새 행동 UI에는 전체 반복 토글을 제공하지 않고 각 단계의 `repeatCount`만 제공한다.
- 저장 DTO의 `repeats`는 레거시·교차 플랫폼 왕복을 위해 읽고 기록하지만 런타임은 값이 아니라 fixed·random·규칙·상호작용 문맥으로 반복 여부를 결정한다.
- 설정 사이드바에는 전환 탭과 보관 상태가 없는 `내 펫` 목적지 하나를 제공한다. 내부 installation·instance·profile 분리는 유지한다.
- 가져오기는 항상 새 installation·instance·profile을 만들고 한 번의 사용자 작업처럼 완료한다. settings 저장 실패 시 새 installation을 제거하고 이전 선택을 복원한다.
- 자동 말풍선 위치는 표시 중 선택된 위·아래 방향을 유지하며 화면 경계 때문에 불가능할 때만 반대쪽으로 바꾼다. 기준 사각형은 패널 전체가 아니라 현재 프레임의 불투명 콘텐츠 영역이다.
- D-112에 따라 상단 `내 펫`/`가져오기·편집` 전환을 제거하고 사용 중·보관 중 펫을 한 대시보드에 표시한다.
- 펫 만들기·가져오기는 대시보드에서, 사본 만들기·내보내기는 active pet 카드에서 시작한다.
- 사용자에게 읽기 전용 상태를 표시하지 않는다. 가져온 단독 펫은 첫 편집 때 같은 installation을 편집 가능 상태로 전환하고, 내장·공유 콘텐츠는 선택한 instance만 자동 copy-on-write한다.
- 펫 정보와 애니메이션 편집은 `선택한 펫` 아래의 전용 화면에서 수행한다.
- D-113에 따라 `사용 중`·`보관 중` 구분도 제거한다. 모든 항목은 독립 설정을 가진 내 펫이며 재우기는 전체 상태를 보존하고 완전 삭제는 마지막 installation까지 제거한다.
- 과거 비활성 installation은 기존 미참조 profile을 우선 연결한 잠든 instance로 복구한다.

## 작업 순서

### 공통 계약

- [x] D-111에 행동 1회 재생, 내 펫 통합과 말풍선 배치 의미를 기록한다.
- [x] 행동·패키지·설정 명세에 레거시 필드 호환과 원자적 가져오기를 기록한다.
- [x] 상세 Windows 인계 문서를 작성한다.

### macOS

- [x] 행동 편집과 새 행동 화면에서 전체 반복 토글을 제거한다.
- [x] D-115에 따라 평상시 fixed는 저장된 `repeats`와 관계없이 계속 순환하고 랜덤의 각 행동·규칙·쓰다듬기는 한 번 재생하게 한다.
- [x] 랜덤 행동은 완료 뒤 다음 bag 항목을 강제로 새 cursor에서 시작하게 한다.
- [x] 이동 runtime의 이동 중 반복은 유지한다.
- [x] 설정 사이드바의 데스크톱 펫·설치한 펫 목적지를 단일 `내 펫` 목적지로 합친다.
- [x] 로컬·웹 가져오기 검토에서 기본 또는 권장 설정을 선택하고 새 instance/profile까지 원자적으로 추가한다.
- [x] settings 저장 실패 시 설치 롤백 경계를 연결한다.
- [x] 현재 프레임 알파 경계를 말풍선 anchor로 사용하고 자동 위치를 표시 중 고정한다.
- [x] 사용 중·보관 중 펫을 단일 대시보드로 합치고 생성·가져오기·복제·내보내기 동선을 옮긴다.
- [x] `선택한 펫 > 펫 정보·애니메이션` 화면을 추가하고 독립 library 선택 UI를 제거한다.
- [x] 읽기 전용 UI를 제거하고 단독 설치의 in-place editable 전환과 내장·공유 설치의 instance별 copy-on-write를 연결한다.
- [x] 보관 상태를 제거하고 재우기·완전 삭제·legacy orphan 복구로 단일 생명주기를 연결한다.
- [x] D-111 기준 관련 단위 테스트와 전체 단위 테스트를 통과한다.
- [x] D-111 기준 Debug 빌드와 `git diff --check`를 통과한다.
- [x] D-112 단일 대시보드·보편 편집 변경의 Debug 빌드와 `git diff --check`를 통과한다.
- [x] D-112·D-113 자동 테스트를 실행한다.
- [ ] 실제 앱 QA를 완료한다.

### Windows

- [x] `WINDOWS_MY_PETS_RUNTIME_POLISH_HANDOFF.md`에 구현 순서·자동 테스트·실제 QA를 기록한다.
- [x] Windows 환경에서 Domain·저장·WinUI·런타임 순서로 구현한다.
- [x] D-115에 따라 평상시 fixed만 연속 순환하고 랜덤의 각 행동·규칙·쓰다듬기의 1회 재생을 유지한다.
- [x] Debug·Release 전체 308개 테스트와 두 구성 빌드를 완료한다.
- [ ] packaged Release 실제 앱·성능 QA를 완료한다.

### 플랫폼 동등성

- [ ] macOS·Windows에서 레거시 `repeats` true/false 패키지를 가져와 fixed는 계속 순환하고 랜덤의 각 행동·규칙·쓰다듬기는 한 번만 재생되는지 확인한다.
- [ ] 양 플랫폼에서 같은 패키지를 반복 가져와 독립 펫과 프로필이 생기는지 확인한다.
- [ ] 권장 프로필 포함 패키지를 교차 왕복하고 모든 휴대 설정을 비교한다.
- [ ] 이동 중 말풍선 거리와 위·아래 안정성을 양 플랫폼에서 비교한다.

## 필수 자동 검증

- 동일한 완료 행동 재요청이 재시작되지 않음
- 레거시 `repeats` 값과 무관한 fixed 연속 순환과 규칙 행동 1회 재생·마지막 프레임 유지
- 랜덤 단일·복수 선택이 완료마다 첫 프레임에서 새 cursor 시작
- 이동 행동은 이동 중 반복하고 정지 즉시 종료
- 가져오기 성공 시 새 installation·instance·profile 생성과 선택
- 권장 프로필 적용 시 독립 overlay·행동·이동·말풍선 복사
- settings 저장 실패 시 installation·instance·profile·선택 rollback
- 알파 마스크의 불투명 경계 계산과 다중 화면 말풍선 clamp
- 기존 schema-v1~v15와 권장 프로필 v1~v11 왕복 회귀

## 실제 macOS QA

- 행동 편집에 전체 반복 옵션이 없고 단계 반복 횟수만 보이는지 확인
- 고정 행동이 자연스럽게 계속 순환하고 규칙 행동은 마지막 프레임에서 유지되며 설정 갱신 때문에 재시작하지 않는지 확인
- 랜덤 행동이 각 항목을 한 번씩 자연스럽게 이어 재생하는지 확인
- 자유 이동·따라가기·도망가기 동안 이동 모션은 계속 재생되고 정지 후 평상시 결과가 맞는지 확인
- 투명 여백이 큰 프레임과 높이가 다른 프레임에서 말풍선 간격이 안정적인지 확인
- 화면 위·아래 경계를 오갈 때 말풍선이 가능한 동안 같은 쪽을 유지하는지 확인
- 파일·웹 가져오기에서 기본/권장 설정 선택, 즉시 표시, 중복 독립 추가와 재실행을 확인
- 재우기 후 모든 설정 보존, 완전 삭제 후 instance·profile·마지막 installation 제거를 확인
- 과거 비활성 installation이 잠든 펫으로 한 번 복구되는지 확인
- 단독 가져온 펫과 내장·공유 펫의 편집, 취소, 재실행 독립성을 확인

## 진행 로그

- 2026-09-01: Windows `main` `30a3e47`과 깨끗한 작업 트리를 확인했다. `WINDOWS_MY_PETS_RUNTIME_POLISH_HANDOFF.md`를 최종 기준으로 Domain 행동 1회 재생부터 Windows 구현을 시작했다. 구형 `WINDOWS_DESKTOP_PET_LIBRARY_HANDOFF.md`에서는 installation·instance 분리와 항상 새 설치 원칙만 유지한다.
- 2026-09-01: Windows 행동 1회 재생·완료 프레임 유지, 항상 새 installation·instance·profile 가져오기, 단일 `내 펫`, 보편 편집·copy-on-write, 재우기·완전 삭제·legacy orphan 복구와 말풍선 alpha anchor·자동 방향 잠금을 구현했다. schema-v15·권장 프로필 v11과 저장 `repeats` 왕복은 유지했다. Debug·Release 각각 Activity 27, Core 62, Packages 28, PetLibrary 89, Settings 82, Shell 20으로 총 308개 테스트와 두 구성 빌드가 경고·오류 없이 통과했다. 실제 packaged UI·DPI·성능 QA와 macOS 교차 왕복은 남아 있다.
- 2026-09-01: 반복 문제, 말풍선 패널 기준 배치와 D-110 UI의 사용자 혼란을 검토하고 D-111 범위를 확정했다.
- 2026-09-01: 행동 1회 재생 runtime, 반복 UI 제거, 내 펫 통합 목적지, 원자적 가져오기와 알파 기반 말풍선 anchor를 1차 구현했다.
- 2026-09-01: macOS 전체 단위 테스트 529개 중 528개 통과·1개 조건부 건너뜀, Debug 빌드와 `git diff --check` 통과를 확인했다.
- 2026-09-01: 테스트 전용 설정으로 최신 Debug 앱을 실행해 단일 `내 펫` 진입점, `내 펫`/`가져오기·편집` 전환과 행동 편집의 전체 반복 옵션 제거를 확인했다. 행동·이동의 장시간 재생, 실제 이동 중 말풍선 거리와 파일·웹 가져오기 왕복은 실제 앱 QA로 남긴다.
- 2026-09-01: `testSettingsWindowOpens` XCUITest는 두 차례 모두 앱 연결 전에 Runner가 signal kill로 종료되어 실행 환경 제한으로 기록했다. 같은 화면은 Computer Use 접근성 트리로 직접 확인했다.
- 2026-09-01: D-112 단일 대시보드, `펫 정보·애니메이션`, 보편 편집과 저장 시점 copy-on-write를 구현하고 Windows 인계를 최종 동작 기준으로 다시 정리했다. 사용자 요청에 따라 이 후속 변경의 자동 테스트·빌드는 실행하지 않았다.
- 2026-09-01: 애니메이션 복제 초안의 Swift 제네릭 추론 오류를 명시적 frame draft 배열 변환으로 수정했고 D-112 포함 macOS Debug 빌드와 `git diff --check`를 통과했다. 자동 테스트는 실행하지 않았다.
- 2026-09-01: D-113에 따라 보관 카드를 제거하고 재우기·완전 삭제·legacy orphan 복구를 구현했다. Windows 인계도 보관 없는 최종 생명주기로 다시 정리했다.
- 2026-09-01: D-113 최종 소스의 macOS Debug 빌드와 `git diff --check`를 통과했다. 복구·삭제 rollback 단위 테스트를 추가했지만 사용자 요청에 따라 테스트 실행은 보류했다.
- 2026-09-01: 릴리스 요청에 따라 보류했던 테스트를 재개했다. D-113 회귀를 포함한 macOS 전체 531개 중 530개 통과·조건부 WebP fixture 1개 건너뜀·실패 0개와 별도 Debug 빌드를 통과했다.
- 2026-09-01: Windows 선택 펫 UI 후속 정리로 `펫 정보 수정`을 정보 요약 바로 아래로 이동하고 숨겨진 관리 섹션의 잔여 구분선 4개와 저장 위치·진단 정보를 제거했다. 화면 표시는 macOS 순서대로 크기·빠른 크기·투명도·픽셀 아트·클릭 통과·겹침 투명도를 배치하고, 평상시 행동의 빈 카드와 이동의 중복 제목·설명 및 선택 펫 화면의 공통 `설정 대상 펫` 요약을 제거했다. Windows Debug 빌드와 전체 308개 테스트가 통과했고 같은 소스의 Release 설치본을 로컬에서 갱신·실행했다. 실제 UI QA와 macOS의 동일 대상 요약 제거는 남아 있다.
- 2026-09-01: Windows 라이트·다크 테마의 주요 액션 버튼을 슬라이더·토글·라디오 활성 상태와 같은 MonglePet 중성 강조 토큰에 연결했다. 실제 `AccentButtonStyle`이 참조하는 상위 `AccentFillColor`와 글자 리소스까지 같은 normal·hover·pressed·disabled 토큰으로 통일하고, 전역 슬라이더의 36px 높이·중앙 정렬과 2px 아래 보정을 적용했다. `펫 가져오기`, 행동·단계·규칙 추가와 대화상자 기본 동작이 같은 색상 계열을 사용한다. Debug 빌드와 Release 로컬 재설치·실행을 확인했다.
- 2026-09-01: 회색 강조색이 활성·비활성 의미를 흐리는 문제를 보정해 primary button·slider 값·toggle on·radio checked를 라이트·다크별 따뜻한 MonglePet 강조색으로 통일하고 중립 보조 버튼 경계를 강화했다. `내 펫`은 중복 제목과 항상 열린 폼을 제거하고 수량 요약·생성/가져오기·전체 작업, 축약 상태 카드, 실제 단일 선택 시 펼쳐지는 이름/복제/내보내기/순서 작업, 화면 표시 토글과 일시정지/삭제 추가 메뉴로 재구성했다. ListView 단일 선택·시스템 focus visual과 명시적 Automation 이름을 유지했다. 색상 대비 계산, Debug·Release 빌드와 각 308개 테스트, `git diff --check`가 통과했다. 좁은 창·라이트/다크·키보드·Narrator 실제 UI QA와 macOS 정보 구조 후속 반영은 남아 있다.
- 2026-09-01: `내 펫`의 동작이 같은 버튼 묶음처럼 보이는 후속 피드백에 따라 전체 펫 작업을 제목·구분선이 있는 toolbar로 묶고, 카드의 화면 표시를 독립 control panel로 분리했다. 선택 확장 영역은 `이름`, `표시 순서`, `펫 작업`으로 나눠 저장만 primary, 순서와 복제·내보내기는 별도 중립 button group으로 표시한다. 화살표에 `앞으로`·`뒤로` 문구를 병기하고 선택 card에 옅은 accent tint를 추가했다. 전체/개별 일시정지는 현재 상태에 맞는 단일 문구를 사용하고 개별 메뉴에는 pause/play/delete 아이콘과 대상 문구를 제공한다. Debug 빌드와 전체 308개 테스트, `git diff --check`가 통과했다.
- 2026-09-01: 사용자 요청으로 macOS `ActivePetsSettingsView`의 현재 source를 다시 대조하고 위의 Windows 전용 축약/확장 초안을 최종 정보 구조로 사용하지 않기로 했다. Windows도 macOS와 같이 안내→생성/가져오기→전체 작업 순서를 쓰고 각 카드를 항상 펼쳐 84px preview, 이름·선택/상태, 원본, 이동·상호작용, 별칭, 사본·내보내기와 우측 switch·borderless 순서·삭제로 배치했다. primary는 펫 만들기에만 사용하고 내장 펫 내보내기 숨김, 삭제 가능 조건, 변경된 이름만 저장 가능, 선택 tint/stroke를 맞췄다. SwiftUI를 복사하지 않고 WinUI `SymbolIcon`, `ToggleSwitch`, `ListView`와 native focus visual로 구현했으며 Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-01: 실제 Windows 카드 후속 QA에 따라 이동 방식·클릭 통과 앞의 장식 아이콘을 제거하고 두 상태 글자를 11px로 한 단계 낮췄다. 카드 중앙과 우측을 공유 5행 Grid로 바꿔 `자는 중/깨어 있음`과 34px switch, 이름 저장 행과 34px 앞뒤 순서 버튼, 사본/내보내기 행과 휴지통 버튼이 각각 같은 수평선과 높이를 사용하게 했다. Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-01: 선택 badge가 상단 34px 행 높이까지 늘어나는 실제 화면을 확인해 `설정 중`을 24px 고정 높이·수직 중앙으로 제한했다. 카드 작업은 34px hit target을 유지하면서 사본·내보내기 glyph를 14px, 삭제 glyph와 앞뒤 화살표를 15px로 축소하고 서로 다른 Up/Download symbol 대신 동일한 `↑`/`↓` 방향 문자를 사용했다. `SymbolIcon`에는 직접 글자 크기를 지정할 수 없어 작은 `Viewbox`로 배율을 제한했으며 Debug 빌드가 통과했다.
- 2026-09-01: 후속 실제 화면에서 capsule 자체가 이름보다 강하게 보이는 문제를 확인해 `설정 중`은 테두리·배경 없는 11px accent text로 단순화했다. 상단 펫 만들기·가져오기와 전체 깨우기·재우기·일시정지의 기본 20px symbol은 모두 14px `Viewbox`로 축소하고 34px button hit target은 유지했다. 이전 축약/확장 초안에서 남은 미사용 ActivePet badge/group style도 제거했다. Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-01: 상태 switch의 빈 On/Off content presenter가 폭을 예약해 `자는 중`·`깨어 있음`이 카드 안쪽으로 밀리는 실제 화면을 수정했다. 상태 문구와 44px switch를 두 Auto 열 Grid로 묶고 content를 null로 제거해 우측 화살표·휴지통과 같은 카드 오른쪽 기준선에 정렬했다. Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-01: 펫 추가 작업과 전체 펫 제어가 연속된 같은 button row처럼 보이는 후속 피드백에 따라 두 작업군 사이에 1px divider, 12px 상단 padding과 `전체 펫 제어` caption을 추가했다. 생성·가져오기와 전체 깨우기·재우기·일시정지의 의미 계층은 유지하며 Debug 빌드와 `git diff --check`가 통과했다.
- 2026-09-02: 실제 다크 모드 QA에서 slider 값 구간이 primary button과 같은 주황색으로 보이고 switch의 켜짐·꺼짐 대비가 의도와 반대인 문제를 수정했다. 다크 slider 값 구간은 밝은 중립색, 나머지 track은 중간 회색으로 분리하고 switch는 `켜짐=밝은 track+어두운 knob`, `꺼짐=어두운 track+밝은 knob`로 정확히 반전했다. 라이트 모드는 `켜짐=진한 track`, `꺼짐=밝은 track`의 기존 의미를 유지한다. `내 펫` 카드의 상태 문구와 switch는 상단 이름 행에서 카드 중앙 상태 행으로 옮겼으며 Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-02: 설치본 후속 QA에서 WinUI 기본 `ToggleSwitch` 템플릿의 라이브러리 리소스가 앱 전역 override보다 우선되어 `내 펫` switch가 이전 회색을 유지하는 것을 확인했다. 카드 switch의 로컬 Default/Light theme resource에 fill·stroke·knob의 모든 상태를 직접 지정해 실제 template lookup 경계에서 색상을 고정하고, 상태 문구에는 20px 고정 line box와 2px 시각 보정을 적용해 switch track과의 광학 중심을 맞췄다. Debug 빌드가 경고·오류 없이 통과했다.
- 2026-09-02: 사용자 최종 확인과 릴리스 요청에 따라 Windows 새 기능선을 `1.6.0.15`, 태그 `windows-v1.6.0-preview.1`, 릴리스 이름 `MonglePet Windows 1.6.0 Preview 1`로 확정했다. 마케팅·Assembly·File·MSIX 버전과 배포 계약 테스트를 함께 승격했고 Debug·Release 각 Activity 27, Core 62, Packages 28, PetLibrary 89, Settings 82, Shell 20으로 총 308개 테스트와 두 구성 빌드가 경고·오류 없이 통과했다.
- 2026-09-02: 소스 커밋 `507400b`를 `origin/main`에 푸시하고 태그 `windows-v1.6.0-preview.1`, 제목 `MonglePet Windows 1.6.0 Preview 1`의 GitHub Pre-release를 게시했다. 65,284,653 bytes 미서명 x64 설치기의 SHA-256은 `30F0BA24866AA3970842EF037715DCED54788971A12A692F6DAEF45FC1E883EC`다. 기존 설치 위 업그레이드 종료 코드 0, 사용자 데이터 48개·5,826,673 bytes의 inventory digest `934FDC9C8AF2E5959E2A80F69A8B4A54E58C7BE2A4D32FE7B2B4F9ED8C38D049` 보존, 설치본 `1.6.0.15`·게시 DLL 일치와 실행 응답을 확인했다. 원격 설치기와 `SHA256SUMS.txt`를 다시 내려받아 크기·digest·체크섬과 Pre-release 상태를 검증했다.
- 2026-09-02: 공개 Preview 실제 QA에서 `fixed` 평상시 기본 행동이 첫 순환 뒤 정지하는 회귀를 확인했다. 현재 선택 펫은 `fixed`, 기본 행동 1개, 저장 `repeats: true`였으나 Windows runtime이 D-111에 따라 강제로 `Once`를 사용한 것이 직접 원인이었다. D-115로 평상시 fixed만 `RepeatWhileRequested`로 보정하고 랜덤 개별 행동·규칙·쓰다듬기의 1회 의미는 유지했다. C# `BehaviorPlaybackPolicy`와 fixed/random 정책 테스트를 추가했고 Core Debug 64개 테스트와 전체 Debug 빌드가 통과했다. macOS 후속 반영과 실제 장시간 확인은 남아 있다.
- 2026-09-02: D-115 Windows 핫픽스의 Debug·Release 빌드가 경고·오류 없이 통과했고 각 구성에서 Activity 27, Core 64, Packages 28, PetLibrary 89, Settings 82, Shell 20으로 총 310개 테스트가 모두 통과했다. 같은 Release publish의 DLL을 로컬 `1.6.0.15` 설치본과 일치시켜 다시 실행했으며, 실제 두 순환 이상 재생 확인과 새 설치 버전·릴리스 승격은 남아 있다.
- 2026-09-02: 마우스 도망가기의 평상시 자유 이동에서 무작위 머무르기가 꺼져 있어도 숨겨진 최소값을 최대값과 비교해 저장을 막는 Windows UI 회귀를 수정했다. 숨겨진 편집값은 무시하고 저장 최소값을 새 최대값 이하로 자동 보정하며, 무작위 범위를 켠 상태의 최소값도 최대값을 넘으면 즉시 맞춘다. 이동 오류 `InfoBar`는 카드 최하단에서 상단으로 옮기고 오류 발생 시 화면에 보이도록 요청한다. 정책 테스트 3개를 추가했고 Debug·Release 빌드와 각 구성 총 313개 테스트가 경고·오류·실패 없이 통과했다.
- 2026-09-02: 사용자 확인과 릴리스 요청에 따라 기존 Preview 1을 보존하는 Windows 핫픽스 버전을 `1.6.0.16`, 태그 `windows-v1.6.0-preview.2`, 릴리스 이름 `MonglePet Windows 1.6.0 Preview 2`로 확정했다. 마케팅 버전 `1.6.0`, schema-v15와 권장 프로필 v11은 유지한다.
- 2026-09-02: 실행 중 Preview 1 위 첫 설치 QA에서 Inno Setup Restart Manager가 앱 전용 종료 메시지보다 먼저 실패해 설치 코드 5를 반환하는 경로를 확인했다. 기본 자동 종료를 끄고 전용 종료·원자적 저장·overlay 해제를 최대 30초 기다리도록 보정했으며 Shell Debug·Release 계약 테스트를 통과했다. 최종 실행 중 앱 위 설치는 14.21초·종료 코드 0으로 완료됐고 사용자 데이터 48개·5,827,013 bytes의 inventory digest `4EC2A894F7D0F061448E8CE22D538F8FEC3EEBF7B996B452087632FD8D56DB52`, 설치본 `1.6.0.16`과 publish DLL 일치를 보존했다.
- 2026-09-02: 소스 커밋 `3f91dec335300f6d29af41046819a9fd48f58e8a`를 `origin/main`에 푸시하고 태그 `windows-v1.6.0-preview.2`, 제목 `MonglePet Windows 1.6.0 Preview 2`의 GitHub Pre-release를 게시했다. 65,279,431 bytes 미서명 x64 설치기의 SHA-256은 `228D1B459F6BA6A9E067294C35A2FDE0CEC9747299791C9F3785B302C594F6EA`다. 원격 설치기와 107 bytes `SHA256SUMS.txt`를 다시 내려받아 크기·digest·체크섬과 태그 대상 커밋 일치를 확인했다.
- 2026-09-02: macOS에 D-115 문맥별 재생 정책을 반영했다. 평상시 fixed와 직접 선택은 행동 전체를 계속 순환하고, 랜덤의 개별 행동·조건 규칙·쓰다듬기는 한 번 통과하며, 이동 행동은 실제 이동 runtime에서만 반복한다. 저장 `repeats`, schema-v15, 권장 프로필 v11은 변경하지 않았다. 관련 runtime 42개와 머무는 시간·설정 migration 회귀 26개, 전체 `MonglePetTests` 536개 중 535개 통과·조건부 fixture 1개 skip, Debug 빌드와 `git diff --check`를 통과했다. 실제 앱에서 두 순환 이상 재생, 규칙 마지막 프레임 유지, 외부 앱 창 드래그와 장시간 runtime QA는 남아 있다.
- 2026-09-02: 사용자가 macOS 실제 앱에서 D-115 행동 순환과 설정창 사용을 다시 확인해 현재 범위의 이상이 없음을 승인했다. 설정창은 실시간 좌표·프레임을 구독하거나 반복 활성화하지 않는 구조임을 확인했고 외부 앱 드래그 문제는 재현되지 않아 이번 범위에서는 완료 처리한다. 새 배포 후보는 기존 Preview 1을 보존하는 `1.6.0 (13)`, 태그 `macos-v1.6.0-preview.2`로 분리한다.

## 남은 위험

- 알파 마스크는 성능을 위해 최대 64px로 축소되므로 매우 가는 장식 픽셀의 경계는 근사값이다.
- child window의 AppKit 자동 이동과 경계 보정 조합은 실제 빠른 이동에서 시각 QA가 필요하다.
- legacy orphan을 일괄 복구할 때 많은 펫이 잠든 상태로 목록에 추가될 수 있어 대량 항목의 정렬·검색은 후속 UX가 필요할 수 있다.
- Windows DPI 변환과 XAML Island 측정은 macOS 좌표 계산을 직역하지 않고 별도 검증해야 한다.
