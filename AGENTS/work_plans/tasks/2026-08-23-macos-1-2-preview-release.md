# macOS 1.2.0 Preview 배포

## 상태

- 상태: completed
- 생성일: 2026-08-23
- 마지막 갱신: 2026-08-24

## 목표

- macOS의 웹 펫 URL 가져오기와 펫 제작 UI 개선을 `1.2.0 (3)` Preview로 검증하고 GitHub Pre-release에 게시한다.
- 미서명·미공증 ZIP, SHA-256과 빌드 manifest를 같은 소스 커밋에서 생성하고 원격 산출물 무결성을 재검증한다.

## 범위

- macOS 앱 버전과 관련 자동 테스트 갱신
- 전체 단위 테스트와 서명 없는 Debug·Release 빌드
- 깨끗한 원격 `main` 커밋에서 Universal Preview ZIP 생성
- 별도 임시 위치의 압축 해제, 버전·아키텍처·실행 스모크 테스트
- `macos-v1.2.0-preview.1` GitHub Pre-release 게시와 원격 digest 검증
- 배포 문서, 웹 다운로드 인계와 플랫폼 현황 갱신

## 제외 범위

- Developer ID 서명, Apple 공증과 DMG 생성
- 새 내장 몽글이 자산 교체
- Windows 소스 변경, 빌드와 실제 Windows QA
- 자체 웹 다운로드 화면의 소스 수정과 운영 배포

## 열린 질문

- 없음. 사용자가 새 버전을 `1.2.0`으로 승인했고 macOS 빌드 번호는 기존 `2` 다음인 `3`을 사용한다.

## 결정사항

- 앱 버전은 `1.2.0 (3)`, 태그는 `macos-v1.2.0-preview.1`, 릴리스 이름은 `MonglePet macOS 1.2.0 Preview 1`로 한다.
- Apple Developer Program을 사용할 수 없으므로 미서명·미공증 ZIP만 제한된 테스터에게 제공한다.
- Windows `1.1.0.13` Preview 기록과 산출물은 변경하지 않는다.
- 산출물 생성 뒤 문서 메타데이터를 갱신하는 커밋은 배포 소스 커밋과 분리하고, 릴리스 태그는 manifest에 기록된 소스 커밋을 가리킨다.

## 작업 순서

### 공통 계약

- [x] 1단계: 버전·태그·채널과 플랫폼 분리 원칙을 확정한다.

### macOS

- [x] 2단계: 앱 버전, 버전·패키지 내보내기 테스트와 배포 문서를 갱신한다.
- [x] 3단계: 전체 단위 테스트와 서명 없는 Debug·Release 빌드를 통과한다.
- [x] 4단계: 변경을 커밋·푸시하고 깨끗한 소스 커밋에서 Preview 산출물 3개를 생성한다.
- [x] 5단계: 별도 위치에서 압축 해제해 버전·아키텍처·실행을 확인한다.
- [x] 6단계: GitHub Pre-release를 게시하고 원격 산출물과 digest를 재검증한다.

### Windows

- [x] 7단계: macOS 전용 릴리스로 구분하고 기존 Windows 산출물을 보존한다.

### 플랫폼 동등성

- [x] 8단계: Windows 구현·검증 전까지 플랫폼 동등 완료로 표시하지 않고 후속 작업으로 인계한다.

## 검증 방법

- `MonglePetVersionTests`와 `PetPackageExporterTests`를 먼저 실행한 뒤 전체 `MonglePetTests`로 확장한다.
- Debug와 Release를 코드서명 없이 빌드한다.
- 생성된 ZIP의 SHA-256을 재계산하고 manifest의 버전·빌드·커밋을 확인한다.
- 별도 임시 디렉터리에서 앱을 압축 해제해 `CFBundleShortVersionString`, `CFBundleVersion`, `arm64`·`x86_64` 포함과 실제 실행을 확인한다.
- GitHub에서 산출물을 다시 내려받아 로컬 최종 ZIP과 SHA-256이 같은지 확인한다.

## 진행 로그

- 2026-08-23: 원격 `main`과 작업 트리가 깨끗한 상태에서 시작했고 기존 `macos-v1.2.0-preview.1` 태그·릴리스가 없음을 확인했다.
- 2026-08-23: 앱 버전을 `1.2.0 (3)`으로 올리고 버전·패키지 내보내기 테스트와 ZIP 파일명 기준을 함께 갱신했다.
- 2026-08-23: 버전·패키지 내보내기 대상 테스트와 전체 `MonglePetTests` 455개가 통과했다. 외부 WebP fixture 선택형 테스트 1개는 건너뛰었고 실패는 없었다.
- 2026-08-23: 코드서명 없는 Debug 테스트 빌드와 Universal Release 빌드가 통과했다. Release 앱의 버전 `1.2.0 (3)`과 `arm64`·`x86_64` 실행 파일을 확인했다.
- 2026-08-23: 소스 기준 커밋 `8eb6e179f952aadce1623ac9abcefce89bde1044`을 원격 `main`에 푸시하고, 깨끗한 상태에서 7,006,673 bytes의 ZIP·SHA-256·manifest를 생성했다. ZIP SHA-256은 `4E6347A939D53ACDE931D90B0B89FD65943D2EECB2266A1C83BA7FD0AF67AE93`이다.
- 2026-08-23: 별도 임시 디렉터리의 압축 해제본에서 `1.2.0 (3)`, Bundle ID, Universal 아키텍처와 미서명 상태를 확인하고 설정 화면 QA 인자로 실제 실행 스모크 테스트를 통과했다.
- 2026-08-23: GitHub Pre-release `MonglePet macOS 1.2.0 Preview 1`을 게시했다. 원격 세 산출물을 다시 내려받아 ZIP digest와 보조 파일이 로컬 최종본과 일치함을 확인했다. 릴리스 URL은 `https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.2.0-preview.1`이다.

## 완료 결과

- macOS `1.2.0 (3)` 미서명·미공증 Universal Preview ZIP 생성, 독립 실행 스모크 테스트와 GitHub Pre-release 게시를 완료했다.
- 배포 소스는 `8eb6e179f952aadce1623ac9abcefce89bde1044`, ZIP SHA-256은 `4E6347A939D53ACDE931D90B0B89FD65943D2EECB2266A1C83BA7FD0AF67AE93`으로 고정했다.

## 남은 위험 / 후속 작업

- 미서명·미공증 파일은 macOS 보안 정책에 따라 최초 실행이 차단될 수 있으므로 제한된 테스터용으로만 제공한다.
- 자체 웹 다운로드 화면 반영과 Windows 1.2.0 구현·QA는 후속 작업이다.
