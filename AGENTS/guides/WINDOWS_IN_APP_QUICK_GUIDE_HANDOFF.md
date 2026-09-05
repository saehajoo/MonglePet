# Windows 앱 내 간단 이용 가이드 인계

## 상태와 목적

- 상태: macos_implementation_complete_qa_pending
- 기준일: 2026-09-05
- 기준 결정: D-123
- macOS 기준 화면: `apps/macos/MonglePet/Settings/MonglePetQuickGuideView.swift`
- 관련 작업 계획: `AGENTS/work_plans/tasks/2026-09-05-in-app-quick-guide.md`
- 목적: 웹 설명서를 앱에 복제하지 않고 Windows 사용자도 앱 안에서 첫 작업 순서와 핵심 용어를 빠르게 이해하도록 한다.

이 작업은 Windows 소스에서 별도로 구현한다. SwiftUI 코드를 XAML로 직역하지 말고 기존 WinUI 3 `NavigationView`, grouped card, Mica, 테마와 반응형 배치 안에서 같은 사용자 결과를 제공한다.

## 작업 전 확인

Windows 작업 공간에서 다음을 먼저 읽는다.

1. 루트 `AGENTS.md`
2. `apps/windows/AGENTS.md`
3. `AGENTS/project/DECISIONS.md`의 D-123
4. `AGENTS/project/PLATFORM_PARITY.md`의 앱 내 이용 가이드 항목
5. 이 문서
6. `apps/windows/src/MonglePet.Windows/MainPage.xaml`
7. `apps/windows/src/MonglePet.Windows/MainPage.xaml.cs`

기존 사용자 변경을 보존하고 Windows 작업 계획을 만들거나 갱신한 뒤 구현한다. macOS 작업 공간에서는 Windows 소스를 변경하거나 Windows 빌드 결과를 완료로 추정하지 않는다.

## 확정된 사용자 결과

### 진입점

- 설정 `NavigationView`의 기존 `지원` 그룹에 `이용 가이드`를 추가한다.
- 순서는 `이용 가이드` 다음 `문제 해결`이다.
- `문제 해결`은 안전 시작과 복구를 위한 저빈도 기능이므로 가이드와 합치거나 이름을 바꾸지 않는다.
- 설정의 다른 페이지에서도 가이드를 쉽게 다시 열 수 있는 도움말 버튼을 하나 제공한다.
  - Windows에서는 설정 content header 오른쪽이나 title bar의 작은 `Help` 아이콘 버튼을 권장한다.
  - NavigationView가 compact 상태여도 키보드와 Narrator로 버튼을 찾을 수 있어야 한다.
- 첫 실행 시 가이드를 강제로 띄우거나 완료 여부를 저장하지 않는다.

### 가이드의 정보 구조

가이드는 다음 네 영역을 이 순서로 표시한다.

1. 짧은 소개
2. `빠르게 시작하기` 5단계
3. `헷갈리기 쉬운 말`
4. `웹 가이드 보기`

가이드는 긴 설명서가 아니다. 한 화면에서 구조를 훑을 수 있게 카드와 짧은 문장을 사용하고, 제작 세부사항은 외부 웹 가이드로 보낸다.

## 표시 문구

### 소개

- 제목: `MonglePet 시작하기`
- 설명: `펫을 추가한 뒤 애니메이션과 행동을 준비하고, 화면 표시·이동·규칙을 원하는 방식으로 설정해 보세요.`
- 안내: `각 펫의 행동, 이동, 말풍선과 화면 설정은 서로 독립적으로 저장됩니다.`

### 빠르게 시작하기

#### 1. 펫 준비하기

- 설명: `내 펫에서 새 펫을 만들거나 파일·웹 주소로 가져옵니다. 사용할 펫을 고르고 깨우기와 재우기도 이곳에서 관리합니다.`
- 바로가기: `내 펫 열기`
- 대상 section tag: `activePets`

#### 2. 애니메이션과 행동 만들기

- 설명: `먼저 이미지 프레임으로 애니메이션을 준비한 다음, 하나 이상의 애니메이션 단계를 묶어 실제 행동을 만듭니다.`
- 바로가기: `애니메이션 열기` → `pet`
- 바로가기: `행동 편집 열기` → `routines`

#### 3. 평상시 행동과 규칙 정하기

- 설명: `다른 조건이 없을 때 보여 줄 평상시 행동을 고릅니다. 입력 없음이나 특정 앱 사용 중에 다른 행동을 보여 주려면 규칙을 추가합니다.`
- 바로가기: `평상시 행동 열기` → `stationary`
- 바로가기: `규칙 설정 열기` → `automaticRules`

#### 4. 보이는 모습과 움직임 꾸미기

- 설명: `크기와 투명도, 이동 방식과 범위, 쓰다듬기 반응 및 말풍선을 선택한 펫에 맞게 조정합니다.`
- 바로가기: `화면 표시` → `display`
- 바로가기: `이동` → `movement`
- 바로가기: `상호작용` → `interaction`
- 바로가기: `말풍선` → `speech`

#### 5. 완성한 펫 보관하고 공유하기

- 설명: `내 펫에서 패키지 파일로 저장하면 펫 이미지와 제작자가 구성한 휴대 가능한 설정을 함께 공유할 수 있습니다.`
- 바로가기: `내 펫에서 내보내기` → `activePets`
- 바로가기는 내보내기 dialog를 자동으로 열지 않는다. 대상 펫 카드에서 사용자가 펫과 작업을 다시 확인한 뒤 실행하게 한다.

### 헷갈리기 쉬운 말

- `애니메이션`: `이미지 프레임이 순서대로 재생되는 화면 표현입니다.`
- `행동`: `하나 이상의 애니메이션 단계를 순서와 반복 횟수로 묶은 동작입니다.`
- `평상시 행동`: `이동하지 않고 적용할 조건 규칙이 없을 때 계속 보여 주는 기본 행동입니다.`
- `규칙`: `입력 없음이나 사용 중인 앱 같은 조건이 맞을 때 평상시 행동보다 먼저 적용됩니다.`
- `제작자 설정`: `가져온 펫에 포함된 행동·이동·말풍선 설정이며 추가한 뒤 자유롭게 바꿀 수 있습니다.`

위 문구의 사용자 의미를 유지한다. Windows control 폭 때문에 임의로 핵심 조건을 삭제하지 말고 `TextWrapping="Wrap"`과 반응형 배치를 사용한다.

### 웹 가이드

- 제목: `더 자세한 제작 방법이 필요하신가요?`
- 설명: `이미지 준비, 펫 제작과 공유에 관한 자세한 설명은 웹 가이드에서 확인할 수 있습니다.`
- 버튼: `웹 가이드 보기`
- Debug·Release 공통 고정 URL: `https://mapleroom.kr/monglepet/guide`
- 사용자가 버튼을 눌렀을 때만 `Windows.System.Launcher.LaunchUriAsync`로 기본 브라우저를 연다.
- 앱 시작이나 가이드 진입만으로 웹 요청, 사전 로드, WebView 생성 또는 분석 event를 보내지 않는다.
- 실행 결과가 `false`이거나 예외가 발생하면 가이드 안의 `InfoBar`로 `웹 가이드를 열 수 없습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.`를 표시한다.

## Windows 구현 기준

### NavigationView와 표시 상태

- `MainPage.xaml`의 `지원` header 아래에 `NavigationViewItem Content="이용 가이드" Tag="guide"`를 `문제 해결`보다 먼저 추가한다.
- 아이콘은 WinUI `SymbolIcon Symbol="Help"` 또는 현재 디자인 체계에 맞는 도움말 아이콘을 사용한다.
- `ShowSettingsSection("guide")`에서 가이드 panel만 표시하고 기존 설정·펫 card는 숨긴다.
- `SettingsSectionTitle`은 `이용 가이드`, 설명은 `처음 시작하는 순서와 애니메이션·행동·규칙의 차이를 확인합니다.`로 표시한다.
- 가이드 바로가기 버튼은 기존 `ShowSettingsSection` 경계만 호출한다. 선택 펫, active instance, profile, overlay와 runtime을 다시 로드하거나 저장하지 않는다.
- 가이드에서 다른 목적지로 이동한 뒤 브라우저 뒤로가기 같은 별도 history stack은 만들지 않는다. 기존 NavigationView의 현재 선택만 정확히 동기화한다.

### 반응형 배치

- 기존 `SettingsContentGrid`와 `SettingsCardStyle`·`SettingsSubcardStyle`을 재사용한다.
- 5단계 카드는 번호, 제목, 설명, 바로가기 순서의 동일한 시각 계층을 사용한다.
- 용어 카드는 넓은 창에서는 2열, compact 창에서는 1열로 바뀌게 한다.
- 바로가기 버튼은 넓은 창에서는 가로 배치하고 공간이 부족하면 줄바꿈하거나 세로 배치한다. 가로 ScrollViewer는 만들지 않는다.
- 기존 최소 설정창 크기 `800×600` effective pixel, 100%·150%·200% DPI와 NavigationView compact 상태에서 내용과 웹 버튼이 잘리지 않아야 한다.
- Dark·Light·High Contrast에서 플랫폼 테마 리소스를 사용하고 macOS 색상값이나 SwiftUI material을 복사하지 않는다.

### 접근성

- NavigationView item의 접근성 이름은 `이용 가이드`다.
- 상시 도움말 버튼은 `AutomationProperties.Name="이용 가이드 열기"`와 tooltip을 제공한다.
- 단계 번호만 장식용이면 접근성 트리에서 제외하고 제목과 설명을 한 번만 읽게 한다.
- 모든 바로가기 버튼은 화면 문구 그대로 고유한 접근성 이름을 가진다.
- 웹 버튼은 외부 브라우저가 열린다는 사실을 이름 또는 도움말에서 알 수 있게 한다.
- Tab 순서는 소개 → 단계별 바로가기 → 용어 → 웹 버튼의 시각 순서와 일치해야 한다.
- Narrator에서 `애니메이션`과 `행동` 설명이 서로 합쳐지거나 단계 번호만 읽히지 않는지 확인한다.

## 변경하지 않을 항목

- 로컬 settings schema-v16
- 제작자 설정 schema-v12
- `.monglepet` manifest formatVersion과 package 내용
- 선택 펫, active instance, profile과 overlay 저장 구조
- 기존 `문제 해결`의 안전 모드·복원 기능
- 앱 자동 업데이트와 웹 콘텐츠
- notification area 메뉴
- macOS SwiftUI layout과 색상값

가이드 방문 여부, 마지막 단계와 스크롤 위치를 settings JSON이나 package에 추가하지 않는다. 추후 첫 실행 온보딩이 필요하면 별도 제품 결정과 접근성·건너뛰기 정책을 먼저 확정한다.

## 권장 변경 파일

- `apps/windows/src/MonglePet.Windows/MainPage.xaml`
  - NavigationView item
  - 상시 도움말 버튼
  - `QuickGuideCard`와 단계·용어·웹 InfoBar
- `apps/windows/src/MonglePet.Windows/MainPage.xaml.cs`
  - `guide` section visibility와 제목·설명
  - 목적지 바로가기 handler
  - Debug/Release 웹 URL과 `LaunchUriAsync` 오류 처리
- Windows Settings/Shell 테스트 프로젝트
  - navigation·문구·URL·저장 비변경 계약

실제 구조가 이미 분리되어 있다면 전용 `QuickGuideView` 또는 `UserControl`을 만들어도 된다. 다만 가이드 UI가 런타임·settings store를 구독하거나 계속 갱신하지 않게 한다.

## 필수 자동 검증

1. `지원` 그룹에 `이용 가이드`와 `문제 해결`이 이 순서로 존재한다.
2. `guide` 선택 시 가이드만 보이고 안전 모드 panel이 보이지 않는다.
3. 상시 도움말 버튼과 모든 바로가기가 올바른 section tag를 선택한다.
4. Debug·Release 모두 고정 운영 URL `https://mapleroom.kr/monglepet/guide`를 사용하며 package 또는 사용자 입력 URL을 사용하지 않는다.
5. 웹 실행 실패와 예외가 비차단 InfoBar로 표시된다.
6. 가이드 진입과 바로가기 이동이 settings store 저장을 호출하지 않는다.
7. 가이드 관련 XAML text가 wrap되고 가로 scroll을 요구하지 않는다.
8. 기존 전체 Windows Debug·Release xUnit 테스트와 두 구성 빌드를 실행한다.
9. `git diff --check`를 실행한다.

## 실제 Windows QA

- expanded·compact NavigationView에서 가이드 진입과 선택 표시 확인
- 상단 도움말 버튼으로 어느 설정 화면에서든 가이드 재진입
- 5단계 바로가기 전체 왕복과 올바른 설정 대상 유지
- 내 펫 바로가기에서 기존 선택 펫·별칭·깨움 상태가 바뀌지 않음
- Debug·Release 모두 고정 운영 가이드 URL이 기본 브라우저에서 열림
- 기본 브라우저 연결이 없거나 실행이 거부될 때 InfoBar 표시
- 800×600과 넓은 창, 100%·150%·200% DPI에서 잘림·가로 스크롤 없음
- Dark·Light·High Contrast에서 텍스트·번호·테두리·focus visual 대비
- 키보드만으로 sidebar, 상단 도움말, 모든 바로가기와 웹 버튼 조작
- Narrator가 제목·설명·버튼을 중복 없이 자연스러운 순서로 읽음
- 가이드 화면을 열어 둔 동안 펫 이동·애니메이션 때문에 focus나 scroll 위치가 갱신되지 않음
- `문제 해결` 안전 시작 기능과 visibility에 회귀가 없음

## 완료 보고 형식

Windows 구현 완료 보고에는 다음을 구분해 기록한다.

- 변경한 XAML·code-behind 또는 전용 view 구조
- `이용 가이드`와 `문제 해결`의 분리 결과
- 상시 도움말과 각 바로가기 결과
- 고정 운영 웹 URL과 실패 처리 결과
- 설정·schema·runtime 비변경 확인
- 자동 테스트 통과 개수와 Debug·Release 빌드 결과
- DPI·테마·키보드·Narrator 실제 QA 결과
- 남은 위험
- git status와 커밋·푸시 상태

Windows 실제 구현과 QA가 끝나기 전에는 `PLATFORM_PARITY.md`에서 이 기능을 동등 완료로 표시하지 않는다.
