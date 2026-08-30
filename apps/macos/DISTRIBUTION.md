# MonglePet 배포 가이드

이 문서는 Mac App Store 밖에서 MonglePet Preview를 배포하는 두 경로를
구분합니다.

아래 명령은 저장소 루트에서 실행합니다.

- **Preview ZIP**: 미서명·미공증 제한 테스트 파일
- **Developer ID DMG**: Developer ID로 서명하고 Apple 공증을 완료한 배포 파일

DMG는 설치용 컨테이너일 뿐 앱의 신뢰를 만들지 않습니다. 일반 사용자에게
DMG를 배포하려면 내부 앱과 최종 DMG의 올바른 서명, Hardened Runtime,
Apple 공증과 티켓 부착이 모두 필요합니다.

## 버전 정책

- `MARKETING_VERSION`은 사용자에게 보이는 Preview 버전입니다.
- `CURRENT_PROJECT_VERSION`은 같은 버전 안의 빌드 번호입니다.
- 테스트나 검토로 코드·설정이 바뀐 새 배포 후보를 만들 때마다 빌드 번호를
  올립니다.
- 사용자에게 새 Preview를 게시할 때 변경 범위에 맞춰 SemVer
  `major.minor.patch`를 올립니다.
- 두 값이 바뀌면 `MonglePetVersionTests`의 기대값도 같은 커밋에서 갱신합니다.
- `.monglepet` 패키지 스키마 버전은 앱 마케팅 버전과 별도로 관리합니다.

현재 최신 배포는 평상시 행동 선택과 조건 규칙 분리, schema-v15 설정 이관,
권장 프로필 v11과 가져오기·내보내기 내용 확인 정리를 포함한
`1.5.0 (11)`입니다. 코드나 설정이 다시 바뀌면 빌드 번호와
`MonglePetVersionTests` 기대값을 함께 올립니다.

`macos-v1.4.0-preview.1` 게시 뒤 펫 제작기·활성 인스턴스 후속 보정과
앱 아이콘을 반영해 `macos-v1.4.0-preview.2` 새 Pre-release로
게시했습니다. 평상시 행동·조건 규칙 분리는 새 기능선을 구분하는
`macos-v1.5.0-preview.1`로 게시했으며 기존 GitHub Release 자산이나 태그는
덮어쓰지 않았습니다.

## 현재 배포 상태

- macOS `1.3.0 (5)`는 태그 `macos-v1.3.0-preview.1`의 GitHub Pre-release로 게시했으며 ZIP, SHA-256과 빌드 manifest를 함께 제공합니다.
- macOS `1.3.1 (6)` 이미지 편집 UI 보정 Preview는 태그 [`macos-v1.3.1-preview.1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.3.1-preview.1)로 보존합니다.
- macOS `1.3.2 (7)` 이동 런타임 성능 보정 Preview는 태그 [`macos-v1.3.2-preview.1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.3.2-preview.1)로 보존합니다.
- macOS `1.4.0 (8)` 행동 중심 설정·최종 몽글이 Preview는 태그 [`macos-v1.4.0-preview.1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.1)로 보존합니다.
- macOS `1.4.0 (10)` 펫 제작기·활성 인스턴스 후속 Preview는 태그 [`macos-v1.4.0-preview.2`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.4.0-preview.2)로 보존합니다.
- 최신 macOS `1.5.0 (11)` 평상시 행동·조건 규칙 Preview는 태그 [`macos-v1.5.0-preview.1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.5.0-preview.1)로 게시했으며 Universal ZIP·SHA-256·manifest의 원격 일치를 확인했습니다.
- 자체 웹사이트의 Windows·macOS 다운로드 화면 반영에는 `../../AGENTS/guides/PREVIEW_DOWNLOAD_HANDOFF.md`의 버전 고정 링크와 사용자 안내를 사용합니다.
- 회사 Mac에서는 소스·문서·자동 검증까지만 완료합니다.
- 실제 Preview ZIP 또는 Developer ID DMG 생성과 최종 설치 검증은 개인
  Mac의 깨끗한 `main`에서 진행합니다.
- Apple Developer Program과 Developer ID 준비 전에는 미서명 Preview ZIP만
  제한된 테스터에게 제공합니다.
- 일반 사용자 공개 배포는 Developer ID 서명·Apple 공증·티켓 부착을 마친
  DMG만 사용합니다.
- Windows가 아직 macOS의 최신 기능을 반영하지 않았으므로 macOS 단독
  Preview의 GitHub 태그는 `macos-v1.5.0-preview.1`처럼 플랫폼과 채널을
  구분합니다. 플랫폼 동등성이 다시 확인되기 전에는 서로 다른 버전의
  산출물을 하나의 제품 Release로 합치지 않습니다.

## 공통 사전 검증

1. 작업 트리가 깨끗하고 배포할 커밋이 원격 저장소에 푸시됐는지 확인합니다.
2. 전체 단위 테스트, Debug·Release 빌드와 필요한 UI 테스트를 통과합니다.
3. 앱의 버전·빌드 번호와 Git 커밋을 기록합니다.
4. 공개 README, 소스 라이선스, 자산 라이선스와 제3자 고지를 검토합니다.

## 미서명 Preview ZIP

```sh
apps/macos/Scripts/build-preview-zip.zsh
```

스크립트는 Release 앱을 코드서명 없이 빌드하고 `dist/`에 다음 파일을
생성합니다.

- `MonglePet-<version>-build.<build>-preview.zip`
- 같은 이름의 `.sha256`
- 버전, 커밋과 빌드 환경을 적은 `.manifest.txt`

산출물과 manifest의 커밋이 항상 일치하도록 작업 트리가 깨끗하지 않으면
스크립트가 중단되며 이를 우회하는 옵션은 제공하지 않습니다.

오프라인 검증에서 이미 받은 Swift Package 체크아웃을 재사용하려면
`SOURCE_PACKAGES_DIR`에 Xcode의 `SourcePackages` 디렉터리를 지정할 수
있습니다.

최종 파일은 별도 위치에서 다시 압축 해제해 버전 표시, 앱 실행, 설정 열기,
기본 펫 표시를 확인합니다. 미서명 파일은 정식 배포물로 표시하지 않습니다.

개인 Mac에서 검증을 마치면 GitHub Release에 다음 세 파일을 함께 올립니다.

- `MonglePet-1.5.0-build.11-preview.zip`
- `MonglePet-1.5.0-build.11-preview.zip.sha256`
- `MonglePet-1.5.0-build.11-preview.manifest.txt`

Release 설명에는 미서명·미공증 Preview라는 점, 지원 macOS 버전, 설치 후
첫 실행 확인 방법과 알려진 제한을 명시합니다.

## Developer ID DMG

### 사전 조건

- Apple Developer Program 가입
- 개인 키가 함께 설치된 `Developer ID Application` 인증서
- Apple Developer Team ID
- `notarytool` 키체인 프로필

현재 설치된 코드서명 인증서는 다음 명령으로 확인합니다.

```sh
security find-identity -v -p codesigning
```

공증 자격 증명은 비밀번호나 API 키를 저장소에 넣지 않고 macOS 키체인에
저장합니다.

```sh
xcrun notarytool store-credentials "MonglePet-Notary"
```

### 생성

```sh
SIGNING_IDENTITY="Developer ID Application: 이름 (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARY_PROFILE="MonglePet-Notary" \
apps/macos/Scripts/build-notarized-dmg.zsh
```

스크립트는 다음 순서로 실행됩니다.

1. Release Archive를 Developer ID Application으로 서명
2. Hardened Runtime, App Sandbox, 서명과 배포 entitlement 확인
3. `MonglePet.app`과 `/Applications` 바로가기가 있는 압축 DMG 생성
4. 최종 DMG 서명
5. `notarytool submit --wait`로 최종 DMG 제출
6. 승인된 DMG에 공증 티켓 부착
7. 코드서명, 티켓, Gatekeeper, DMG 무결성과 SHA-256 확인

완료된 파일과 공증 출력, entitlement 기록은 `dist/`에 남습니다.

## 독립 설치 검증

공증 성공은 실제 설치 흐름 검증을 대신하지 않습니다.

1. GitHub Release 등에 DMG와 SHA-256을 올립니다.
2. 다른 사용자 계정이나 별도 Mac에서 브라우저로 파일을 다시 받습니다.
3. quarantine 상태를 유지한 채 DMG를 열고 앱을 `/Applications`로 복사합니다.
4. 첫 실행, 완전 종료·재실행, 설정 열기, 펫 표시를 확인합니다.
5. 로그인 시 실행을 켜고 끈 뒤 시스템 로그인 항목과 재로그인 동작을
   확인합니다.

Gatekeeper 비활성화나 `xattr`로 quarantine을 제거하는 절차는 검증 또는
사용자 설치 안내에 포함하지 않습니다.

## 수동 검증 명령

```sh
codesign --verify --deep --strict --verbose=2 MonglePet.app
codesign -d --entitlements :- MonglePet.app
spctl --assess --type execute --verbose=4 MonglePet.app
hdiutil verify MonglePet.dmg
xcrun stapler validate MonglePet.dmg
spctl --assess --type open \
  --context context:primary-signature \
  --verbose=4 MonglePet.dmg
shasum -a 256 MonglePet.dmg
```

공증이 실패하면 출력된 submission ID로 로그를 받아 원인을 확인합니다.

```sh
xcrun notarytool log <submission-id> \
  --keychain-profile "MonglePet-Notary"
```
