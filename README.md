# MonglePet

MonglePet(몽글펫)은 데스크톱 위에서 움직이는 반려 캐릭터를 표시하는
네이티브 데스크톱 펫 프로젝트입니다. 현재 macOS 메뉴 막대 앱을 먼저
개발하고 있으며 기능과 배포 절차를 검증하는 **Preview** 단계입니다.
Windows 앱은 같은 저장소에서 독립적인 네이티브 프로젝트로 후속 개발합니다.

## 주요 기능

- 펫 깨우기·재우기와 크기, 투명도, 클릭 통과 설정
- 고정, 마우스 따라가기, 자유 이동 모드
- 사용 중인 앱과 유휴 시간에 반응하는 자동 행동
- 원하는 애니메이션을 반복하는 수동 행동
- 펫별 행동·이동 프로필과 다중 디스플레이 경계 설정
- `.monglepet`, Codex 호환 패키지, GIF, APNG, PNG 시퀀스 가져오기
- 편집한 펫을 데이터 전용 `.monglepet` 패키지로 내보내기
- 로그인 시 자동 실행

MonglePet은 Dock 아이콘 없이 메뉴 막대에서 실행됩니다. 앱 메뉴의 설정에서
펫과 행동, 이동 방식을 관리할 수 있습니다.

## 현재 macOS 시스템 요구사항

- macOS 14 Sonoma 이상
- Apple silicon 또는 Intel Mac

## 설치

### 공증된 DMG

릴리스 설명에 **Developer ID 서명 및 Apple 공증 완료**라고 표시된 경우:

1. DMG와 함께 제공된 SHA-256 체크섬을 확인합니다.
2. DMG를 열고 `MonglePet.app`을 `Applications` 폴더로 드래그합니다.
3. 응용 프로그램 폴더에서 MonglePet을 실행합니다.

### 미서명 Preview ZIP

릴리스 설명에 **미서명·미공증 Preview**라고 표시된 파일은 제한된 테스트
목적으로만 사용합니다.

1. ZIP과 함께 제공된 SHA-256 체크섬을 확인하고 압축을 풉니다.
2. `MonglePet.app`을 응용 프로그램 폴더로 옮긴 뒤 실행합니다.
3. macOS가 개발자를 확인할 수 없다고 차단하면 시스템 설정의
   **개인정보 보호 및 보안**에서 해당 앱의 **확인 없이 열기**를 선택합니다.

Gatekeeper를 끄거나 다운로드 격리 속성을 제거하는 명령은 사용하지 않습니다.
출처와 체크섬을 확인할 수 없는 빌드는 실행하지 마세요.

## 개인정보 보호

MonglePet은 행동 결정을 위해 다음 정보만 기기 안에서 일시적으로 사용합니다.

- 현재 사용 중인 앱의 Bundle Identifier
- 사용자 유휴 시간과 잠금·잠자기·깨우기 상태
- 마우스 따라가기 중인 현재 포인터 위치
- 자유 이동 경계를 계산하기 위한 현재 전면 창의 대표 영역

키 입력 내용, 화면 내용, 창 제목, 문서명, 브라우저 URL, 포인터 이동 기록이나
창 위치 기록은 수집하거나 저장하지 않습니다. 현재 Preview에는 분석 도구,
클라우드 동기화 또는 네트워크 전송 기능이 없습니다. 설정과 설치한 펫은
버전이 지정된 JSON과 파일 형태로 로컬에 저장됩니다.

## 펫 패키지

`.monglepet`은 이미지와 JSON 데이터만 포함하는 디렉터리 또는 ZIP 기반
패키지입니다. 실행 코드나 스크립트는 허용하지 않습니다. 패키지 구조와
호환성 규칙은 [PET_PACKAGE.md](AGENTS/specifications/PET_PACKAGE.md)를
참고하세요.

저장소의 `shared/Samples/ReadOnlySample.monglepet`은 가져오기 검증용 테스트
샘플이며 배포용 펫이 아닙니다.

## 저장소 구조

```text
MonglePet/
├── apps/
│   ├── macos/       # 현재 Swift·AppKit 앱
│   └── windows/     # 후속 Windows 네이티브 앱
├── shared/          # 공통 패키지 샘플과 향후 schema fixture
├── AGENTS/          # 제품·아키텍처·명세·작업 계획
└── AGENTS.md        # 저장소 공통 작업 지침
```

두 플랫폼은 UI와 운영체제 연동 코드를 공유하지 않습니다. `.monglepet`
패키지 규격, 권장 프로필, 데이터 fixture와 공통 테스트 시나리오만
공유합니다.

## macOS 개발

현재 기준 환경은 Xcode 26.6, Swift 6이며 프로젝트는 macOS 14 이상을
대상으로 합니다.

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```sh
xcodebuild -project apps/macos/MonglePet.xcodeproj \
  -scheme MonglePet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MonglePetDerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:MonglePetTests
```

작업 전에는 [AGENTS.md](AGENTS.md)와 작업 유형에 맞는 `AGENTS/` 문서를
먼저 확인합니다. macOS 전용 지침은
[apps/macos/AGENTS.md](apps/macos/AGENTS.md), 배포 파일 생성 절차는
[apps/macos/DISTRIBUTION.md](apps/macos/DISTRIBUTION.md)에 정리되어
있습니다.

## 라이선스

MonglePet의 자체 소스 코드는
[PolyForm Noncommercial License 1.0.0](LICENSE)에 따라 공개됩니다.
이는 비상업적 사용을 허용하는 소스 공개 라이선스이며 OSI 승인 오픈 소스
라이선스는 아닙니다. 저작권자 표기는 [NOTICE](NOTICE)를 확인하세요.

제3자 소프트웨어에는 각각의 라이선스가 적용됩니다. 자세한 내용은
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인하세요. 앱 아이콘,
캐릭터 이미지, 샘플 펫을 포함한 자산은 소스 코드 라이선스 범위에서 제외되며
[ASSET_LICENSE.md](ASSET_LICENSE.md)의 조건을 따릅니다.
