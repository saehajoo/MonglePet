# Windows 행동 런타임과 기본 설정 UI

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- schema-v10의 펫별 행동 프로필을 C# 행동 결정기와 cycle 기반 scheduler를 거쳐 실제 Composition 모션 재생에 연결한다.
- WinUI에서 자동·수동 모드와 기존 수동 행동 루틴을 선택하고 즉시 저장·적용·복원한다.

## 범위

- 운영체제 API와 분리된 cycle·repeatCount·단계·루틴 반복 scheduler와 단위 테스트
- 현재 펫 기본 모션 예약 참조와 누락 모션의 기본 모션 fallback
- monotonic 시간과 일회성 timer 기반 Windows 행동 runtime
- 숨김 중 scheduler와 프레임 재생 pause, 다시 깨울 때 남은 실행 재개
- 내장 펫 예약 키와 설치 UUID별 기본 행동 프로필 보충
- 자동·수동 모드와 기존 수동 루틴 선택 WinUI, 전체 설정 원자 저장
- 펫 전환·재시작 복원과 실제 packaged Release QA

## 제외 범위

- 행동 루틴 단계 생성·삭제·순서·반복 횟수 편집기
- 자동 규칙 생성·삭제·우선순위 편집기
- 전면 앱, 입력 없음, 잠금·절전 Windows adapter와 polling
- 쓰다듬기, 이동 애니메이션과 말풍선 우선 표시

## 열린 질문

- 없음

## 결정사항

- 순수 `MonglePet.Core` scheduler는 모션 ID와 cycle duration만 입력받고 WinUI·Composition·패키지 파일에 의존하지 않는다.
- Windows runtime은 `Stopwatch` monotonic 시간과 `DispatcherQueueTimer` 일회성 경계 timer를 사용한다.
- 자동 모드에서 OS 활동 snapshot이 아직 없을 때는 기본 행동 루틴을 선택한다. 저장된 규칙은 보존하며 다음 adapter 단계에서 입력을 연결한다.
- 이번 WinUI는 이미 저장된 루틴 선택까지만 제공하고 루틴·규칙 전체 편집기는 별도 후속 단계로 둔다.

## 작업 순서

- [x] 1단계: 순수 cycle 기반 MotionScheduler와 단위 테스트
- [x] 2단계: Composition 동적 모션 전환·pause와 Windows 행동 runtime
- [x] 3단계: 펫별 기본 프로필·App 적용 경계와 WinUI 기본 설정
- [x] 4단계: Debug·Release 자동 검증과 실제 packaged Release QA
- [x] 5단계: Windows·동등성 문서와 작업 계획 완료

## 검증 방법

- 같은 루틴 재요청 진행 유지, 다른/편집 루틴 즉시 재시작, repeatCount·단계·루틴 반복과 pause를 xUnit으로 확인한다.
- 현재 펫 기본 예약 참조와 없는 모션 fallback을 확인한다.
- Core·Packages·PetLibrary·Settings 전체 xUnit과 x64 Debug·Release 빌드를 실행한다.
- 실제 packaged Release WinUI에서 자동·수동 변경과 수동 루틴 선택을 조작하고 LocalState·runtime 상태를 확인한다.

## 진행 로그

- 2026-08-09: 행동 명세, macOS 기준 동작, Windows 결정기·설정 Domain·Composition 재생 경계를 분석하고 기본 런타임 단계 범위를 확정했다.
- 2026-08-09: 순수 `MotionScheduler`와 5개 xUnit 시나리오를 추가하고 같은 요청 진행 유지, 편집 요청 재시작, repeatCount·단계·루틴 반복, pause, 완료와 fallback을 검증했다.
- 2026-08-09: Composition player의 동적 모션 전환과 pause/resume, `Stopwatch`·일회성 timer 행동 runtime, 펫별 기본 프로필과 자동·수동·기존 수동 루틴 WinUI를 연결했다.
- 2026-08-09: x64 Debug·Release 빌드와 Core 13개·Packages 18개·PetLibrary 10개·Settings 25개, 총 66개 테스트를 통과했다.
- 2026-08-09: 두 모션 packaged Release 실제 앱에서 자동 기본 루틴, 수동 `focus`, 숨김 저장, 재실행 시 숨김·선택 복원, 다시 표시할 때 `focus` 재개와 자동 복귀를 UI Automation으로 확인하고 임시 상태를 모두 정리했다.

## 완료 결과

- schema-v10 펫별 행동 프로필이 C# 행동 결정기와 순수 cycle scheduler를 거쳐 실제 Composition 모션 재생에 연결됐다.
- WinUI에서 자동·수동 모드와 기존 수동 루틴을 선택하면 즉시 저장·적용되며 펫 전환과 재실행 뒤 복원된다.
- 숨김 중 scheduler와 프레임 재생이 함께 멈추고 같은 실행에서는 남은 사이클 시간부터 재개한다.
- Debug·Release 자동 검증과 실제 packaged Release QA를 완료했다.

## 남은 위험 / 후속 작업

- 전면 앱·입력 없음 adapter가 연결되기 전 자동 규칙은 저장·해석되지만 실제 OS 활동으로 발동하지 않는다.
