# MonglePet macOS Instructions

## 적용 범위

이 파일은 `apps/macos/` 아래의 macOS 앱, 테스트와 배포 자동화 작업에 적용한다. 저장소 공통 원칙과 제품·패키지 명세는 루트 `../../AGENTS.md`와 `../../AGENTS/` 문서를 먼저 따른다.

## 플랫폼 기준

- 최소 지원 버전: macOS 14 이상
- 언어: Swift 6
- UI와 시스템 연동: SwiftUI, AppKit, Core Animation
- 테스트: XCTest, XCUITest
- Bundle Identifier: `kr.mapleroom.MonglePet`
- 프로젝트: `MonglePet.xcodeproj`

## 작업 원칙

- 투명 오버레이, 상태 메뉴와 시스템 감지는 공개 macOS API로 구현한다.
- Domain과 시간 기반 행동 로직은 AppKit·SwiftUI에서 분리한다.
- 화면 잠금·절전·펫 숨김 상태에서는 불필요한 timer와 렌더링을 중지한다.
- 설정과 펫 라이브러리는 버전이 지정된 JSON·파일 저장소를 사용한다.
- 플랫폼 공통으로 유지할 수 있는 변경은 `.monglepet` 규격과 fixture에서 검증하고 Swift 소스 자체를 Windows와 공유하지 않는다.
- 신규 기능과 수정은 macOS에서 먼저 구현·검증해 제품 기준을 확정한다.
- 기능 완료 시 루트 `../../AGENTS/project/PLATFORM_PARITY.md`에서 macOS 상태와 Windows 후속 범위를 갱신한다.
- 공통 schema에 AppKit 타입, Bundle Identifier, 화면 UUID와 macOS 파일 경로를 노출하지 않는다.

## 기본 검증

저장소 루트에서 Debug 빌드:

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

저장소 루트에서 단위 테스트:

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:MonglePetTests
```

배포 절차는 `DISTRIBUTION.md`, 자동화는 `Scripts/`를 따른다.
