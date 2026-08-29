# macOS 1.4.0 펫 제작기 후속 Preview 2 릴리스

## 상태

- 상태: in_progress
- 생성일: 2026-08-29
- 마지막 갱신: 2026-08-29

## 목표

- 펫 제작 버전 검증, 새 펫·사본의 독립 활성 인스턴스와 랜덤 행동·이동 전환 보정을 macOS `1.4.0 (10)` Preview로 게시한다.
- 검증된 소스 커밋과 미서명 Universal ZIP, SHA-256, manifest 및 GitHub Pre-release를 일치시킨다.

## 범위

- 앱 빌드 번호 `10`과 버전 테스트
- macOS AppIcon 10개 rendition과 누락 회귀 테스트
- 전체 macOS 단위 테스트와 Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP, 체크섬과 manifest
- `macos-v1.4.0-preview.2` GitHub Pre-release 게시와 원격 자산 재검증

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- Windows 소스 변경과 Windows 실기기 QA
- macOS·Windows 실제 패키지 교차 왕복 완료 표시

## 열린 질문

- 없음

## 결정사항

- 마케팅 버전은 `1.4.0`을 유지하고 최종 배포 후보를 구분하기 위해 빌드 번호를 `10`으로 올린다.
- 기존 Preview 1을 보존하고 태그는 `macos-v1.4.0-preview.2`, 릴리스 이름은 `MonglePet macOS 1.4.0 Preview 2`로 한다.
- UI 자동화 Runner bootstrap 실패와 실제 교차 왕복 미완료는 Pre-release 알려진 제한으로 공개한다.

## 작업 순서

### 공통 계약

- [x] 1단계: 패키지 schema를 바꾸지 않고 Windows 확정 사용자 결과만 반영했음을 확인한다.

### macOS

- [x] 2단계: 앱 빌드 번호와 버전 테스트를 `1.4.0 (10)`으로 올린다.
- [x] 3단계: 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [ ] 4단계: 깨끗한 원격 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성하고 압축 해제본을 검증한다.
- [ ] 5단계: GitHub Pre-release를 게시하고 원격 자산과 태그 대상을 다시 검증한다.

### Windows

- [x] 6단계: Windows 소스 변경 없이 Preview 2 기준 결과를 macOS 네이티브 구현으로만 반영한다.

### 플랫폼 동등성

- [ ] 7단계: 실제 macOS QA와 Windows 교차 왕복 미완료를 플랫폼 현황에 유지한다.

## 검증 방법

- 전체 `MonglePetTests`, 코드 서명 없는 Debug 빌드와 `git diff --check`를 실행한다.
- Preview 스크립트의 Universal Release 빌드와 ZIP 자체 체크섬 검증을 통과한다.
- 별도 임시 디렉터리에 ZIP을 풀어 버전·빌드·Bundle ID·arm64/x86_64를 확인한다.
- GitHub 릴리스의 세 자산 이름·크기·digest와 태그 대상 커밋을 로컬 최종본과 비교한다.

## 진행 로그

- 2026-08-29: 원격 `main`과 로컬 기준이 일치하고 GitHub CLI 인증이 유효하며 `macos-v1.4.0-preview.2`가 아직 게시되지 않았음을 확인했다.
- 2026-08-29: 마케팅 버전 `1.4.0`, 태그 `macos-v1.4.0-preview.2`로 확정했다.
- 2026-08-29: 전체 `MonglePetTests` 514개 중 513개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드를 통과했다.
- 2026-08-29: 빌드 9 ZIP 독립 검증에서 비어 있는 `AppIcon.appiconset` 때문에 앱 아이콘이 포함되지 않는 기존 문제를 발견해 게시를 중단했다. Windows 공식 1,254px 원본으로 macOS 10개 rendition을 구성하고 회귀 테스트를 추가한 빌드 10을 최종 후보로 정했다.
- 2026-08-29: 빌드 10 전체 `MonglePetTests` 515개 중 514개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 별도 Debug 빌드를 통과했다. Debug 앱에 `AppIcon.icns`, `CFBundleIconFile`과 `CFBundleIconName`이 생성됨을 확인했다.

## 완료 결과

- 진행 중.

## 남은 위험 / 후속 작업

- 현재 호스트의 UI 테스트 Runner bootstrap 실패 원인과 실제 생성·사본 편집 흐름 수동 QA가 남아 있다.
- Windows 실기기와의 실제 패키지 교차 왕복은 별도 환경에서 확인해야 한다.
- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
