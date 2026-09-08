# macOS 1.9.1 편집 보호·조건 규칙 재생 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-09-08
- 마지막 갱신: 2026-09-08

## 목표

- D-134 편집 보호·독립 설정 보존과 D-135 조건 규칙 연속 재생을 macOS `1.9.1 (20)` Preview로 게시한다.
- 검증한 소스 커밋, 미서명 Universal ZIP, SHA-256, manifest와 GitHub Pre-release를 일치시킨다.
- Windows 후속 구현 범위를 두 전용 인계 문서로 확정한다.

## 범위

- 앱 버전 `1.9.1 (20)`과 버전 테스트
- 행동 삭제 영향 확인, 독립 이동 설정 보존, 공통 저장 실패·재시도와 제작 편집기 변경 폐기 확인
- 앱 사용·입력 없음 규칙의 조건 유지 중 행동 연속 재생과 안전 fallback
- D-134·D-135 공통 결정·명세·테스트·플랫폼 동등성·Windows 인계
- 전체 macOS 단위 테스트, Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP·체크섬·manifest
- `macos-v1.9.1-preview.1` GitHub Pre-release와 원격 자산 검증

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- settings schema-v16, 제작자 설정 v12, `.monglepet` formatVersion, 저장 `repeats`와 30 MiB 상한 변경
- Windows 소스 구현·빌드·실제 QA
- 자동 업데이트와 서버 배포
- macOS·Windows 플랫폼 동등 완료 표시

## 열린 질문

- 없음

## 결정사항

- schema 비변경 안정성·동작 보정이므로 patch 버전 `1.9.1`, 빌드 번호 `20`으로 올린다.
- 기존 Preview를 보존하고 태그는 `macos-v1.9.1-preview.1`, 릴리스 이름은 `MonglePet macOS 1.9.1 Preview 1`로 한다.
- Apple Developer Program 미가입 상태이므로 미서명·미공증 Universal ZIP만 제한된 테스터에게 제공한다.

## 작업 순서

### 공통 계약

- [x] D-134·D-135, 행동·설정·패키지 명세와 Windows 인계를 갱신한다.

### macOS

- [x] 앱 버전과 버전 테스트를 `1.9.1 (20)`으로 올린다.
- [x] 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 기능·문서·버전을 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 소스 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성한다.
- [x] 압축 해제본의 버전·빌드·Bundle ID·Universal 아키텍처·AppIcon과 격리 실행을 확인한다.
- [x] GitHub Pre-release를 게시하고 태그 대상과 원격 자산을 재검증한다.
- [x] 배포·다운로드 문서에 최종 커밋·크기·SHA-256을 기록하고 푸시한다.

### Windows

- [x] 편집 보호·독립 설정 보존을 `WINDOWS_EDIT_SAFETY_HANDOFF.md`에 기록한다.
- [x] 조건 규칙 연속 재생을 `WINDOWS_CONTINUOUS_RULE_PLAYBACK_HANDOFF.md`에 기록한다.
- [ ] Windows 환경에서 구현·자동 테스트·실제 QA를 진행한다.

### 플랫폼 동등성

- [ ] Windows 구현 뒤 편집 보호와 조건 규칙 사용자 시나리오를 교차 확인한다.

## 검증 방법

- D-134 관련 테스트 66개, D-135 관련 runtime 테스트 53개와 전체 `MonglePetTests`
- 코드 서명 없는 Debug 빌드와 `git diff --check`
- Preview 스크립트의 Universal Release 빌드와 자체 checksum 검증
- 별도 임시 디렉터리에서 ZIP을 풀어 Info.plist·실행 파일·AppIcon과 격리 실행 확인
- GitHub 원격 태그와 세 자산의 이름·크기·SHA-256을 로컬 최종본과 비교

## 진행 로그

- 2026-09-08: `main`과 `origin/main`이 `e0c6588`로 일치하고 `macos-v1.9.1-preview.1` 태그·릴리스가 없으며 GitHub 인증이 유효함을 확인했다.
- 2026-09-08: 사용자가 macOS 구현 결과를 Git에 올리고 새 Preview 릴리스를 게시하도록 요청했다.
- 2026-09-08: schema 비변경 patch 범위에 맞춰 `1.9.1 (20)`과 `macos-v1.9.1-preview.1`로 확정했다.
- 2026-09-08: 버전 변경 후 전체 `MonglePetTests` 587개 중 586개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드를 통과했다.
- 2026-09-08: 소스 커밋 `8e9ce63dba4d71bcc2c5cf162303f389631fcbb9`을 `origin/main`에 푸시하고 같은 깨끗한 커밋에서 11,649,154 bytes Universal Preview ZIP을 생성했다. SHA-256은 `ca4bfef03c9f362e8b9979511415bd177d8bbe34c26fd7450a8238fddf7a8f0a`다.
- 2026-09-08: 압축 무결성, `1.9.1 (20)`, Bundle ID, arm64·x86_64, AppIcon과 격리된 3초 실행을 확인했다.
- 2026-09-08: annotated tag `macos-v1.9.1-preview.1`과 GitHub Pre-release를 게시하고 원격 세 자산을 다시 내려받아 로컬과 바이트 단위 일치, 원격 digest와 태그 대상을 확인했다.

## 완료 결과

- GitHub Pre-release: `https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.9.1-preview.1`
- 소스 커밋: `8e9ce63dba4d71bcc2c5cf162303f389631fcbb9`
- ZIP: `MonglePet-1.9.1-build.20-preview.zip`, 11,649,154 bytes
- SHA-256: `ca4bfef03c9f362e8b9979511415bd177d8bbe34c26fd7450a8238fddf7a8f0a`
- manifest의 버전·빌드·커밋과 annotated tag 대상이 소스 커밋에 일치한다.

## 남은 위험 / 후속 작업

- 편집기 제목바 닫기·변경 폐기, 저장 실패 재시도와 실제 조건 규칙 오버레이의 최종 사용자 QA는 제한된 Preview에서 계속 확인한다.
- Windows 구현·실제 QA와 양 플랫폼 교차 확인 전에는 플랫폼 동등 완료로 표시하지 않는다.
- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
