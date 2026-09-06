# macOS 1.8.2 큰 제작 편집기 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-09-06
- 마지막 갱신: 2026-09-06

## 목표

- 애니메이션 반복 힌트 비노출, 행동 연결 우선 편집과 큰 제작 편집기의 독립 리사이즈 창을 macOS `1.8.2 (18)` Preview로 게시한다.
- 모든 큰 편집 창을 바로 이전 부모 창 기준으로 안전하게 배치하고 위치·크기를 저장하지 않는 사용자 결과를 배포한다.
- 검증한 소스 커밋, 미서명 Universal ZIP, SHA-256, manifest와 GitHub Pre-release를 일치시킨다.

## 범위

- 앱 버전 `1.8.2 (18)`과 버전 테스트
- 새 펫·애니메이션·현재 프레임·PNG·스프라이트·말풍선 편집 독립 창
- 애니메이션 반복 힌트 비노출과 행동 연결 우선 정보 구조
- 부모 창 기준 최초 배치, 현재 모니터 작업 영역 제한과 창 상태 비저장
- 공통 결정·플랫폼 동등성·Windows 인계
- 전체 macOS 단위 테스트, Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP·체크섬·manifest
- `macos-v1.8.2-preview.1` GitHub Pre-release와 원격 자산 검증

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- settings schema, 제작자 설정 schema와 `.monglepet` format 변경
- Windows 소스 구현·빌드·실제 QA
- macOS·Windows 플랫폼 동등 완료 표시

## 결정사항

- 호환 계약이 유지되는 제작 UI 보정이므로 patch 버전 `1.8.2`, 빌드 번호 `18`로 올린다.
- 기존 Preview를 보존하고 태그는 `macos-v1.8.2-preview.1`, 릴리스 이름은 `MonglePet macOS 1.8.2 Preview 1`로 한다.
- Apple Developer Program 미가입 상태이므로 미서명·미공증 Universal ZIP만 제한된 테스터에게 제공한다.

## 작업 순서

### 공통 계약

- [x] D-125·D-126, 플랫폼 동등성과 Windows 인계를 갱신한다.

### macOS

- [x] 부모 기준 창 배치 구현과 관련 회귀 테스트를 완료한다.
- [x] 앱 버전과 버전 테스트를 `1.8.2 (18)`로 올린다.
- [x] 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 기능·문서·버전을 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 소스 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성한다.
- [x] 압축 해제본의 버전·빌드·Bundle ID·Universal 아키텍처·앱 아이콘과 격리 실행을 확인한다.
- [x] GitHub Pre-release를 게시하고 태그 대상과 원격 자산을 재검증한다.
- [x] 배포·다운로드 문서에 최종 커밋·크기·SHA-256을 기록하고 푸시한다.

### Windows

- [x] 반복 힌트 비노출, 독립 창 범위와 부모 기준 배치를 Windows 인계에 기록한다.
- [ ] Windows 환경에서 네이티브 구현·자동 테스트·실제 QA를 진행한다.

### 플랫폼 동등성

- [ ] Windows 구현 뒤 편집 창과 애니메이션 편집 사용자 시나리오를 비교한다.

## 검증 방법

- 전체 `MonglePetTests`, 코드 서명 없는 Debug 빌드와 `git diff --check`
- Preview 스크립트의 Universal Release 빌드와 자체 checksum 검증
- 별도 임시 디렉터리에서 ZIP을 풀어 Info.plist·실행 파일·AppIcon과 격리 실행 확인
- GitHub 원격 태그와 세 자산의 이름·크기·SHA-256을 로컬 최종본과 비교

## 진행 로그

- 2026-09-06: 사용자가 독립 편집 창과 부모 창 기준 배치 결과를 확인한 뒤 커밋·푸시와 릴리스를 요청했다.
- 2026-09-06: 최신 macOS 공개본 `1.8.1 (17)`, 태그 `macos-v1.8.1-preview.1`과 원격 `main` 상태를 확인하고 schema 비변경 patch `1.8.2 (18)`로 확정했다.
- 2026-09-06: 전체 macOS 단위 테스트 562개 중 561개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드, `git diff --check`를 통과했다.
- 2026-09-06: 릴리스 기준 커밋 `b2cad6ffe8ba8a7f065296e0644460154faa9905`를 `origin/main`에 푸시하고 깨끗한 커밋에서 Universal Release 산출물을 생성했다.
- 2026-09-06: 압축 해제본의 `1.8.2 (18)`, Bundle ID, arm64·x86_64, AppIcon과 격리된 3초 실행을 확인했다.
- 2026-09-06: 태그 `macos-v1.8.2-preview.1`과 GitHub Pre-release를 게시하고 원격 세 자산을 다시 내려받아 로컬 최종본과 바이트 단위 일치 및 태그 대상을 확인했다.

## 완료 결과

- GitHub Pre-release: `https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.8.2-preview.1`
- 소스 커밋: `b2cad6ffe8ba8a7f065296e0644460154faa9905`
- ZIP: `MonglePet-1.8.2-build.18-preview.zip`, 11,352,823 bytes
- SHA-256: `134a09811ac38873c0e99966dad43df160dccde87b147c015d1e0a4933d417ad`
- manifest의 버전·빌드·커밋과 annotated tag 대상이 소스 커밋에 일치한다.

## 남은 위험 / 후속 작업

- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
- 실제 다중 모니터·키보드·VoiceOver QA와 Windows 구현·교차 확인 전에는 플랫폼 동등 완료로 표시하지 않는다.
