# MonglePet for Windows

Windows 버전의 플랫폼 디렉터리다. 첫 네이티브 솔루션과 공통 계약 테스트 기반이 준비되었으며 기준 기술은 **C# + .NET 10 LTS + WinUI 3 + Win32/Microsoft.UI.Composition**이다.

초기 지원 기준은 Windows 11 25H2 build 26200 이상과 x64다. Windows App SDK 2.3.1 Stable을 사용하는 packaged WinUI 3·MSIX 앱으로 시작하고, 순수 Domain과 패키지 계약은 xUnit으로 검증한다.

Windows 앱은 macOS 앱과 기능 동등성을 목표로 하되 네이티브 프로젝트로 별도 구현한다. 공유 범위는 `.monglepet` 패키지 규격, 권장 프로필, 스키마 fixture와 공통 테스트 시나리오로 제한한다.

설정 및 일반 앱 UI는 WinUI 3로 구현하고, 펫은 별도 Win32 `HWND`와 `Microsoft.UI.Composition` Visual layer로 표시한다. 행동 엔진과 데이터 처리는 C#에 유지하고 Win32 API는 창, notification area, 전면 앱·입력 없음과 다중 모니터 감지 경계에서 사용한다.

WPF는 초기 성능 비교 또는 호환성 대안일 뿐 최종 기준 기술이 아니다. C++/WinRT도 전체 앱 언어로 사용하지 않고 실제 Windows Release 측정에서 관리형 렌더링 병목이 확인된 모듈에만 후속 검토한다.

## 프로젝트 구조

- `MonglePet.slnx`: Windows 솔루션
- `src/MonglePet.Activity`: 전면 앱·입력 없음과 세션·전원 상태를 `ActivitySnapshot`으로 변환하는 Windows adapter
- `src/MonglePet.Core`: UI와 운영체제 API에서 분리한 행동 Domain
- `src/MonglePet.Packages`: `.monglepet` manifest, 디렉터리·ZIP 로더와 프레임 모델
- `src/MonglePet.PetLibrary`: LocalState 기반 설치·목록·교체·삭제와 ZIP importer
- `src/MonglePet.Settings`: schema-v1~v10 순차 마이그레이션, schema-v10 전체 Domain 매핑·항목 복구와 원자적 JSON 저장
- `src/MonglePet.Shell`: notification area 메뉴와 모니터 작업 영역 배치의 Windows 전용 adapter
- `src/MonglePet.Windows`: packaged WinUI 3·MSIX 앱
- `tests`: Activity·Core·Packages·PetLibrary·Settings·Shell xUnit 테스트

현재 패키지 계층은 `pet.json` 구조 검증에 더해 디렉터리·ZIP의 경로 탈출, 링크, 허용 확장자, 압축·해제 크기, 엔트리 수와 압축률을 검사한다. 참조 파일의 존재와 PNG·WebP 컨테이너 형식·정적 이미지·크기·알파 선언도 검사하며, 선택한 atlas는 Windows 이미지 디코더가 `LoadedImageSurface`로 실제 디코딩한다. 설치 전 모든 미리보기·atlas의 실제 디코딩과 공통 WebP 오류 fixture는 후속 보강 범위다.

## 펫 오버레이와 화면 표시 설정

`MonglePet.Windows`는 설정 창과 별개로 Win32 `WS_POPUP` 오버레이를 만든다. 부모 HWND가 항상 위, 작업 표시줄 제외, 포커스 비활성화와 마우스 입력 통과를 담당하고, 내부 `ContentIsland`·`DesktopChildSiteBridge`가 `Microsoft.UI.Composition` 이미지 비주얼을 표시한다.

WinUI 화면에서 96–384px 펫 너비, 10–100% 기본 투명도, 입력 통과, 클릭 통과 중 마우스 겹침 투명도, nearest 픽셀 아트 렌더링과 표시·숨김을 즉시 변경한다. 값은 schema-v10 LocalState에 원자적으로 저장되고 시작·펫 전환 뒤 복원되며, 높이는 현재 패키지 기본 모션 첫 프레임의 종횡비로 계산한다. 공통 읽기 전용 `.monglepet` 샘플의 PNG atlas와 기본 모션을 manifest 프레임 좌표·시간에 맞춰 표시한다. notification area의 현재 화면 이동과 클릭 통과를 끈 overlay 드래그로 작업 영역 위치와 화면 식별자를 저장·복원한다. 최대 64px frame 알파 마스크가 aspect-fit 여백을 제외한 실제 표시 픽셀을 판정하며 기능이 꺼지면 디코딩과 100ms 포인터 관찰도 중지한다. 실제 다중 프레임·WebP QA는 아직 남아 있다.

2026-08-08 x64 Release 고정 workload 30초 측정에서 CPU는 전체 시스템 기준 평균 0.017%(단일 코어 환산 0.103%), private memory 최대 100.2 MiB, 3D GPU 평균·최대 0%였다. 1프레임 정지 상태의 기준선이며 이동·말풍선·프레임 지연과 1시간 메모리 증가는 후속 workload에서 별도로 측정한다.

## 말풍선

말풍선 설정은 schema-v10 행동 프로필에 펫별로 저장한다. 행동 루틴 진입 대사는 주기 대사보다 우선하고 같은 루틴에서는 한 번만 발생한다. 주기 대사는 순차·무작위 순서와 별도 간격을 사용하며, 각 대사는 지정 시간 뒤 닫거나 다음 대사까지 유지할 수 있다. 펫을 숨기거나 Windows가 잠금·절전에 들어가고 펫을 전환하면 현재 말풍선과 모든 timer를 즉시 정리한다.

표시는 펫 오버레이가 소유하는 별도 non-activating·click-through Win32 `WS_POPUP`에 WinUI 3 `DesktopWindowXamlSource`를 연결해 수행한다. 시스템·크림·밤·민트·복숭아·사용자 지정 테마, 불투명도·글자·여백·모서리·꼬리와 자동·위·아래 위치, 좌우 오프셋·간격을 지원하며 부모 이동과 모니터 작업 영역 경계를 따라 재배치한다. 설정 화면은 행동 대사와 주기 대사를 분리하고 저장 전 draft, 즉시 반영되는 사용·모양·위치 설정, 꼬리·정렬·상대 위치 미리보기를 제공한다. 실제 혼합 DPI·긴 대사 시각 QA와 이동 말풍선 workload는 최종 검증에 남아 있다.

## Notification area 빠른 제어

`MonglePet.Shell`은 `Shell_NotifyIcon` 아이콘과 네이티브 메뉴를 제공한다. 메뉴는 현재 펫 이름, 깨우기·재우기, 클릭 통과, 포인터가 있는 현재 화면으로 가져오기, 설정과 `MonglePet 종료` 순서이며 열 때마다 실제 앱 상태로 다시 구성한다. Explorer가 재시작되면 숨은 callback HWND의 `TaskbarCreated` 처리에서 같은 GUID의 아이콘을 다시 등록한다.

일반 설정의 로그인 자동 실행은 별도 JSON 값을 저장하지 않고 MSIX `MonglePetStartupTask`의 실제 Windows 상태를 사용한다. 사용자가 Windows 시작 앱 설정에서 끈 상태는 앱이 강제로 덮어쓰지 않으며 해당 설정 화면을 여는 복구 버튼을 표시한다.

설정창 X 버튼은 창만 숨기므로 펫과 행동 runtime, notification area는 계속 실행한다. 아이콘 활성화 또는 설정 메뉴로 같은 WinUI 창을 다시 열고, 명시적 종료에서만 설정 Page의 timer·event와 장기 실행 자원·overlay를 정리한 뒤 마지막 WinUI 창을 닫는다. 종료 명령은 notification area의 native callback이 반환된 다음 UI queue에서 실행한다. packaged Release에서 모든 메뉴 상태와 명령, X 숨김·재열기, 현재 화면 위치의 재실행 복원과 완전 종료를 확인했다. 실제 Explorer 재시작과 혼합 DPI 다중 모니터 장비의 수동 QA는 남아 있다.

## 이동·드래그·쓰다듬기

순수 이동 Geometry가 Win32와 독립적으로 화면 safe bounds, 마우스 따라가기 목표, 자유 이동 무작위·전면 창 선호 목표, 마우스 도망 목표, 속도 advance와 Windows 좌상단 좌표 방향을 계산한다. `PetMovementRuntime`은 위치 고정, 마우스 따라가기, 자유 이동과 마우스 도망가기 모드를 schema-v10 펫별 설정과 전역 이동 범위에서 읽어 실제 overlay 좌표에 적용한다. 이동 중에는 16ms tick과 `double` 논리 위치를 사용하고 HWND에 적용할 때만 반올림해 저속 진행량을 보존한다. 모든 화면 범위는 가상 데스크톱의 모니터 사이 공간을 횡단할 수 있고 선택 모니터·사용자 영역만 지정 경계로 제한한다. 정지 포인터 관찰은 100ms, 환경 오류 재시도는 1초다.

이동 설정 UI에서 속도·마우스 거리·정지 반경·자유 이동 dwell·전면 앱 창 주변 선호·도망 거리와 속도·평상시 행동, 모든/선택/저장된 사용자 영역 범위, 모드별 fallback 모션과 쓰다듬기 모션을 선택한다. 저장된 방향 모션도 실제 적용 좌표 방향에 맞춰 사용한다. 전면 창 선호는 창 제목 없이 foreground PID와 보이는 일반 창의 DWM bounds만 최대 1초 캐시해 사용하며 전체 화면·작은 창·조회 실패는 작업 영역으로 복구한다. 자동 이동 좌표와 창 이력은 저장하지 않고 사용자 드래그 완료와 notification area 현재 화면 이동만 원점을 저장한다.

현재 펫의 실제 알파 표시 픽셀에 포인터가 직접 진입해 300ms 머무르면 쓰다듬기 모션을 한 번 재생하고 패널 이탈 뒤 다시 활성화한다. 도망가기와 사용자 드래그 중에는 차단하며 정지 포인터 아래로 펫이 이동한 경우에도 시작하지 않는다. 표시 우선순위는 쓰다듬기, 이동, 행동이며 쓰다듬기 완료 뒤 중단한 행동 시간축으로 복귀한다. 실제 듀얼 모니터 Release QA에서 `DISPLAY2(0, 0)`에서 `DISPLAY1(-1920, 297)`의 음수 좌표로 자유 이동하고 드래그 저장·재실행과 쓰다듬기 복귀를 확인했다. 전체 화면 전면 앱 fallback과 선호 끄기 복원도 실제 Release에서 확인했으며, 알파 쓰다듬기와 일반 창 foreground의 최종 물리 QA는 후속 보강이다.

현재 UI는 위치 고정·자유 이동·마우스 따라가기·마우스 도망가기 중 선택한 방식에 필요한 섹션만 표시한다. 공통 하나·4방향·8방향 이동 모션, 사용자 지정 영역과 모드별 쓰다듬기 설정을 편집할 수 있다.

## 행동 런타임과 기본 설정

`MonglePet.Core`의 순수 cycle scheduler가 모션 한 사이클, 단계별 `repeatCount`, 여러 단계와 루틴 반복을 계산한다. Windows runtime은 `Stopwatch` 단조 시간과 일회성 `DispatcherQueueTimer`로 경계에서만 다음 모션을 요청하며, 숨김 중에는 scheduler와 프레임 timer를 멈추고 다시 표시할 때 남은 시간부터 재개한다. 현재 펫 기본 모션 예약 참조와 누락 모션 fallback도 Composition 재생 경계에서 처리한다.

WinUI 행동 설정에서 현재 펫의 자동·수동 모드와 수동 루틴을 선택하고, 루틴·단계·반복과 앱·입력 없음 자동 규칙을 생성·수정·삭제하면 schema-v10 전체 설정에 원자적으로 저장되고 즉시 재생에 반영된다. 기본 루틴은 삭제를 막고 루틴 삭제 시 이를 참조하는 규칙·행동 대사를 함께 정리한다. 내장 펫과 설치 UUID별로 행동 프로필을 분리하며 펫 전환과 재실행 뒤 선택을 복원한다. 자동 모드는 1초 간격의 전면 앱·입력 없음 snapshot으로 규칙을 평가하고, 세션 잠금·절전 중에는 수동 모드를 포함한 재생을 즉시 멈춘다. 숨김·잠금·절전 중에는 activity polling도 중지한다.

Windows 앱 규칙 식별자는 package identity가 있으면 소문자 `pfn:<package-family-name>`, 일반 Win32 앱이면 소문자 `exe:<file-name>`이다. 규칙 편집기에서 이를 직접 입력하거나 현재 전면 앱 식별자를 채울 수 있고, 창 제목 없이 일반 최상위 창이 열린 앱을 이름·아이콘 목록에서 고르거나 표준 파일 선택기로 `.exe`를 명시적으로 선택할 수 있다. 전체 설치 앱·디스크·레지스트리는 스캔하지 않는다. 선택용 이름·아이콘·경로는 메모리에서만 사용하며 창 제목·문서명·브라우저 주소·실제 입력 내용과 실행 파일 전체 경로는 설정에 저장하지 않는다.

## 로컬 펫 라이브러리

packaged 앱은 `ApplicationData.Current.LocalFolder\MonglePet\Library\<installation-uuid>`에 검증된 패키지를 설치한다. 일반 `%LOCALAPPDATA%\MonglePet` 경로는 MSIX가 `LocalCache`로 가상화하므로 직접 사용하지 않는다.

설치는 라이브러리와 같은 볼륨의 숨은 staging 디렉터리로 복사한 뒤 전체 패키지를 다시 검증하고 UUID 최종 경로로 rename한다. 같은 패키지 ID는 기본적으로 중복을 거부하며 별도 설치와 같은 ID 설치 교체를 명시적으로 지원한다. 교체 중 실패하면 기존 설치 backup을 복구하고, 손상된 설치와 남은 staging·backup은 사용 가능한 목록에서 제외한다.

개발 화면에서 `.monglepet 가져오기`로 아카이브를 선택하면 이름·버전·제작자·모션 수와 권장 설정을 먼저 검토한다. 권장 설정은 schema-v1~v7을 읽고 사용자가 선택한 경우에만 설치 UUID의 로컬 프로필로 복사한다. 중복이면 기존 설정을 기본 보존하는 교체 또는 권장 설정 선택을 유지하는 별도 설치를 결정할 수 있다. `현재 펫 내보내기`는 공유 권한 확인 후 canonical manifest·미리보기·참조 atlas와 선택 권장 설정만 ZIP에 넣고 전체 왕복 검증 뒤 저장한다.

선택 설치 UUID는 `ApplicationData.Current.LocalFolder\MonglePet\settings.json`의 schema-v10 `selectedPetInstallationID`에 저장한다. 시작 시 저장한 설치를 우선 복원하고, 사라진 설치는 남은 첫 설치 또는 bundled 샘플로 복구한다. schema-v1부터 v9까지는 기존 필드와 알 수 없는 확장 필드를 보존하며 v10으로 순차 변환한다. v1의 유지 시간은 당시 선택 펫 manifest의 모션 한 사이클로 반복 횟수를 계산하며, 선택 펫 정의 자체를 얻지 못하면 원본을 보존하고 쓰기를 차단한다. schema-v10은 overlay, 행동 루틴·규칙, 이동·방향 모션, 쓰다듬기와 말풍선 정책·대사·테마·배치를 Domain 모델로 읽고 잘못된 항목만 독립 복구한다. 전체 설정 저장은 유효하지 않은 Domain 값을 거부하고 살아남은 항목의 알 수 없는 확장 필드를 보존한다. 손상·5MiB 초과 파일은 격리하고 미래 schema도 원본 보호를 위해 쓰기를 차단한다. 화면 표시와 행동 루틴·규칙 WinUI·런타임 적용을 완료했으며 실제 파일 선택 대화상자 수동 QA는 후속 범위다.

packaged 앱을 실행하려면 먼저 빌드 결과의 loose AppX를 개발 등록한 뒤 AUMID로 시작한다. 현재 `Microsoft.Windows.SDK.BuildTools.WinApp` 0.5.0의 `dotnet run` helper는 이 .NET 10 프로젝트에서 `ErrorStartingProcess`를 반환할 수 있으므로 실제 앱 검증 기준으로 사용하지 않는다.

```powershell
dotnet build apps/windows/src/MonglePet.Windows/MonglePet.Windows.csproj --configuration Debug
$manifestPath = Resolve-Path 'apps/windows/src/MonglePet.Windows/bin/Debug/net10.0-windows10.0.26100.0/win-x64/AppxManifest.xml'
Add-AppxPackage -Register $manifestPath
Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\4B7E245F-A59A-4E0F-84D7-52B511356256_1z32rh13vfry6!App'
```

사용자 펫은 macOS와 같은 schema-v1 `monglepet-editor.json` marker로 편집 가능 상태를 식별하며 새 펫 만들기, 정보 수정, 삭제와 애니메이션 추가·수정·삭제를 지원한다. 가져온 패키지는 읽기 전용이고 편집하려면 새 package ID의 독립 사본을 만든다. 설정의 펫 탭은 `MonglePet 패키지 / 패키지 가져오기 / 현재 펫 내보내기` 흐름을 제공한다. 편집은 별도 staging에서 전체 loader 검증 후 같은 설치 UUID에 원자적으로 반영하며 공유 파일에는 editor marker를 포함하지 않는다.

## 빌드와 테스트

저장소 루트에서 실행한다.

```powershell
dotnet restore apps/windows/MonglePet.slnx
dotnet build apps/windows/MonglePet.slnx --configuration Debug --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Debug --no-build --no-restore --maxcpucount:1
```

SDK는 루트 `global.json`의 .NET 10.0.302로 고정한다. .NET 10이 제공하는 안정 Windows API 계약은 build 26100을 대상으로 컴파일하며, 실제 제품 설치 최소 버전 build 26200은 `Package.appxmanifest`의 MSIX 대상 제품군에서 적용한다.

2026-08-09 기준 x64 Debug·Release 전체 빌드와 Activity 27개, Core 38개, Packages 18개, PetLibrary 18개, Settings 58개, Shell 8개로 총 167개 xUnit 테스트가 통과했다. startup task와 펫 편집·로컬 공유 기능을 포함한 1.0.0.13 x64 Release MSIX도 생성됐으며 로컬 `mspdbcmf.exe` 부재로 symbols package만 생략됐다. Windows 설정 화면은 macOS와 같은 6개 기능 구조와 사용자 문구를 따르고, 펫·애니메이션 관리, 모드별 이동 설정, 행동·입력 없음 규칙과 말풍선 대사·위치 미리보기를 제공한다. 설정 콘텐츠는 Mica 위의 중앙 반응형 최대 폭, 탭별 아이콘 헤더와 20px 카드·14px 하위 카드 계층을 사용해 넓은 창의 빈 공간과 왼쪽 쏠림을 줄인다. 말풍선 본체와 꼬리는 하나의 연속 외곽선으로 그리며, 꼬리는 고정 높이를 유지한 채 설정 간격에 따라 말풍선과 함께 이동한다. XAML Island 측정 실패는 글자·여백 기반 안전 크기로 복구한다. `다음 대사까지 유지` 행동 대사 중에도 주기 대사가 예약되며 주기 대기 timer는 설정창 가시성과 분리한다. 서로 다른 이미지 atlas의 행동 전환은 이전 프레임을 유지한 채 새 surface를 준비해 투명 번쩍임을 막고, notification area 메뉴가 닫힌 뒤 설정창을 전면 활성화한다.

Windows 기반부터 로컬 공유까지의 완료 기록은 `../../AGENTS/work_plans/INDEX.md`에서 확인한다. 이번 가져오기 검토·권장 설정·내보내기 구현은 `../../AGENTS/work_plans/tasks/2026-08-09-windows-local-sharing.md`에 정리했다. 다음 구현을 시작하기 전 이 디렉터리의 `AGENTS.md`와 새 작업 계획을 함께 확인한다.
