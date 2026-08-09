# Windows 활동 감지와 자동 규칙 연결

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- Windows의 전면 앱, 입력 없음, 세션 잠금과 시스템 절전 상태를 최소 범위로 감지해 `ActivitySnapshot`으로 변환한다.
- 실제 활동 snapshot을 기존 행동 결정기와 runtime에 연결해 자동 앱·입력 없음 규칙과 잠금·절전 중지 동작을 활성화한다.

## 범위

- Windows 전용 활동 source와 순수 상태 변환 경계
- `GetLastInputInfo` 기반 1초 입력 없음 polling
- 전면 HWND 프로세스의 package family 또는 실행 파일명 기반 앱 식별
- 오버레이 HWND의 세션 잠금·해제와 절전·복귀 메시지 수신
- 숨김·잠금·절전 중 polling 중지와 복귀 직후 snapshot 발행
- App·행동 runtime 생명주기 연결과 읽기 전용 상태 표시
- 자동 앱·입력 없음 규칙, 잠금·절전 메시지의 packaged Release QA

## 제외 범위

- 행동 루틴과 자동 규칙 생성·삭제·순서·조건 전체 편집기
- 실행 중 앱 선택기와 앱 아이콘·표시 이름 UX
- 활동 기록·통계·디스크 저장
- 이동 대상용 전면 창 geometry와 다중 모니터 adapter

## 열린 질문

- 없음

## 결정사항

- Windows 앱 규칙 식별자는 패키지 앱이면 소문자 `pfn:<package-family-name>`, 일반 Win32 앱이면 소문자 `exe:<file-name>`을 사용한다.
- 전면 창 제목, 문서명, 브라우저 주소, 실제 입력 내용과 실행 파일 전체 경로는 snapshot이나 설정에 저장하지 않는다.
- 전면 앱과 입력 없음 시간은 화면이 사용 가능하고 펫이 깨어 있는 동안 1초 간격으로만 확인한다.
- 잠금·절전은 오버레이 HWND가 받은 공개 Win32 세션·전원 메시지로 즉시 반영하고, 복귀 시 새 snapshot을 즉시 발행한다.
- 이번 단계의 UI는 현재 감지 상태 확인만 제공하며 규칙 편집은 별도 작업으로 둔다.

## 작업 순서

- [x] 1단계: Windows 활동 source·식별자·상태 변환과 단위 테스트
- [x] 2단계: 세션·전원 메시지와 1초 monitor 구현
- [x] 3단계: App·행동 runtime 연결과 상태 UI
- [x] 4단계: Debug·Release 자동 검증과 packaged Release QA
- [x] 5단계: 결정·동등성·테스트 문서와 작업 계획 완료

## 검증 방법

- 앱 식별자 정규화, idle 시간, lock/unlock·suspend/resume 상태 전이를 운영체제 API와 분리한 테스트로 확인한다.
- Core·Activity·Packages·PetLibrary·Settings 전체 xUnit과 x64 Debug·Release 빌드를 실행한다.
- 실제 packaged Release에서 전면 앱 규칙과 짧은 입력 없음 규칙 전환, 가짜 Windows 세션·전원 메시지의 suspend/resume 연결을 확인한다.
- QA 뒤 프로세스, 패키지 등록, LocalState와 임시 파일이 남지 않는지 확인한다.

## 진행 로그

- 2026-08-09: 행동·개인정보 명세와 Windows runtime 경계를 분석하고 활동 감지 단계의 범위와 식별자 형식을 확정했다.
- 2026-08-09: `MonglePet.Activity` 프로젝트와 9개 테스트를 추가해 PFN·실행 파일명 정규화, idle snapshot과 세션·전원 상태 전이를 검증했다.
- 2026-08-09: 오버레이 HWND의 WTS·전원 메시지와 `GetLastInputInfo`·전면 앱 1초 monitor를 App·행동 runtime·상태 UI에 연결했다.
- 2026-08-09: x64 Debug·Release 전체 빌드와 Activity 9개·Core 13개·Packages 18개·PetLibrary 10개·Settings 25개, 총 75개 테스트를 통과했다.
- 2026-08-09: packaged Release에서 MonglePet PFN 앱 규칙 `focus`, Notepad 전환 뒤 2초 idle 규칙 `rest`, lock/unlock·suspend/resume pause와 숨김 중 polling 정지를 확인하고 임시 상태를 모두 정리했다.

## 완료 결과

- Windows 전면 앱과 입력 없음 상태가 1초 snapshot으로 자동 규칙에 연결됐다.
- 세션 잠금과 시스템 절전 메시지가 수동 모드보다 우선해 scheduler와 frame playback을 일시 정지하고 복귀 시 즉시 재평가한다.
- PFN·실행 파일명만 사용하고 창 제목·경로·입력 내용과 활동 이력을 저장하지 않는다.
- Debug·Release 자동 검증과 실제 packaged Release QA를 완료했다.

## 남은 위험 / 후속 작업

- Windows 앱 식별자 선택 UX와 기존 macOS bundle identifier 규칙의 플랫폼별 표시는 전체 규칙 편집기 단계에서 구현한다.
