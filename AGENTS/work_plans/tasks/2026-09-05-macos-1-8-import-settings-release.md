# macOS 1.8.0 가져오기 호환성·설정 UI Preview 릴리스

## 상태

- 상태: completed
- 생성일: 2026-09-05
- 마지막 갱신: 2026-09-05

## 목표

- 완전하게 재현할 수 없는 펫 설치 차단과 가져오기 검토 화면 단순화, 화면 표시·이동 정보 구조 개선을 macOS `1.8.0 (16)` Preview로 게시한다.
- 검증한 소스 커밋, 미서명 Universal ZIP, SHA-256, manifest와 GitHub Pre-release를 일치시킨다.
- Windows 후속 구현 범위를 최신 문서로 확정한다.

## 범위

- 앱 버전 `1.8.0 (16)`과 버전 테스트
- D-121 펫 가져오기 호환성 차단·수동 업데이트 링크
- 가져오기 핵심 결과와 접힌 `자세히 보기`
- 화면 표시·이동 설정 정보 구조 개선
- 전체 macOS 단위 테스트, Debug·Universal Release 빌드
- 미서명·미공증 Preview ZIP·체크섬·manifest
- `macos-v1.8.0-preview.1` GitHub Pre-release와 원격 자산 검증
- 공통 명세와 Windows·서버 인계 문서

## 제외 범위

- Developer ID 코드 서명, Apple 공증과 DMG
- 자동 업데이트·앱 내부 다운로드
- Windows·웹 서버 소스 구현과 QA
- 최신 펫과 실제 구버전 앱의 교차 설치 테스트
- macOS·Windows 플랫폼 동등 완료 표시

## 열린 질문

- 없음

## 결정사항

- 가져오기 사용자 정책과 설정 정보 구조가 바뀌는 기능 릴리스이므로 마케팅 버전을 `1.8.0`, 빌드 번호를 `16`으로 올린다.
- 기존 Preview를 보존하고 태그는 `macos-v1.8.0-preview.1`, 릴리스 이름은 `MonglePet macOS 1.8.0 Preview 1`로 한다.
- Apple Developer Program 미가입 상태이므로 미서명·미공증 ZIP만 제한된 테스터에게 제공한다.
- schema-v16과 제작자 설정 v12는 변경하지 않으며, v12를 포함한 패키지의 최소 앱 버전은 계속 최초 지원 버전 `1.7.0`이다.

## 작업 순서

### 공통 계약

- [x] D-121, 패키지·설정 명세와 Windows·서버 인계를 갱신한다.

### macOS

- [x] 앱 버전과 버전 테스트를 `1.8.0 (16)`으로 올린다.
- [x] 전체 단위 테스트와 코드 서명 없는 Debug 빌드를 통과한다.
- [x] 기능·문서·버전을 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 소스 커밋에서 Universal Preview ZIP·체크섬·manifest를 생성한다.
- [x] 압축 해제본의 버전·빌드·Bundle ID·Universal 아키텍처·앱 아이콘을 확인한다.
- [x] GitHub Pre-release를 게시하고 태그 대상과 원격 자산을 재검증한다.
- [x] 배포·다운로드 문서에 최종 커밋·크기·SHA-256을 기록하고 푸시한다.

### Windows

- [x] 가져오기 Domain·WinUI·transaction과 화면 표시·이동 정보 구조를 인계 문서에 기록한다.
- [ ] Windows 환경에서 구현·자동 테스트·실제 QA를 진행한다.

### 플랫폼 동등성

- [ ] Windows 구현 뒤 로컬·웹 가져오기와 설정 화면 시나리오를 비교한다.

## 검증 방법

- 전체 `MonglePetTests`, 코드 서명 없는 Debug 빌드와 `git diff --check`
- Preview 스크립트의 Universal Release 빌드와 자체 checksum 검증
- 별도 임시 디렉터리에서 ZIP을 풀어 Info.plist·실행 파일·AppIcon을 확인
- GitHub 원격 태그와 세 자산의 이름·크기·SHA-256을 로컬 최종본과 비교
- 사용자 요청에 따라 최신 펫과 실제 구버전 앱 교차 테스트는 제외한다.

## 진행 로그

- 2026-09-05: `main`과 `origin/main`이 `43581b0`으로 일치하고 `macos-v1.8.0-preview.1` 태그가 없음을 확인했다.
- 2026-09-05: 사용자가 macOS 변경을 승인하고 커밋·푸시·Preview 릴리스를 요청했다.
- 2026-09-05: 기능 범위에 맞춰 `1.8.0 (16)`과 `macos-v1.8.0-preview.1`로 확정했다.
- 2026-09-05: 릴리스 버전으로 전체 551개 단위 테스트 중 550개 통과·선택형 WebP fixture 1개 건너뜀·실패 0개와 코드 서명 없는 Debug 빌드를 확인했다.
- 2026-09-05: 소스 커밋 `a9e7dbb929e4f4ddbf1b49507bd1461d48676951`을 `origin/main`에 푸시하고 깨끗한 소스에서 Universal Release 산출물을 생성했다.
- 2026-09-05: 11,056,793 bytes ZIP의 SHA-256 `2782b6db1ea871421cbbcd3916df4f532229d15f7bf992326fe92d09d6bdfda7`, `1.8.0 (16)`, Bundle ID, arm64·x86_64, AppIcon과 격리된 3초 실행을 확인했다.
- 2026-09-05: `macos-v1.8.0-preview.1` GitHub Pre-release를 게시하고 원격 태그 대상과 ZIP·SHA-256·manifest 세 자산의 바이트 단위 일치를 확인했다.

## 완료 결과

- macOS `1.8.0 (16)` 미서명·미공증 Universal Preview를 게시했다.
- 릴리스: <https://github.com/saehajoo/MonglePet/releases/tag/macos-v1.8.0-preview.1>
- Windows 후속 구현과 플랫폼 동등성 검증은 완료로 처리하지 않았다.

## 남은 위험 / 후속 작업

- 전용 XCUITest Runner가 앱 연결 전에 종료되는 환경 제약이 있어 설정 화면의 좁은 창·키보드·VoiceOver 실제 QA가 남아 있다.
- Windows·서버 구현과 실제 양 플랫폼 패키지 왕복이 남아 있다.
- 미서명·미공증 Preview이므로 제한된 테스터에게만 제공한다.
