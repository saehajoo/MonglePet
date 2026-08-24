# macOS 1.3.1 이미지 편집 UI 보정 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-08-24
- 마지막 갱신: 2026-08-24

## 목표

- macOS `1.3.0 (5)` 공개 뒤 완료한 PNG·스프라이트 결과 미리보기와 스크롤 보정을 `1.3.1 (6)` Preview로 게시한다.
- 검증된 소스 커밋과 Universal 미서명 ZIP, SHA-256, manifest 및 GitHub Pre-release를 일치시킨다.
- macOS 기준 UI와 최신 릴리스 정보를 Windows 작업 공간에서 구현할 수 있도록 인계 문서와 실행 프롬프트를 갱신한다.

## 범위

- 앱 마케팅 버전 `1.3.1`, 빌드 번호 `6`과 버전 테스트
- 스프라이트 전체 시트 종횡비 기반 높이·고정 선택 결과 패널
- PNG 왼쪽 자르기 캔버스·오른쪽 고정 결과 패널·독립 설정 스크롤
- 전체 단위 테스트, Debug·Universal Release 빌드와 실제 Preview 앱 스모크 QA
- 미서명·미공증 Preview ZIP, 체크섬, manifest와 GitHub Pre-release 게시·원격 재검증
- 공개 다운로드 인계와 Windows 구현 지침 갱신

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- Windows 소스 변경·빌드·실제 QA
- 업데이트 확인·자동 업데이트
- `.monglepet` schema 또는 이미지 처리 결과 변경

## 열린 질문

- 없음

## 결정사항

- 공개 `1.3.0` 뒤의 호환 버그 수정이므로 SemVer patch를 올려 `1.3.1 (6)`로 게시한다.
- 태그는 `macos-v1.3.1-preview.1`, 릴리스 이름은 `MonglePet macOS 1.3.1 Preview 1`로 한다.
- 기존 `1.3.0` 자산과 태그는 수정하지 않고 새 릴리스에 세 산출물을 게시한다.
- 릴리스 태그는 manifest에 기록된 깨끗한 원격 소스 커밋을 가리킨다.

## 작업 순서

### 공통 계약

- [x] 1단계: 버전·태그·릴리스 범위를 결정과 배포 문서에 기록한다.

### macOS

- [x] 2단계: 앱 버전과 버전 테스트를 `1.3.1 (6)`로 올린다.
- [x] 3단계: 전체 단위 테스트, Debug·Universal Release 빌드와 실제 앱 QA를 완료한다.
- [x] 4단계: 깨끗한 원격 커밋에서 Preview ZIP·체크섬·manifest를 생성하고 재검증한다.
- [x] 5단계: GitHub Pre-release를 게시하고 원격 자산을 다시 받아 digest를 비교한다.

### Windows

- [x] 6단계: Windows 인계 문서·실행 프롬프트에 최신 macOS UI 기준과 릴리스 커밋을 기록한다.

### 플랫폼 동등성

- [x] 7단계: Windows 구현·실제 QA 전에는 이미지 편집 기능을 플랫폼 동등 완료로 표시하지 않는다.

## 검증 방법

- 전체 `MonglePetTests`와 코드서명 없는 Debug 빌드를 실행한다.
- Preview 스크립트의 Universal Release 빌드와 ZIP 자체 체크섬 검증을 통과한다.
- 별도 임시 디렉터리에 ZIP을 풀어 버전·빌드·Bundle ID·arm64/x86_64를 확인하고 실제 앱을 실행한다.
- GitHub 릴리스의 세 자산 이름·크기·digest와 태그 대상 커밋을 로컬 최종본과 비교한다.

## 진행 로그

- 2026-08-24: 원격 `main`과 작업 트리가 깨끗하고 최신 공개 macOS 릴리스가 `1.3.0 (5)`, 태그 `macos-v1.3.0-preview.1`임을 확인했다.
- 2026-08-24: 공개 뒤 세 번의 이미지 편집 UI 보정을 patch 릴리스 `1.3.1 (6)`, 태그 `macos-v1.3.1-preview.1`로 묶기로 확정했다.
- 2026-08-24: 버전 테스트 4개와 전체 `MonglePetTests` 469개를 실행해 468개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개를 확인했고 Debug 빌드가 성공했다.
- 2026-08-24: 깨끗한 원격 소스 커밋 `89ceb5444478eeb2717ac29ec930f4661503a794`에서 arm64·x86_64 Universal Release와 7,413,980 bytes ZIP을 생성했다. 별도 임시 경로에 풀어 `1.3.1 (6)`, Bundle ID와 두 아키텍처를 확인했다.
- 2026-08-24: 압축 해제한 Release 앱의 PNG 편집 화면에서 좌우 본문·고정 결과 미리보기·동일한 확대 버튼·footer를, 스프라이트 편집 화면에서 종횡비 기반 전체 시트·고정 선택 결과·독립 설정 영역을 실제로 확인했다.
- 2026-08-24: ZIP SHA-256 `BD0E59171DE502AC123ABE71F8EDD73D4C12A938D65A06186B644F2C8761CC04`와 manifest를 태그 `macos-v1.3.1-preview.1` Pre-release에 게시했다. 원격 세 자산을 다시 내려받아 로컬 파일과 바이트 단위로 비교했고 태그가 기준 커밋을 가리킴을 확인했다.
- 2026-08-24: 공개 다운로드 자료, 배포 상태, 플랫폼 현황과 Windows 구현 인계·실행 프롬프트를 `1.3.1 (6)` 기준으로 갱신했다.

## 완료 결과

- [`MonglePet macOS 1.3.1 Preview 1`](https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.3.1-preview.1)을 미서명·미공증 제한 테스트용 GitHub Pre-release로 게시했다.
- Universal ZIP, SHA-256과 manifest가 소스 커밋·버전·빌드·원격 자산과 일치한다.
- Windows에는 같은 정보 구조와 사용자 결과를 WinUI 3 네이티브 UI로 구현하도록 인계했으며 실제 Windows QA 전까지 플랫폼 동등성은 진행 중으로 유지한다.

## 남은 위험 / 후속 작업

- Apple Developer Program을 사용할 수 없어 이번 산출물도 Developer ID 미서명·미공증 Preview ZIP으로 제한한다.
- Windows는 최신 `main`을 받은 뒤 인계 문서 기준으로 네이티브 UI를 구현·검증해야 한다.
