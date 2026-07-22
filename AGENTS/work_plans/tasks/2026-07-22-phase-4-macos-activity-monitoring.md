# Phase 4 macOS 활동 감지

## 상태

- 상태: completed
- 생성일: 2026-07-22
- 마지막 갱신: 2026-07-22
- 현재 하위 단계: 완료

## 목표

- 접근성·화면 기록·입력 모니터링 권한 없이 자동 행동에 필요한 최소 macOS 활동 상태를 만든다.
- 전면 앱 bundle identifier, 입력 후 경과 시간, 화면 잠금에 준하는 사용자 세션 비활성화와 시스템 절전 상태만 `ActivitySnapshot`으로 전달한다.
- 잠금·화면 수면·시스템 절전 중에는 polling과 펫 애니메이션을 중지하고 복귀 시 재개한다.

## 범위

- `NSWorkspace.didActivateApplicationNotification` 기반 전면 앱 bundle identifier 감지
- `CGEventSource.secondsSinceLastEventType` 기반 모든 입력 이후 경과 시간 조회
- `NSWorkspace`의 sleep/wake, screens sleep/wake와 session active/inactive 알림 처리
- 1초 저빈도 polling과 이벤트 기반 즉시 snapshot 발행
- 주입 가능한 clock, polling scheduler와 monitor protocol
- `AppCoordinator` 생명주기 및 `PetWindowController` 시스템 일시 중지 연결
- 가짜 monitor·clock·poller와 NotificationCenter 기반 단위 테스트

## 제외 범위

- 키 입력 내용, 창 제목, 문서명, 브라우저 주소와 화면 내용 접근
- 접근성, 화면 기록 또는 입력 모니터링 권한 요청
- 비공개 `com.apple.screenIsLocked` 분산 알림 사용
- 앱 규칙 및 유휴 기준 설정 UI
- 설정 저장과 재실행 복원
- 활동 기록, 통계, 로그 또는 네트워크 전송

## 열린 질문

- 없음

## 결정사항

- 공개 API만 사용하며 사용자 세션 비활성화 또는 화면 수면 중 하나라도 참이면 `ActivitySnapshot.isScreenLocked`를 보수적으로 `true`로 전달한다.
- 전면 앱 변경과 세션·전원 상태 변경은 즉시 발행하고, 유휴 시간만 1초 간격으로 확인한다.
- 화면 잠금·화면 수면·시스템 절전 중에는 polling timer를 취소하고 마지막 유휴 시간을 유지한다.
- snapshot은 메모리에서 행동 판단에만 사용하고 파일이나 로그로 저장하지 않는다.

## 작업 순서

- [x] 4-1: Activity adapter protocol과 전면 앱 monitor
- [x] 4-2: 유휴 시간 provider와 세션·절전 monitor
- [x] 4-3: snapshot 집계와 저빈도 polling
- [x] 4-4: 앱 및 렌더링 생명주기 연결
- [x] 4-5: adapter·집계·일시 중지 단위 테스트
- [x] 4-6: 실제 잠금·절전 수동 QA와 문서 완료

## 검증 방법

- 가짜 전면 앱, idle provider, clock과 poller로 초기·주기 snapshot을 검증한다.
- NotificationCenter fixture로 앱 전환과 각 세션·전원 알림의 상태 변환을 검증한다.
- 잠금·절전 중 polling 중지와 복귀 후 재개를 검증한다.
- 시스템 일시 중지와 사용자 재우기를 분리해 깨울 때 애니메이션이 잘못 재개되지 않는지 검증한다.
- 실제 앱에서 권한 대화상자 없이 실행, 앱 전환, 화면 잠금 및 해제, 절전 복귀를 수동 확인한다.
- 전체 `MonglePetTests`와 Debug 빌드를 실행한다.

## 진행 로그

- 2026-07-22: Phase 3을 `e8f7b30`으로 커밋·푸시하고 Phase 4 착수.
- 2026-07-22: 로컬 macOS SDK와 Apple 문서에서 필요한 `NSWorkspace` 및 `CGEventSource` 공개 API 확인.
- 2026-07-22: macOS adapter, snapshot 집계와 앱 렌더링 일시 중지 연결 구현.
- 2026-07-22: 활동 감지 관련 테스트 8개 및 전체 단위 테스트 84개 통과, Debug 빌드 성공.
- 2026-07-22: 권한 요청 없음, 잠금·해제, 절전·깨우기 및 사용자 재우기 상태 보존 실제 앱 QA 통과.

## 완료 결과

- 자동 행동에 필요한 최소 macOS 활동 상태를 권한 요청 없이 메모리 snapshot으로 전달한다.
- 전면 앱 변경과 세션·전원 이벤트는 즉시 반영하고 유휴 시간은 1초 간격으로 확인한다.
- 시스템이 사용 불가한 동안 polling과 펫 애니메이션을 중지하고 사용자의 awake 상태는 보존한다.
- 실제 앱에서 잠금·절전 복귀와 사용자가 재운 펫의 숨김 상태 보존을 확인했다.

## 남은 위험 / 후속 작업

- 실제 앱 규칙 편집과 선택된 행동 재생 연결은 Phase 5 설정 UI에서 진행한다.
