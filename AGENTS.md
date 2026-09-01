# MonglePet Project Instructions

## 역할

이 파일은 MonglePet 프로젝트에서 Codex가 가장 먼저 확인하는 최상위 작업 지침이자 문서 라우터다.

프로젝트 전체에 공통으로 적용되는 원칙만 이곳에 유지한다. 제품, 아키텍처, 테스트, 개별 기능의 상세 내용은 `AGENTS/` 아래 문서에서 관리하며, 작업을 시작하기 전에 아래 문서 라우팅 표에서 관련 문서를 선택해 읽는다.

## 프로젝트 소개

MonglePet은 데스크톱 위에 반려 캐릭터를 표시하고 사용자의 설정과 작업 상황에 따라 애니메이션을 전환하는 네이티브 데스크톱 펫 애플리케이션이다. 현재 macOS 앱을 먼저 개발하고 있으며 Windows 앱은 같은 저장소의 독립 네이티브 프로젝트로 후속 구현한다.

사용자는 펫을 깨우거나 재우고 자동 또는 수동 행동 모드를 선택할 수 있다. 자동 모드에서는 현재 사용 중인 앱과 유휴 시간을 바탕으로 행동을 결정하고, 수동 모드에서는 현재 펫에 맞게 구성한 애니메이션 목록을 반복한다.

외부 펫은 데이터 전용 `.monglepet` 패키지와 지원 이미지 형식으로 등록할 수 있다. 사용자 활동 정보는 행동 결정에 필요한 최소 범위만 기기 안에서 사용하며 실제 키 입력, 화면 내용, 창 제목은 수집하지 않는다.

## 프로젝트 기본 정보

- 제품명: **MonglePet** / **몽글펫**
- 기본 캐릭터: **몽글이**
- 현재 플랫폼: **macOS 14 이상**
- macOS: **Swift 6, SwiftUI, AppKit, Core Animation, XCTest, XCUITest**
- macOS Bundle Identifier: `kr.mapleroom.MonglePet`
- Windows: **C#, .NET, WinUI 3**, 펫 오버레이는 별도 Win32 `HWND`와 `Microsoft.UI.Composition` 사용
- 저장 방식: SwiftData를 사용하지 않는 버전이 지정된 JSON 및 파일 기반 로컬 저장소
- 저장소 구조: `apps/macos`, `apps/windows`, `shared`

## 핵심 개발 원칙

- 각 플랫폼의 네이티브 기술을 우선하고 Electron, WebView, Unity 같은 상시 실행 런타임을 사용하지 않는다.
- 도메인 로직은 플랫폼 UI와 파일 시스템에서 분리해 단위 테스트할 수 있게 만든다.
- 상시 실행 앱에 맞게 CPU, 메모리, 불필요한 프레임 갱신을 최소화한다.
- 사용자 활동 정보는 로컬에서 필요한 최소 범위만 처리한다.
- 외부 펫 패키지에는 이미지와 JSON 데이터만 허용하고 실행 코드나 스크립트를 허용하지 않는다.
- 유사 프로젝트는 기능과 UX 참고 자료로만 사용하고 소스 코드나 저장소 구조를 복사하지 않는다.
- 플랫폼 간 공유는 `.monglepet` 규격, 데이터 스키마, fixture와 테스트 시나리오로 제한한다.
- macOS와 Windows 앱은 독립적인 프로젝트·소스·배포 체계를 유지한다.

## 플랫폼별 개발 순서

신규 기능과 수정은 원칙적으로 `공통 계약 → macOS 구현 → Windows 인계 → Windows 구현 → 플랫폼 동등성 검증` 순서로 진행한다.

1. 제품 규칙과 공통 데이터 변경 여부를 먼저 확정한다.
2. macOS 환경에서 macOS 구현과 필수 자동 테스트·실제 앱 QA를 완료한다.
3. macOS 기준 동작이 확정되면 공통 schema, fixture, 호환성 시나리오와 Windows 인계 항목을 갱신한다.
4. Windows 앱의 소스 변경, 빌드와 테스트는 Windows 환경에서 진행한다.
5. 두 플랫폼의 공통 fixture·사용자 시나리오·플랫폼별 실제 앱 QA가 완료된 뒤 기능을 동등 완료로 표시한다.

큰 기능의 작업 계획은 `공통 계약`, `macOS`, `Windows`, `플랫폼 동등성` 단계를 구분한다. 구체적인 체크리스트와 진행 로그는 기능별 작업 계획에, 전체 기능 현황은 `AGENTS/project/PLATFORM_PARITY.md`에 기록한다.

## 문서 라우팅

| 작업 유형 | 먼저 읽을 문서 |
| --- | --- |
| 전체 문서 위치와 상태 확인 | `AGENTS/INDEX.md` |
| 제품 목표, 기능 범위, 개인정보 원칙 판단 | `AGENTS/project/PRODUCT.md` |
| 구조 설계, 계층 분리, 저장소 구현 | `AGENTS/project/ARCHITECTURE.md` |
| 다음 개발 단계와 완료 조건 확인 | `AGENTS/project/ROADMAP.md` |
| macOS 우선 개발과 Windows 기능 동등성 현황 | `AGENTS/project/PLATFORM_PARITY.md` |
| 테스트 작성, 빌드 검증, 성능 QA | `AGENTS/project/TESTING.md` |
| 확정된 기술·제품 결정 확인 | `AGENTS/project/DECISIONS.md` |
| 자동·수동 행동 엔진 작업 | `AGENTS/specifications/BEHAVIOR_MODEL.md` |
| 펫 등록, 패키지, 가져오기 작업 | `AGENTS/specifications/PET_PACKAGE.md` |
| 설정 저장, 복원, 스키마 마이그레이션 | `AGENTS/specifications/SETTINGS_SCHEMA.md` |
| 큰 기능, 다중 파일 변경, 장기 작업 | `AGENTS/guides/DEVELOPMENT_WORKFLOW.md`와 `AGENTS/work_plans/INDEX.md` |
| 웹 펫 공유 커뮤니티 설계·인계 | `AGENTS/guides/WEB_COMMUNITY_HANDOFF.md`와 `AGENTS/guides/WEB_COMMUNITY_SERVER_PROMPT.md` |
| 웹 URL 펫 가져오기 Windows 인계 | `AGENTS/guides/WINDOWS_WEB_PET_IMPORT_HANDOFF.md`, `AGENTS/specifications/PET_PACKAGE.md`와 `apps/windows/AGENTS.md` |
| macOS 1.3 편집기·호환성·내장 펫 Windows 인계 | `AGENTS/guides/WINDOWS_MACOS_1_3_HANDOFF.md`, `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md`와 `apps/windows/AGENTS.md` |
| 행동 중심 설정·런타임 Windows 인계 | `AGENTS/guides/WINDOWS_BEHAVIOR_CENTRIC_HANDOFF.md`, `AGENTS/specifications/BEHAVIOR_MODEL.md`, `AGENTS/specifications/SETTINGS_SCHEMA.md`와 `apps/windows/AGENTS.md` |
| 내 펫 통합·행동 1회 재생·말풍선 보정 Windows 인계 | `AGENTS/guides/WINDOWS_MY_PETS_RUNTIME_POLISH_HANDOFF.md`, `AGENTS/specifications/BEHAVIOR_MODEL.md`, `AGENTS/specifications/PET_PACKAGE.md`와 `apps/windows/AGENTS.md` |
| 데스크톱 펫·설치한 펫 UX Windows 인계 | `AGENTS/guides/WINDOWS_DESKTOP_PET_LIBRARY_HANDOFF.md`, `AGENTS/specifications/PET_PACKAGE.md`, `AGENTS/specifications/SETTINGS_SCHEMA.md`와 `apps/windows/AGENTS.md` |
| Windows 선반영 펫 제작기 결과의 macOS 후속 작업 | `AGENTS/guides/MACOS_PET_EDITOR_FOLLOWUP.md`, `AGENTS/specifications/PET_PACKAGE.md`와 `apps/macos/AGENTS.md` |
| 내장 몽글이 Windows 인계 | `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_HANDOFF.md`, `AGENTS/guides/WINDOWS_BUILTIN_MONGLE_PROMPT.md`와 `apps/windows/AGENTS.md` |
| macOS 앱, Xcode, 배포 자동화 | `apps/macos/AGENTS.md` |
| Windows 앱 설계·구현 | `apps/windows/AGENTS.md` |
| 플랫폼 공통 샘플·fixture | `shared/README.md` |

## 작업 규칙

1. 작업 시작 전에 이 파일과 작업 유형에 해당하는 문서를 읽는다.
2. 상세 규격과 코드가 다르면 임의로 한쪽을 맞추지 말고 차이를 알린 뒤 작업 범위를 결정한다.
3. 기존 사용자 변경과 관련 없는 작업 트리 변경을 보존한다.
4. 제품 동작이나 범위가 달라지는 결정은 `AGENTS/project/DECISIONS.md`에 기록한다.
5. 큰 작업은 `AGENTS/guides/DEVELOPMENT_WORKFLOW.md`에 따라 작업 계획을 만들거나 기존 계획을 갱신한다.
6. 명세를 추가하거나 이동하면 `AGENTS/INDEX.md`와 이 파일의 문서 라우팅을 함께 확인한다.
7. 코드 변경 후 가장 좁은 관련 테스트부터 실행하고 필요에 따라 전체 빌드와 UI 테스트로 확장한다.
8. 앱 코드는 사용자가 구현이나 수정을 요청했을 때 변경한다. 검토 요청은 읽기와 분석을 우선한다.
9. 신규 기능과 수정은 위의 플랫폼별 개발 순서를 따르며 macOS 기준 동작을 먼저 확정한다.
10. macOS 완료 시 공통 규격·fixture·Windows 인계 항목을 정리하고, Windows 소스 변경과 검증은 Windows 환경에서 수행한다.
11. macOS 기능을 완료하거나 Windows에 반영하면 `AGENTS/project/PLATFORM_PARITY.md`의 진행 현황을 함께 갱신한다.
12. Windows 구현과 실제 Windows QA가 끝나기 전에는 해당 기능을 플랫폼 동등 완료로 표시하지 않는다.

## 기본 검증 명령

Debug 빌드:

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

단위 테스트:

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:MonglePetTests
```

UI 테스트는 실제 앱 실행 환경이 필요하므로 관련 UI 변경이나 릴리스 검증 시 실행한다. 자세한 기준은 `AGENTS/project/TESTING.md`를 따른다.
