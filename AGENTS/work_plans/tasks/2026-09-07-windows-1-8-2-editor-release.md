# Windows 1.8.2 애니메이션 편집기 Preview 릴리스

## 상태

- 상태: in_progress
- 생성일: 2026-09-07
- 마지막 갱신: 2026-09-07

## 목표

- Windows 애니메이션 가져오기·편집 결과 보정을 `1.8.2.21` Preview로 게시한다.
- 검증한 소스 커밋, 미서명 x64 설치기, SHA-256과 GitHub Pre-release를 일치시킨다.

## 범위

- PNG·스프라이트 공통 캔버스와 crop 경계
- 애니메이션 전체 재생·선택 프레임 미리보기
- 기존 atlas frame의 저장 crop·투명 여백 보존
- 앱 버전 `1.8.2.21`, 설치기와 GitHub Pre-release

## 제외 범위

- 코드 서명과 자동 업데이트
- settings schema, 제작자 설정 schema와 `.monglepet` format 변경
- 기존 펫의 투명 여백 자동 제거

## 열린 질문

- 없음

## 결정사항

- 기존 Windows `1.8.1.20`을 보존하고 `1.8.2.21`, 태그 `windows-v1.8.2-preview.1`, 릴리스 이름 `MonglePet Windows 1.8.2 Preview 1`을 사용한다.
- 미서명 x64 EXE 설치기와 `SHA256SUMS.txt`를 제한된 Preview로 게시한다.

## 작업 순서

### Windows

- [x] 편집기 보정과 관련 테스트를 구현한다.
- [x] Debug·Release 각 342개 테스트와 경고·오류 없는 빌드를 통과한다.
- [x] 앱·파일·MSIX 버전을 `1.8.2.21`로 올린다.
- [x] 버전 포함 전체 Debug·Release 빌드와 테스트를 재검증한다.
- [ ] 소스 커밋을 `origin/main`에 푸시한다.
- [ ] 미서명 x64 설치기와 체크섬을 생성한다.
- [ ] 설치기 버전·digest와 실행 결과를 확인한다.
- [ ] GitHub Pre-release를 게시하고 원격 자산·태그를 재검증한다.
- [ ] 배포 문서를 최종 결과로 갱신하고 푸시한다.

### 플랫폼 동등성

- [ ] 실제 혼합 DPI·키보드·Narrator와 macOS 교차 왕복을 확인한다.

## 검증 방법

- Debug·Release 전체 빌드와 테스트
- `git diff --check`
- 설치기 FileVersion, SHA-256과 태그 대상 비교
- 원격 설치기·체크섬 재다운로드 후 바이트 단위 검증

## 진행 로그

- 2026-09-07: 최신 원격 `main`과 macOS `1.8.2 (18)` Preview 릴리스를 확인하고 Windows 후속을 `1.8.2.21`로 확정했다.
- 2026-09-07: Windows 기능 커밋을 최신 원격 main 위로 재배치했다. 버전 전 기준 Debug·Release 각 342개 테스트와 경고·오류 없는 전체 빌드, `git diff --check`가 통과했다.
- 2026-09-07: `1.8.2.21` 버전 계약 테스트 9개와 Debug·Release 각각 Activity 27개·Core 69개·Packages 28개·PetLibrary 94개·Settings 95개·Shell 29개, 총 342개 테스트 및 경고·오류 없는 두 구성 전체 빌드를 재검증했다.

## 완료 결과

- 릴리스 게시 뒤 기록한다.

## 남은 위험 / 후속 작업

- 미서명 Preview이므로 SmartScreen 또는 조직 정책이 경고·차단할 수 있다.
- 실제 혼합 DPI·키보드·Narrator·대용량 이미지 반복 drag와 macOS 교차 왕복 전에는 플랫폼 동등 완료로 표시하지 않는다.
