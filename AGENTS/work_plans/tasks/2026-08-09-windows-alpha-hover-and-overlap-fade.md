# Windows 알파 호버와 겹침 투명화

## 상태

- 상태: completed
- 생성일: 2026-08-09
- 마지막 갱신: 2026-08-09

## 목표

- Windows 펫의 호버 쓰다듬기와 클릭 통과 중 겹침 투명화를 현재 프레임의 실제 알파 표시 픽셀 기준으로 동작시킨다.
- schema-v10에 이미 존재하는 전역 겹침 투명화 설정을 WinUI와 실제 Composition overlay에 연결한다.

## 범위

- 종횡비 여백을 고려하는 순수 알파 마스크 좌표·판정 모델
- Windows Imaging Component 기반 현재 atlas frame 알파 마스크 비동기 디코딩과 캐시
- 쓰다듬기의 패널 진입·실제 표시 픽셀 dwell·패널 이탈 재활성화
- 클릭 통과·awake·화면 사용 가능 조건의 100ms 겹침 감시와 기본 투명도 복원
- WinUI 겹침 투명화 사용 여부와 투명도 편집
- Core 단위 테스트, Debug·Release 빌드·테스트와 packaged Release 실제 QA

## 제외 범위

- 투명 픽셀별 `WM_NCHITTEST`와 드래그 영역 변경
- GPU surface readback 또는 C++ 디코더
- animated WebP와 다중 프레임 이미지 파일 형식 확장
- 혼합 DPI 다중 모니터 물리 장비 QA

## 열린 질문

- 없음

## 결정사항

- macOS와 같은 최대 64px 마스크를 사용하며 알파가 0보다 큰 픽셀을 표시 영역으로 판단한다.
- manifest frame 좌표는 atlas 좌상단 기준으로 해석하고, 화면의 aspect-fit 여백을 제외한 뒤 마스크 좌표로 변환한다.
- 마스크가 아직 준비되지 않았거나 디코딩에 실패하면 표시 픽셀 아님으로 안전하게 복구하되 이미지 재생은 계속한다.
- 포인터 감시는 기존 이동 runtime의 단일 100ms timer를 공유하며 기능 비활성·숨김·잠금·절전 상태에서는 중지한다.

## 작업 순서

- [x] 1단계: 알파 마스크·호버 상태 순수 모델과 테스트
- [x] 2단계: Windows frame 알파 디코더와 Composition player 연결
- [x] 3단계: 이동 runtime의 실제 표시 픽셀 감시와 겹침 투명도 적용
- [x] 4단계: WinUI 표시 설정 편집 연결
- [x] 5단계: Debug·Release 빌드와 전체 테스트
- [x] 6단계: packaged Release 실제 알파 호버·겹침·복원·성능 QA
- [x] 7단계: 아키텍처·동등성·테스트 문서 갱신과 MSIX 생성

## 검증 방법

- 투명/불투명 픽셀, aspect-fit 여백, 경계와 잘못된 좌표를 Core 테스트한다.
- 쓰다듬기는 투명 픽셀에서 시작하지 않고 표시 픽셀 dwell 뒤 한 번만 실행하며 패널 밖 이탈 전에는 재실행하지 않는지 확인한다.
- 클릭 통과와 겹침 투명화가 모두 켜진 경우에만 실제 표시 픽셀 위에서 `min(baseOpacity, overlapOpacity)`가 적용되는지 확인한다.
- 비활성·숨김·잠금·절전·드래그와 설정 변경에서 기본 투명도를 즉시 복원하고 불필요한 timer가 중지되는지 확인한다.
- x64 Debug·Release 전체 빌드와 테스트, packaged Release 실제 앱·이벤트 로그·임시 파일·CPU를 확인한다.

## 진행 로그

- 2026-08-09: macOS `PetFrameAlphaMask`·`PetPointerOverlapLifecycle`, D-036·D-044와 Windows schema-v10·Composition player·이동 runtime을 대조해 구현 경계를 확정했다.
- 2026-08-09: 최대 64px 알파 마스크·aspect-fit 좌표 모델, 비동기 atlas frame 디코더·순차 preload 캐시와 표시 픽셀 호버 상태 테스트를 추가했다.
- 2026-08-09: 기존 100ms 포인터 관찰에 쓰다듬기와 클릭 통과 겹침 투명화를 통합하고 WinUI 설정·상태 표시를 연결했다. 두 기능이 모두 꺼지면 timer와 알파 디코딩을 시작하지 않는다.
- 2026-08-09: Debug 빌드와 Activity 21개·Core 34개·Packages 18개·PetLibrary 10개·Settings 37개·Shell 8개, 총 128개 테스트가 통과했다.
- 2026-08-09: packaged x64 Release에서 비활성 시작 시 `알파 마스크 대기`, 활성화 시 `59×64` 준비, 투명 모서리 100% 유지와 불투명 중앙 20% 적용을 확인했다. 설정·원점을 복원해 명시적으로 종료했고 최근 충돌 이벤트는 0건이었다.
- 2026-08-09: 겹침 감시가 활성화된 위치 고정 workload 10초 측정은 전체 시스템 CPU 0.442%, 단일 코어 환산 2.652%, private memory 118.4MiB로 초기 기준을 통과했다.

## 완료 결과

- 실제 frame 알파를 기준으로 투명 여백을 제외한 300ms 쓰다듬기와 클릭 통과 중 겹침 투명화를 Windows 네이티브 overlay에 연결했다.
- alpha mask가 준비되지 않았거나 디코딩에 실패하면 상호작용만 안전하게 비활성화하고 Composition 재생은 유지한다.
- `MonglePet.Windows_1.0.0.0_x64.msix`를 생성했다. `mspdbcmf.exe`가 없어 symbols package만 생략됐으며 앱 MSIX 생성에는 영향이 없다.

## 남은 위험 / 후속 작업

- Windows 시스템 이미지 codec의 실제 WebP 알파 마스크 디코딩은 WebP 호환 작업에서 fixture로 추가 검증한다.
- 혼합 DPI 다중 모니터에서 물리 픽셀 좌표와 pointer 좌표 일치는 별도 실제 장비 QA로 남긴다.
- 이 자동화 환경은 실제 포인터 위치 변경을 차단하므로 알파 표시 픽셀의 쓰다듬기 진입은 순수 상태 테스트로 검증했다. 사용자 포인터를 이용한 최종 수동 확인은 공개 배포 QA에서 함께 수행한다.
