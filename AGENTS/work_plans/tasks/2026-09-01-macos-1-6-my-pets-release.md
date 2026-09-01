# macOS 1.6.0 내 펫·런타임 보정 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-09-01
- 마지막 갱신: 2026-09-01

## 목표

- 단일 `내 펫` 흐름, 독립 가져오기·복제·편집, 보관 없는 생명주기와 행동·말풍선 런타임 보정을 macOS `1.6.0 (12)` Preview로 게시한다.
- 검증된 소스 커밋과 미서명 Universal ZIP, SHA-256, manifest 및 GitHub Pre-release를 일치시킨다.

## 범위

- 앱 버전 `1.6.0 (12)`와 버전 테스트
- 전체 macOS 단위 테스트와 Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP, 체크섬과 manifest
- `macos-v1.6.0-preview.1` GitHub Pre-release 게시와 원격 자산 재검증
- Windows 후속 구현 기준 문서 확정

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- Windows 소스 변경·빌드·실제 QA
- macOS·Windows 플랫폼 동등 완료 표시

## 열린 질문

- 없음

## 결정사항

- 사용자 흐름과 installation·instance·profile 생명주기가 함께 바뀐 기능 릴리스이므로 마케팅 버전을 `1.6.0`, 빌드 번호를 `12`로 올린다.
- 기존 Preview를 보존하고 태그는 `macos-v1.6.0-preview.1`, 릴리스 이름은 `MonglePet macOS 1.6.0 Preview 1`로 한다.
- Apple Developer Program 미가입 상태이므로 미서명·미공증 ZIP만 제한된 Preview로 게시한다.

## 작업 순서

### 공통 계약

- [x] D-111~D-113과 행동·패키지·설정 명세, Windows 인계 범위를 확인한다.

### macOS

- [x] 앱 버전과 버전 테스트를 `1.6.0 (12)`로 올린다.
- [x] 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 깨끗한 원격 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성하고 압축 해제본을 검증한다.
- [x] GitHub Pre-release를 게시하고 원격 자산과 태그 대상을 다시 검증한다.

### Windows

- [x] macOS 확정 결과를 Windows 네이티브 구현 인계 문서에 기록한다.

### 플랫폼 동등성

- [x] Windows 구현·실제 QA와 교차 왕복 전까지 진행 중 상태를 유지한다.

## 검증 방법

- 전체 `MonglePetTests`, 코드 서명 없는 Debug 빌드와 `git diff --check`
- Preview 스크립트의 Universal Release 빌드와 ZIP 자체 체크섬 검증
- 별도 임시 디렉터리에서 ZIP 압축 해제 후 버전·빌드·Bundle ID·arm64/x86_64·앱 아이콘 확인
- GitHub 릴리스 세 자산의 이름·크기·digest와 태그 대상 커밋 비교

## 진행 로그

- 2026-09-01: 로컬과 원격 `main`이 일치하고 `macos-v1.6.0-preview.1` 태그·릴리스가 없음을 확인했다.
- 2026-09-01: 변경 범위에 맞춰 `1.6.0 (12)`, `macos-v1.6.0-preview.1`로 확정했다.
- 2026-09-01: 전체 531개 중 530개 통과·조건부 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드, `git diff --check`를 통과했다.
- 2026-09-01: rollback 정리 실패 회귀 테스트에서 D-113에 없는 `비활성 설치 항목` 문구가 남은 것을 발견해, 설치를 다시 찾을 수 있다는 의미를 유지하면서 `앱을 다시 시작한 뒤 내 펫에서 확인`하도록 코드와 테스트를 정렬했다.
- 2026-09-01: 소스 커밋 `617af2e11ff9f404922227d1ca8aa6f60d8e999d`에서 10,889,967 bytes Universal ZIP과 SHA-256 `b48937ffdd03892b52049e9dc06d7a7698edf3c59da1cb589f6f1bc63f650129`을 생성했다. 압축 무결성, `1.6.0 (12)`, Bundle ID, arm64/x86_64, 앱 아이콘과 격리된 3초 실행을 확인했다.
- 2026-09-01: 태그 `macos-v1.6.0-preview.1`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시했다. 원격 태그 대상을 확인하고 세 자산을 다시 내려받아 로컬 최종본과 바이트 단위로 일치함을 확인했다.

## 완료 결과

- [`MonglePet macOS 1.6.0 Preview 1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.6.0-preview.1)을 미서명·미공증 Pre-release로 게시했다.
- `MonglePet-1.6.0-build.12-preview.zip`, 체크섬과 manifest가 검증된 소스 커밋 및 원격 자산과 일치한다.
- Windows 네이티브 구현과 실제 교차 왕복은 완료로 표시하지 않고 후속 범위로 유지했다.

## 남은 위험 / 후속 작업

- 빠른 이동 중 말풍선 배치와 대량 legacy orphan 복구는 추가 실제 앱 QA가 필요하다.
- Windows 네이티브 구현과 실제 패키지 교차 왕복은 Windows 환경에서 확인해야 한다.
- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
