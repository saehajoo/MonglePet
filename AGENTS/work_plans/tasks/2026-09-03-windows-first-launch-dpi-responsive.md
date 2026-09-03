# Windows 첫 실행 런타임·DPI·좁은 창 보정

## 상태

- 상태: in_progress
- 생성일: 2026-09-03
- 마지막 갱신: 2026-09-03

## 목표

- 설치 직후 처음 실행한 프로세스에서도 모든 깨어 있는 펫의 행동·이동 timer가 즉시 시작되게 한다.
- 디스플레이 배율이 다른 Windows 환경에서도 펫의 오른쪽·아래쪽이 overlay HWND에 잘리지 않게 한다.
- 설정 창을 줄이거나 높은 DPI에서 사용할 때 `내 펫`의 주요 작업과 카드 버튼이 잘리지 않게 한다.

## 범위

- unpackaged 설치 완료 후 첫 실행을 포함한 WinUI 창·Composition runtime 초기화 순서
- atlas 비동기 로드 실패 시 동일 프로세스 안에서 안전하게 다시 시도하는 재생 준비 경계
- Win32 overlay HWND와 `DesktopChildSiteBridge`의 물리 픽셀·rasterization scale 정합성
- 저장 화면 식별자가 없는 좌표와 디스플레이 변경 시 화면 안쪽 복구
- `내 펫` NavigationView·상단 작업·펫 카드의 좁은 폭 대응
- 설정 창의 DPI 인식 최소 추적 크기와 작은 작업 영역 예외

## 제외 범위

- settings schema와 `.monglepet` 공통 계약 변경
- macOS 소스 변경
- 새 행동·이동 기능 추가
- 버전 증가, 커밋·푸시와 GitHub Release 게시

## 열린 질문

- 없음. 첫 프로세스 전체가 멈추고 재실행하면 회복된다는 사용자 재현 결과를 공용 런타임 준비 순서 문제로 취급한다.

## 결정사항

- settings 창을 먼저 활성화하고 XAML content가 Loaded 된 다음 dispatcher의 다음 작업에서 overlay·행동·이동 runtime을 생성한다.
- protocol activation도 같은 초기화 완료 경계 뒤에서 처리해 기본 메모리 설정을 먼저 편집하지 않게 한다.
- 펫 크기 계약의 `px`는 Win32 화면 좌표와 같은 물리 픽셀로 유지하고 composition site의 자동 DPI 확대를 중복 적용하지 않는다.
- 이미지 surface의 일시적 첫 로드 실패는 제한된 횟수만 재취득하며 성공 완료만 재생 준비로 판단한다.
- 설정 UI는 수평 스크롤에 의존하지 않고 좁은 폭에서 NavigationView를 자동 축소하고 작업 버튼을 균등 열에 배치한다.
- 설정 창은 `800×600` DPI 독립 픽셀보다 작아지지 않게 하되 현재 모니터 작업 영역이 더 작으면 화면 안에서 사용할 수 있는 크기를 우선한다. 실행 시 기존 창이 이보다 작으면 즉시 최소 크기로 넓힌다.
- 공개 Preview 2를 덮어쓰지 않고 파일 버전 `1.6.0.17`, 태그 `windows-v1.6.0-preview.3`으로 게시한다.

## 작업 순서

### Windows

- [x] 1단계: 설치기 첫 실행과 일반 실행의 차이 및 runtime 생성 시점을 코드로 고정한다.
- [x] 2단계: content Loaded 이후 단일 초기화와 activation 대기를 구현한다.
- [x] 3단계: atlas surface 성공 준비·제한 재시도를 구현한다.
- [x] 4단계: overlay DPI scale과 저장 위치 복구를 구현한다.
- [x] 5단계: `내 펫` 상단 작업과 카드가 좁은 창에서 잘리지 않도록 반응형 배치를 적용한다.
- [x] 6단계: 관련 테스트, Debug·Release 빌드와 전체 테스트를 완료한다.

### 플랫폼 동등성

- [ ] 실제 Windows 100%·150%·200% DPI와 설치 완료 첫 실행을 확인한다.
- [ ] macOS 공통 동작·저장 계약에 영향이 없음을 확인한다.

## 검증 방법

- 설치 완료 화면에서 앱을 바로 실행하고 기본 몽글이 행동·자유 이동 또는 마우스 도망가기가 재실행 없이 시작되는지 확인한다.
- 같은 프로세스에서 이동 방식 변경과 새 펫 가져오기 후 각 펫이 바로 움직이고 애니메이션을 재생하는지 확인한다.
- 100%·150%·200% DPI 및 보조 모니터에서 펫 전체 픽셀이 보이고 저장 위치가 화면 작업 영역 안에 복원되는지 확인한다.
- 설정 창 폭을 줄여 생성·가져오기·전체 제어와 카드의 저장·복제·내보내기·순서·삭제 작업이 잘리지 않는지 확인한다.
- 좁은 관련 테스트 후 Windows solution Debug·Release 빌드와 전체 테스트, `git diff --check`를 실행한다.

## 진행 로그

- 2026-09-03: `main` `30e2876`과 깨끗한 작업 트리를 확인했다. 설치기의 `[Run]`이 `nowait postinstall`로 새 프로세스를 즉시 시작하고, 현재 앱은 `OnLaunched`에서 settings 창을 활성화한 직후 XAML Loaded 전에 overlay와 모든 DispatcherQueue timer를 만드는 차이를 확인했다.
- 2026-09-03: overlay HWND 크기와 composition visual에 같은 물리 픽셀 값을 쓰면서 site의 DPI rasterization scale을 제한하지 않고 `WM_DPICHANGED`도 처리하지 않는 경로, 화면 식별자가 없는 저장 좌표를 보정 없이 적용하는 경로를 확인했다.
- 2026-09-03: `내 펫`은 고정 220px 탐색 창과 여러 수평 StackPanel·84px preview/Auto 제어 열을 사용해 높은 DPI와 좁은 창에서 버튼이 잘릴 수 있음을 확인했다.
- 2026-09-03: MainPage Loaded 다음 dispatcher turn으로 runtime 시작을 옮기고 초기화 전 activation queue, atlas 성공 준비·3회 제한 재시도, physical-pixel site scale과 DPI 변경 보정, 화면 식별자 없는 좌표 복구를 구현했다.
- 2026-09-03: NavigationView 자동 compact, 상단 작업의 균등 열과 compact 펫 카드 preview·설명·아이콘 작업을 적용했다. Debug·Release 빌드가 경고·오류 0개로 통과했고 각 구성에서 Activity 27, Core 64, Packages 28, PetLibrary 89, Settings 85, Shell 20으로 총 313개 테스트가 모두 통과했다. `git diff --check`도 통과했다.
- 2026-09-03: 같은 작업 트리에서 미서명 x64 `1.6.0.16` Release 설치기를 다시 만들고 기존 GitHub Release 설치본 위에 종료 코드 0으로 설치했다. `%LOCALAPPDATA%\MonglePet` 사용자 데이터는 전후 48개·5,827,052 bytes와 전체 inventory digest가 일치했고 설치 DLL은 publish DLL과 동일했다. 설치본 프로세스가 실행·응답 중임을 확인했으며 행동·이동·DPI·좁은 창의 시각 판정은 사용자 QA를 기다린다.
- 2026-09-03: 후속 요청에 따라 settings HWND의 `WM_GETMINMAXINFO`에 `640×480` effective pixel 최소 크기를 monitor DPI로 환산해 적용했다. 작은 화면에서는 현재 monitor work area를 상한으로 사용하고 종료 시 native subclass를 제거한다. Windows 앱 Debug 빌드가 경고·오류 없이 통과했다. 같은 소스의 Release publish와 설치기를 다시 만들어 종료 코드 0으로 덮어설치했고 사용자 데이터 48개·5,827,052 bytes의 inventory digest를 보존했다. 설치 DLL과 publish DLL 일치 및 설치본 실행 응답을 확인했다.
- 2026-09-03: 실제 최소 폭 619px 화면에서 내보내기 버튼이 잘리는 사용자 QA에 따라 최소값을 `800×600` effective pixel로 올렸다. 서브클래싱 시 현재 창도 계산된 물리 최소 크기보다 작으면 즉시 넓혀 기존의 작은 창 상태가 다음 실행에 남지 않게 했다.
- 2026-09-03: `800×600` 보정본의 Debug 빌드가 경고·오류 없이 통과했다. 같은 소스의 Release 설치기를 다시 만들고 종료 코드 0으로 설치했으며 사용자 데이터 48개·5,827,052 bytes를 보존했다. 설치 DLL과 publish DLL 일치 및 새 설치본 실행 응답을 확인했다.
- 2026-09-03: 사용자 릴리스 승인에 따라 기존 Preview 2를 보존하는 Windows 파일 버전 `1.6.0.17`, 태그 `windows-v1.6.0-preview.3`, 릴리스 이름 `MonglePet Windows 1.6.0 Preview 3`을 확정했다.

## 완료 결과

- 코드 구현과 자동 검증 완료. 실제 설치 직후 첫 실행·혼합 DPI·좁은 창 QA를 기다린다.

## 남은 위험 / 후속 작업

- 자동화된 테스트는 다양한 실제 Windows DPI와 Inno Setup 완료 화면의 포그라운드 실행 타이밍을 완전히 재현하지 못하므로 사용자 실제 QA가 필요하다.
