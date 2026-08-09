# Windows notification area 빠른 제어

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- Windows notification area에서 현재 펫과 자주 쓰는 표시 설정을 확인하고 제어한다.
- 설정창을 닫아도 펫과 트레이 호스트는 계속 실행하고 명시적인 종료 메뉴에서만 앱을 완전히 종료한다.
- macOS 상태 메뉴와 같은 사용자 결과를 Windows 네이티브 UX로 제공한다.

## 범위

- `Shell_NotifyIcon` 기반 notification area 아이콘과 Explorer 재시작 복구
- 현재 펫 이름 표시
- 펫 깨우기·재우기
- 클릭 통과 체크 상태 확인과 전환
- 포인터가 있는 현재 모니터의 작업 영역으로 펫 가져오기와 위치 저장·복원
- 설정창 열기, 닫기 시 숨김과 명시적 완전 종료
- 메뉴 상태·순서·명령과 모니터 배치 계산의 순수 모델·단위 테스트
- packaged Release 실제 notification area QA

## 제외 범위

- notification area에서 펫 선택, 행동 모드·루틴 또는 이동 모드 전환
- 알림 balloon·toast와 백그라운드 알림
- 로그인 시 자동 실행
- 펫 직접 드래그와 일반 위치 편집 UX
- notification area 전용 설정 schema

## 열린 질문

- 없음

## 결정사항

- notification area는 Windows 전용 `MonglePet.Shell` 경계로 분리하고 WinUI 화면이나 Domain에 Win32 메뉴 타입을 노출하지 않는다.
- 메뉴는 현재 펫, 깨우기·재우기, 클릭 통과, 현재 화면으로 가져오기, 설정, 종료 순서로 macOS 기준 사용자 동작을 유지한다.
- 설정창 X 버튼은 `AppWindow.Hide`로 숨기고 `MonglePet 종료`만 runtime·overlay·tray 자원을 정리한 뒤 마지막 WinUI 창을 닫는다. notification area native callback 안에서는 자원을 직접 파괴하지 않고 UI queue로 종료 작업을 넘긴다.
- 현재 화면은 명령 시점의 포인터가 있는 모니터이며 작업 영역 우하단 여백에 현재 펫 크기를 유지해 배치한다.
- 명시적으로 이동한 위치는 기존 overlay의 `screenIdentifier`, `originX`, `originY`를 사용해 저장하고 해당 모니터가 없으면 현재 사용 가능한 모니터 안으로 복구한다.
- 아이콘 메뉴는 표시할 때마다 앱의 현재 상태 snapshot으로 다시 구성하고 별도 캐시나 설정을 만들지 않는다.

## 작업 순서

- [x] 1단계: Windows shell 프로젝트와 순수 메뉴·모니터 배치 모델
- [x] 2단계: notification area Win32 adapter와 Explorer 재시작 복구
- [x] 3단계: 앱 상태·설정창 생명주기·완전 종료 연결
- [x] 4단계: 현재 화면 이동과 위치 저장·복원 연결
- [x] 5단계: Debug·Release 자동 검증과 packaged Release QA
- [x] 6단계: 플랫폼 동등성·결정·테스트·Windows 문서 갱신

## 검증 방법

- 메뉴 항목 순서·제목·체크·활성 상태와 명령 식별자 단위 테스트
- 긴 펫 이름 말줄임과 깨움 상태 제목 단위 테스트
- 음수 좌표를 포함한 모니터 작업 영역 우하단 배치·clamp 단위 테스트
- x64 Debug·Release 전체 솔루션 빌드와 전체 xUnit 테스트
- packaged Release에서 아이콘 표시, 메뉴 상태, 깨우기·재우기, 클릭 통과, 현재 화면 이동, 설정 숨김·재열기와 완전 종료 확인
- 재실행 뒤 표시·클릭 통과·명시적 위치 복원과 임시 파일·충돌 이벤트 확인

## 진행 로그

- 2026-08-09: macOS 상태 메뉴 기준과 Windows AppWindow·overlay 생명주기를 분석하고 Windows 네이티브 notification area 범위를 확정했다.
- 2026-08-09: `MonglePet.Shell` 프로젝트에 순수 메뉴 모델, 작업 영역 배치 계산, 모니터 조회와 `Shell_NotifyIcon` adapter를 구현했다. 아이콘은 고정 GUID와 version 4 동작을 사용하고 `TaskbarCreated`에서 다시 등록한다.
- 2026-08-09: 설정창 X 닫기를 숨김으로 바꾸고 아이콘 왼쪽 클릭·설정 메뉴로 재표시하며, 명시적 종료에서 notification area·activity runtime·overlay를 정리하도록 앱 생명주기를 연결했다.
- 2026-08-09: 이동 설정 UI 자동화 종료 검증에서 native callback과 XAML 종료 경계를 재점검해, 종료 command를 UI queue로 넘기고 설정 Page 구독을 먼저 해제한 뒤 마지막 WinUI 창을 닫도록 보강했다.
- 2026-08-09: 펫 깨우기·재우기, 클릭 통과, 포인터가 있는 화면 우하단으로 가져오기와 위치 저장·재실행 복원을 packaged Release 앱에서 확인했다.
- 2026-08-09: x64 Debug·Release 전체 솔루션 빌드와 Activity 21개·Core 13개·Packages 18개·PetLibrary 10개·Settings 37개·Shell 8개, 총 107개 xUnit 테스트가 모두 통과했다.

## 완료 결과

- Windows notification area 아이콘은 현재 펫 이름을 표시하고 네이티브 메뉴에서 표시 상태, 클릭 통과, 현재 화면 이동, 설정 열기와 완전 종료를 제공한다.
- 설정창을 X로 닫아도 펫과 notification area 호스트는 유지되며 아이콘 활성화 또는 설정 메뉴로 같은 창을 다시 연다.
- 현재 화면 이동은 음수 좌표를 포함한 작업 영역에 펫 크기를 보정해 배치하고 `screenIdentifier`, `originX`, `originY`를 저장해 재실행 시 복원한다.
- 실제 packaged Release에서 메뉴 순서·제목·체크 상태, 모든 빠른 제어, 숨김·재열기, 명시적 종료와 아이콘 제거를 확인했다. 최근 앱 충돌 이벤트와 설정 임시 파일은 없었다.
- x64 MSIX `MonglePet.Windows_1.0.0.0_x64.msix`를 생성했다. `mspdbcmf.exe`가 없어 심볼 패키지만 생성되지 않는 배포 도구 경고 1개가 남는다.

완료일: 2026-08-09

## 남은 위험 / 후속 작업

- `TaskbarCreated` 재등록 경로는 구현했지만 사용자 Explorer를 실제로 다시 시작하는 수동 QA는 하지 않았다.
- 다중 모니터 배치의 순수 좌표 테스트와 현재 장비의 위치 저장·복원은 통과했으며, 서로 다른 DPI가 섞인 추가 장비에서 수동 QA가 필요하다.
