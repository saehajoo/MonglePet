# Windows 로그인 시 자동 실행

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- MSIX `StartupTask` 실제 상태를 단일 원본으로 사용해 로그인 시 자동 실행을 켜고 끈다.
- 사용자가 Windows 설정에서 차단한 상태는 앱이 우회하지 않고 시작 앱 설정으로 안내한다.

## 범위

- desktop startupTask manifest 선언
- StartupTask 상태 adapter와 WinUI 일반 설정
- 상태 새로 고침·등록·해제·Windows 시작 앱 설정 열기
- 대상 테스트·Debug 빌드와 문서 갱신

## 제외 범위

- JSON 설정 필드 추가
- 자동 업데이트 채널과 배포 서명
- 실제 로그아웃·로그인 수동 QA

## 작업 순서

- [x] 공식 Windows StartupTask 계약과 현재 manifest 분석
- [x] manifest·adapter 구현
- [x] WinUI 설정과 복구 안내 연결
- [x] 대상 검증과 문서 갱신

## 완료 결과

- `desktop:StartupTask`를 기본 비활성으로 선언하고 `StartupTask` 실제 상태만 읽고 변경한다.
- 일반 설정에서 등록·해제, 사용자 차단·조직 정책·manifest 부재 상태와 Windows 시작 앱 설정 복구를 안내한다.
- 생성 AppxManifest에 startup task가 유지되고 x64 Debug 앱 빌드가 경고·오류 없이 통과했다.
- extension 내부 실행 파일 토큰이 MakeAppx에서 치환되지 않는 문제를 실제 실행 파일명으로 수정하고 Release MSIX 생성을 통과했다.
- Debug·Release 전체 153개 테스트와 두 구성 전체 빌드가 통과했다.

## 남은 위험 / 후속 작업

- 실제 설치 MSIX의 시작 앱 목록 반영과 다음 로그인 자동 시작은 최종 수동 QA에서 확인한다.
