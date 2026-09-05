# macOS 1.8.1 편집기·이용 가이드 Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-09-05
- 마지막 갱신: 2026-09-05

## 목표

- 애니메이션 PNG·스프라이트 가져오기 편집기 보정과 앱 내 간단 이용 가이드를 macOS `1.8.1 (17)` Preview로 게시한다.
- 검증한 소스 커밋, 미서명 Universal ZIP, SHA-256, manifest와 GitHub Pre-release를 일치시킨다.
- Windows 후속 편집기·이용 가이드 구현 범위를 확정한다.

## 범위

- 앱 버전 `1.8.1 (17)`과 버전 테스트
- PNG 포함 선택·목록 제거·공통 crop 캔버스·비동기 처리와 스프라이트 순서 선택 보존
- 애니메이션 편집 오류·취소·프레임 상한 UX
- `지원 > 이용 가이드`, 설정 바로가기와 고정 운영 웹 가이드
- 관련 공통 결정·플랫폼 동등성·Windows 인계
- 전체 macOS 단위 테스트, Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP·체크섬·manifest
- `macos-v1.8.1-preview.1` GitHub Pre-release와 원격 자산 검증

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- 첫 실행 강제 온보딩과 자동 업데이트
- 설정·제작자 설정·`.monglepet` schema 변경
- Windows 소스 구현·빌드·실제 QA
- 기존 애니메이션 package 저장과 행동 설정 저장을 묶는 신규 교차 저장소 transaction
- macOS·Windows 플랫폼 동등 완료 표시

## 열린 질문

- 없음

## 결정사항

- schema와 runtime 의미가 유지되는 편집기·가이드 보정이므로 patch 버전 `1.8.1`, 빌드 번호 `17`로 올린다.
- 기존 Preview를 보존하고 태그는 `macos-v1.8.1-preview.1`, 릴리스 이름은 `MonglePet macOS 1.8.1 Preview 1`로 한다.
- Apple Developer Program 미가입 상태이므로 미서명·미공증 Universal ZIP만 제한된 테스터에게 제공한다.
- settings schema-v16, 제작자 설정 schema-v12와 `.monglepet` formatVersion은 변경하지 않는다.

## 작업 순서

### 공통 계약

- [x] D-122·D-123, 플랫폼 동등성과 Windows 편집기·가이드 인계를 갱신한다.

### macOS

- [x] 앱 버전과 버전 테스트를 `1.8.1 (17)`로 올린다.
- [x] 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 기능·문서·버전을 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 소스 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성한다.
- [x] 압축 해제본의 버전·빌드·Bundle ID·Universal 아키텍처·앱 아이콘과 격리 실행을 확인한다.
- [x] GitHub Pre-release를 게시하고 태그 대상과 원격 자산을 재검증한다.
- [x] 배포·다운로드 문서에 최종 커밋·크기·SHA-256을 기록하고 푸시한다.

### Windows

- [x] PNG·스프라이트 편집 결과를 `WINDOWS_MACOS_1_3_HANDOFF.md`에 갱신한다.
- [x] 앱 내 간단 이용 가이드를 `WINDOWS_IN_APP_QUICK_GUIDE_HANDOFF.md`에 기록한다.
- [ ] Windows 환경에서 구현·자동 테스트·실제 QA를 진행한다.

### 플랫폼 동등성

- [ ] Windows 구현 뒤 편집 결과와 이용 가이드 사용자 시나리오를 비교한다.

## 검증 방법

- 전체 `MonglePetTests`, 코드 서명 없는 Debug 빌드와 `git diff --check`
- UI 테스트 target compile과 실제 Runner 실행 가능 여부 기록
- Preview 스크립트의 Universal Release 빌드와 자체 checksum 검증
- 별도 임시 디렉터리에서 ZIP을 풀어 Info.plist·실행 파일·AppIcon과 격리 실행 확인
- GitHub 원격 태그와 세 자산의 이름·크기·SHA-256을 로컬 최종본과 비교

## 진행 로그

- 2026-09-05: `main`과 `origin/main`이 `6d585c5`로 일치하고 `macos-v1.8.1` 태그가 없음을 확인했다.
- 2026-09-05: 사용자가 편집기 결과를 확인하고 이용 가이드 운영 URL을 확정한 뒤 커밋·푸시·릴리스를 요청했다.
- 2026-09-05: schema 비변경 patch 범위에 맞춰 `1.8.1 (17)`과 `macos-v1.8.1-preview.1`로 확정했다.
- 2026-09-05: 전체 `MonglePetTests` 553개 중 552개 통과·선택적 WebP 1개 건너뜀·실패 0개, 코드 서명 없는 Debug 빌드와 UI 테스트 target compile을 통과했다. 전용 XCUITest Runner는 앱 assertion 전에 멈추는 현재 호스트 제약으로 중단해 실제 이용 가이드·편집기 UI QA는 후속으로 남겼다.
- 2026-09-05: 소스 커밋 `97ecbf4cfffbd483c07215d207fe6756d579c30c`을 `origin/main`에 푸시하고 깨끗한 커밋에서 Universal Release 산출물을 생성했다.
- 2026-09-05: 압축 해제본의 `1.8.1 (17)`, Bundle ID, arm64·x86_64, AppIcon과 격리된 3초 실행을 확인했다.
- 2026-09-05: 태그 `macos-v1.8.1-preview.1`과 GitHub Pre-release를 게시하고 원격 세 자산을 다시 내려받아 로컬 최종본과 바이트 단위 일치 및 태그 대상을 확인했다.

## 완료 결과

- GitHub Pre-release: `https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.8.1-preview.1`
- 소스 커밋: `97ecbf4cfffbd483c07215d207fe6756d579c30c`
- ZIP: `MonglePet-1.8.1-build.17-preview.zip`, 11,284,078 bytes
- SHA-256: `11b8afb63bdbc722cc5816bd00c7e3ec90083ab8b68e868f6dd6ffd23375f708`
- manifest의 버전·빌드·커밋과 annotated tag 대상이 소스 커밋에 일치한다.

## 남은 위험 / 후속 작업

- 현재 호스트의 전용 XCUITest Runner가 앱 assertion 전에 멈춰 실제 이용 가이드·편집기 키보드·VoiceOver QA가 남아 있다.
- 기존 애니메이션 수정 뒤 행동 설정 디스크 저장 실패를 두 저장소에서 함께 복구하는 transaction은 별도 아키텍처 후속 작업이다.
- Windows 구현·실제 QA와 양 플랫폼 package 왕복 전에는 플랫폼 동등 완료로 표시하지 않는다.
- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
