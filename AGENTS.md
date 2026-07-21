# MonglePet Project Instructions

## 역할

이 파일은 MonglePet 프로젝트에서 Codex가 가장 먼저 확인하는 최상위 작업 지침이자 문서 라우터다.

프로젝트 전체에 공통으로 적용되는 원칙만 이곳에 유지한다. 제품, 아키텍처, 테스트, 개별 기능의 상세 내용은 `AGENTS/` 아래 문서에서 관리하며, 작업을 시작하기 전에 아래 문서 라우팅 표에서 관련 문서를 선택해 읽는다.

## 프로젝트 소개

MonglePet은 macOS 데스크톱 위에 반려 캐릭터를 표시하고 사용자의 설정과 작업 상황에 따라 애니메이션을 전환하는 네이티브 데스크톱 펫 애플리케이션이다.

사용자는 펫을 깨우거나 재우고 자동 또는 수동 행동 모드를 선택할 수 있다. 자동 모드에서는 현재 사용 중인 앱과 유휴 시간을 바탕으로 행동을 결정하고, 수동 모드에서는 사용자가 구성한 모션 목록을 지정된 시간 동안 반복한다.

외부 펫은 데이터 전용 `.monglepet` 패키지와 지원 이미지 형식으로 등록할 수 있다. 사용자 활동 정보는 행동 결정에 필요한 최소 범위만 기기 안에서 사용하며 실제 키 입력, 화면 내용, 창 제목은 수집하지 않는다.

## 프로젝트 기본 정보

- 제품명: **MonglePet** / **몽글펫**
- 기본 캐릭터: **몽글이**
- 초기 플랫폼: **macOS 14 이상**
- 언어: **Swift 6**
- UI 및 시스템 연동: **SwiftUI, AppKit, Core Animation**
- 테스트: **XCTest, XCUITest**
- Bundle Identifier: `kr.mapleroom.MonglePet`
- 저장 방식: SwiftData를 사용하지 않는 버전이 지정된 JSON 및 파일 기반 로컬 저장소
- 후속 플랫폼: macOS 버전 안정화 후 Windows 앱을 별도 개발

## 핵심 개발 원칙

- macOS 네이티브 기술을 우선하고 Electron, WebView, Unity 같은 상시 실행 런타임을 사용하지 않는다.
- 도메인 로직은 AppKit과 파일 시스템에서 분리해 단위 테스트할 수 있게 만든다.
- 상시 실행 앱에 맞게 CPU, 메모리, 불필요한 프레임 갱신을 최소화한다.
- 사용자 활동 정보는 로컬에서 필요한 최소 범위만 처리한다.
- 외부 펫 패키지에는 이미지와 JSON 데이터만 허용하고 실행 코드나 스크립트를 허용하지 않는다.
- 유사 프로젝트는 기능과 UX 참고 자료로만 사용하고 소스 코드나 저장소 구조를 복사하지 않는다.
- Windows 구현과 공유할 부분은 데이터 스키마와 테스트 시나리오로 제한한다.

## 문서 라우팅

| 작업 유형 | 먼저 읽을 문서 |
| --- | --- |
| 전체 문서 위치와 상태 확인 | `AGENTS/INDEX.md` |
| 제품 목표, 기능 범위, 개인정보 원칙 판단 | `AGENTS/project/PRODUCT.md` |
| 구조 설계, 계층 분리, 저장소 구현 | `AGENTS/project/ARCHITECTURE.md` |
| 다음 개발 단계와 완료 조건 확인 | `AGENTS/project/ROADMAP.md` |
| 테스트 작성, 빌드 검증, 성능 QA | `AGENTS/project/TESTING.md` |
| 확정된 기술·제품 결정 확인 | `AGENTS/project/DECISIONS.md` |
| 자동·수동 행동 엔진 작업 | `AGENTS/specifications/BEHAVIOR_MODEL.md` |
| 펫 등록, 패키지, 가져오기 작업 | `AGENTS/specifications/PET_PACKAGE.md` |
| 설정 저장, 복원, 스키마 마이그레이션 | `AGENTS/specifications/SETTINGS_SCHEMA.md` |
| 큰 기능, 다중 파일 변경, 장기 작업 | `AGENTS/guides/DEVELOPMENT_WORKFLOW.md`와 `AGENTS/work_plans/INDEX.md` |

## 작업 규칙

1. 작업 시작 전에 이 파일과 작업 유형에 해당하는 문서를 읽는다.
2. 상세 규격과 코드가 다르면 임의로 한쪽을 맞추지 말고 차이를 알린 뒤 작업 범위를 결정한다.
3. 기존 사용자 변경과 관련 없는 작업 트리 변경을 보존한다.
4. 제품 동작이나 범위가 달라지는 결정은 `AGENTS/project/DECISIONS.md`에 기록한다.
5. 큰 작업은 `AGENTS/guides/DEVELOPMENT_WORKFLOW.md`에 따라 작업 계획을 만들거나 기존 계획을 갱신한다.
6. 명세를 추가하거나 이동하면 `AGENTS/INDEX.md`와 이 파일의 문서 라우팅을 함께 확인한다.
7. 코드 변경 후 가장 좁은 관련 테스트부터 실행하고 필요에 따라 전체 빌드와 UI 테스트로 확장한다.
8. 앱 코드는 사용자가 구현이나 수정을 요청했을 때 변경한다. 검토 요청은 읽기와 분석을 우선한다.

## 기본 검증 명령

Debug 빌드:

```sh
xcodebuild -project MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

단위 테스트:

```sh
xcodebuild -project MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:MonglePetTests
```

UI 테스트는 실제 앱 실행 환경이 필요하므로 관련 UI 변경이나 릴리스 검증 시 실행한다. 자세한 기준은 `AGENTS/project/TESTING.md`를 따른다.
