# Windows 전면 앱 대표 창 선호 이동

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- Windows 자유 이동이 schema-v10의 기존 `prefersFrontmostWindow` 설정을 실제 전면 앱 대표 창 범위에 적용한다.
- 창 제목·내용을 읽거나 저장하지 않고 전면 프로세스와 일반 창의 위치·크기만 사용한다.

## 범위

- 대표 창 후보 필터·가시 면적·전체 화면 복구의 순수 resolver와 테스트
- `GetForegroundWindow`·`EnumWindows`·DWM bounds 기반 Windows adapter와 1초 캐시
- 대표 창과 화면 작업 영역의 교집합 안에서 자유 이동 목표를 만드는 Geometry
- 이동 runtime 연결, 환경 무효화와 WinUI 선호 설정 편집
- Debug·Release 빌드, 전체 테스트와 packaged Release 실제 QA

## 제외 범위

- 접근성 API 기반 문서 창 계층 또는 탭 추적
- 창 제목·문서명·화면 내용 수집
- 사용자 지정 이동 영역의 시각 편집
- 혼합 DPI 다중 모니터 물리 장비 QA

## 열린 질문

- 없음

## 결정사항

- Windows 좌상단 가상 데스크톱 물리 픽셀 좌표를 그대로 사용하며 좌표계 변환을 추가하지 않는다.
- 전면 PID의 보이는 owner 없는 non-tool, non-cloaked 최상위 창 중 알려진 작업 영역과 겹치는 가시 면적이 가장 큰 창을 대표 창으로 선택한다.
- 후보 중 한 창이라도 작업 영역의 98% 이상을 덮으면 전체 화면으로 보고 대표 창 선호를 사용하지 않는다.
- 대표 창 결과는 foreground HWND·PID 기준 최대 1초 캐시하고 화면 환경 변경에서 무효화한다.

## 작업 순서

- [x] 1단계: 순수 대표 창 resolver와 자유 이동 Geometry·테스트
- [x] 2단계: Windows native 대표 창 provider와 캐시·테스트
- [x] 3단계: 이동 runtime과 WinUI 설정 연결
- [x] 4단계: Debug·Release 빌드와 전체 테스트
- [x] 5단계: packaged Release 실제 대표 창·fallback·복원·성능 QA
- [x] 6단계: 아키텍처·결정·테스트·동등성 문서와 MSIX 갱신

## 검증 방법

- 다른 PID·숨김·owned·tool·cloaked·작은·화면 밖 창 필터와 최대 가시 면적 선택을 테스트한다.
- 전체 화면 후보, 전면 창 없음과 읽기 실패가 일반 화면 자유 이동으로 복구하는지 확인한다.
- 대표 창과 선택 이동 범위의 교집합 안에 펫 전체가 들어가고 창이 너무 작으면 화면 범위로 복구하는지 확인한다.
- 설정이 꺼지면 native 창 조회를 하지 않고, 켜지면 1초 캐시와 환경 무효화가 적용되는지 확인한다.
- 실제 packaged Release에서 일반 앱 창 안의 자유 이동과 전체 화면·MonglePet 전면 fallback, 설정 복원, 충돌 이벤트와 CPU를 확인한다.

## 진행 로그

- 2026-08-09: macOS `FrontmostWindowResolver`·`PetMovementGeometry`, Windows activity/catalog 경계와 기존 schema-v10 필드를 대조해 구현 범위를 확정했다.
- 2026-08-09: 보임·owner·tool·cloaked·최소 크기·화면 교차 필터와 최대 가시 면적·전체 화면 판정 resolver, 1초 foreground HWND·PID 캐시를 구현했다.
- 2026-08-09: 대표 창과 이동 범위 교집합 Geometry, 자유 이동 runtime, `prefersFrontmostWindow` WinUI 토글과 상태 표시를 연결했다.
- 2026-08-09: Debug 빌드와 Activity 27개·Core 36개·Packages 18개·PetLibrary 10개·Settings 37개·Shell 8개, 총 136개 테스트가 통과했다.
- 2026-08-09: packaged x64 Release에서 실제 전체 화면 전면 앱을 `대표 창 없음 또는 전체 화면`으로 판정해 작업 영역으로 복구했고, 선호 끄기 상태가 native 조회 없이 즉시 반영되는 것을 확인했다.
- 2026-08-09: 자유 이동·전면 창 감지 10초 workload는 전체 시스템 CPU 0.364%, 단일 코어 환산 2.184%, private memory 126.2MiB였다. 위치 고정·속도 160·머무름 6초·선호 켜짐·기존 원점으로 복원해 정상 종료했고 최근 충돌 이벤트는 0건이었다.

## 완료 결과

- Windows 자유 이동이 기존 schema-v10 전면 창 선호 설정을 실제 대표 창 bounds에 적용하며, 전체 화면·조회 실패·작은 창에서는 기존 작업 영역 목표로 안전하게 복구한다.
- 전면 앱 PID와 창 위치·크기·표시 속성만 메모리에서 사용하고 창 제목·내용·경로·이력은 읽거나 저장하지 않는다.
- `MonglePet.Windows_1.0.0.0_x64.msix`를 갱신했다. `mspdbcmf.exe` 부재로 symbols package만 생략됐다.

## 남은 위험 / 후속 작업

- 혼합 DPI에서 DWM frame bounds와 오버레이 물리 좌표 일치는 공개 배포 전 실제 장비 QA로 남긴다.
- 자동화 세션에서는 사용자의 전체 화면 앱이 foreground 전환 요청을 차단했다. 일반 창 내부 목표는 native snapshot resolver·Geometry 테스트로 검증했으며, 사용자 조작으로 일반 창을 실제 전면에 둔 최종 수동 QA는 공개 배포 전에 수행한다.
