# MonglePet for Windows

Windows 버전의 플랫폼 디렉터리다. 첫 네이티브 솔루션과 공통 계약 테스트 기반이 준비되었으며 기준 기술은 **C# + .NET 10 LTS + WinUI 3 + Win32/Microsoft.UI.Composition**이다.

초기 지원 기준은 Windows 11 25H2 build 26200 이상과 x64다. Windows App SDK 2.3.1 Stable을 사용하며 개발·향후 자동 업데이트용 packaged MSIX와 첫 웹 Preview용 unpackaged self-contained EXE를 함께 지원한다. 순수 Domain과 패키지 계약은 xUnit으로 검증한다.

Windows 앱은 macOS 앱과 기능 동등성을 목표로 하되 네이티브 프로젝트로 별도 구현한다. 공유 범위는 `.monglepet` 패키지 규격, 권장 프로필, 스키마 fixture와 공통 테스트 시나리오로 제한한다.

설정 및 일반 앱 UI는 WinUI 3로 구현하고, 펫은 별도 Win32 `HWND`와 `Microsoft.UI.Composition` Visual layer로 표시한다. 행동 엔진과 데이터 처리는 C#에 유지하고 Win32 API는 창, notification area, 전면 앱·입력 없음과 다중 모니터 감지 경계에서 사용한다.

WPF는 초기 성능 비교 또는 호환성 대안일 뿐 최종 기준 기술이 아니다. C++/WinRT도 전체 앱 언어로 사용하지 않고 실제 Windows Release 측정에서 관리형 렌더링 병목이 확인된 모듈에만 후속 검토한다.

## 프로젝트 구조

- `MonglePet.slnx`: Windows 솔루션
- `src/MonglePet.Activity`: 전면 앱·입력 없음과 세션·전원 상태를 `ActivitySnapshot`으로 변환하는 Windows adapter
- `src/MonglePet.Core`: UI와 운영체제 API에서 분리한 행동 Domain
- `src/MonglePet.Packages`: `.monglepet` manifest, 디렉터리·ZIP 로더와 프레임 모델
- `src/MonglePet.PetLibrary`: LocalState 기반 설치·목록·교체·삭제와 ZIP importer
- `src/MonglePet.Settings`: schema-v1~v14 순차 마이그레이션, 멀티펫 instance·profile Domain 매핑·항목 복구와 원자적 JSON 저장
- `src/MonglePet.Shell`: notification area 메뉴와 모니터 작업 영역 배치의 Windows 전용 adapter
- `src/MonglePet.Windows`: packaged MSIX와 unpackaged self-contained 배포를 지원하는 WinUI 3 앱
- `tests`: Activity·Core·Packages·PetLibrary·Settings·Shell xUnit 테스트

현재 패키지 계층은 `pet.json` 구조 검증에 더해 디렉터리·ZIP의 경로 탈출, 링크, 허용 확장자, 압축·해제 크기, 엔트리 수와 압축률을 검사한다. 참조 파일의 존재와 PNG·WebP 컨테이너 형식·정적 이미지·크기·알파 선언도 검사하며, 선택한 atlas는 Windows 이미지 디코더가 `LoadedImageSurface`로 실제 디코딩한다. 설치 전 모든 미리보기·atlas의 실제 디코딩과 공통 WebP 오류 fixture는 후속 보강 범위다.

## 펫 오버레이와 화면 표시 설정

`MonglePet.Windows`는 설정 창과 별개로 Win32 `WS_POPUP` 오버레이를 만든다. 부모 HWND가 항상 위, 작업 표시줄 제외, 포커스 비활성화와 마우스 입력 통과를 담당하고, 내부 `ContentIsland`·`DesktopChildSiteBridge`가 `Microsoft.UI.Composition` 이미지 비주얼을 표시한다.

WinUI 화면에서 192px를 100%로 한 10~200% 펫 크기, 10~100% 기본 투명도, 입력 통과, 클릭 통과 중 마우스 겹침 투명도, nearest 픽셀 아트 렌더링과 표시·숨김을 즉시 변경한다. 값은 schema-v14의 활성 instance별 overlay에 원자적으로 저장되고 시작·펫 전환 뒤 복원되며, 높이는 현재 패키지 기본 모션 첫 프레임의 종횡비로 계산한다. 내장 펫은 Windows 사본 없이 공통 `shared/BuiltInPets/Mongle.monglepet`의 PNG atlas와 기본 모션을 manifest 프레임 좌표·시간에 맞춰 표시한다. notification area의 현재 화면 이동과 클릭 통과를 끈 overlay 드래그로 작업 영역 위치와 화면 식별자를 저장·복원한다. 최대 64px frame 알파 마스크가 aspect-fit 여백을 제외한 실제 표시 픽셀을 판정하며 기능이 꺼지면 디코딩과 100ms 포인터 관찰도 중지한다.

2026-08-08 x64 Release 고정 workload 30초 측정에서 CPU는 전체 시스템 기준 평균 0.017%(단일 코어 환산 0.103%), private memory 최대 100.2 MiB, 3D GPU 평균·최대 0%였다. 1프레임 정지 상태의 기준선이며 이동·말풍선·프레임 지연과 1시간 메모리 증가는 후속 workload에서 별도로 측정한다.

## 말풍선

말풍선 설정은 schema-v14 행동 프로필에 활성 펫별로 저장한다. 행동 루틴 진입 대사는 주기 대사보다 우선하고 같은 루틴에서는 한 번만 발생한다. 주기 대사는 순차·무작위 순서와 별도 간격을 사용하며, 각 대사는 지정 시간 뒤 닫거나 다음 대사까지 유지할 수 있다. 펫을 숨기거나 Windows가 잠금·절전에 들어가고 펫을 전환하면 현재 말풍선과 모든 timer를 즉시 정리한다.

표시는 펫 오버레이가 소유하는 별도 non-activating·click-through Win32 `WS_POPUP`에 WinUI 3 `DesktopWindowXamlSource`를 연결해 수행한다. 시스템·크림·밤·민트·복숭아·사용자 지정 테마, 불투명도·글자·여백·모서리·꼬리와 자동·위·아래 위치, 좌우 오프셋·간격을 지원하며 부모 이동과 모니터 작업 영역 경계를 따라 재배치한다. 설정 화면은 행동 대사와 주기 대사를 분리하고 저장 전 draft, 즉시 반영되는 사용·모양·위치 설정, 꼬리·정렬·상대 위치 미리보기를 제공한다. 실제 혼합 DPI·긴 대사 시각 QA와 이동 말풍선 workload는 최종 검증에 남아 있다.

## Notification area 빠른 제어

`MonglePet.Shell`은 `Shell_NotifyIcon` 아이콘과 네이티브 메뉴를 제공한다. 메뉴는 현재 펫 이름, 깨우기·재우기, 클릭 통과, 포인터가 있는 현재 화면으로 가져오기, 설정과 `MonglePet 종료` 순서이며 열 때마다 실제 앱 상태로 다시 구성한다. Explorer가 재시작되면 숨은 callback HWND의 `TaskbarCreated` 처리에서 같은 GUID의 아이콘을 다시 등록한다.

일반 설정의 로그인 자동 실행은 별도 JSON 값을 저장하지 않는다. packaged 앱은 MSIX `MonglePetStartupTask`, unpackaged 앱은 현재 사용자 Run 레지스트리의 인용된 현재 EXE 경로와 `--startup`을 사용한다. Run 값이 다른 경로를 가리키면 덮어쓰지 않고 비활성으로 표시하며, 로그인 실행에서는 설정창을 숨기고 펫과 notification area만 시작한다.

설정창 X 버튼은 창만 숨기므로 펫과 행동 runtime, notification area는 계속 실행한다. 아이콘 활성화 또는 설정 메뉴로 같은 WinUI 창을 다시 열고, 명시적 종료에서만 설정 Page의 timer·event와 장기 실행 자원·overlay를 정리한 뒤 마지막 WinUI 창을 닫는다. 종료 명령은 notification area의 native callback이 반환된 다음 UI queue에서 실행한다. packaged Release에서 모든 메뉴 상태와 명령, X 숨김·재열기, 현재 화면 위치의 재실행 복원과 완전 종료를 확인했다. 실제 Explorer 재시작과 혼합 DPI 다중 모니터 장비의 수동 QA는 남아 있다.

## 이동·드래그·쓰다듬기

순수 이동 Geometry가 Win32와 독립적으로 화면 safe bounds, 마우스 따라가기 목표, 자유 이동 무작위·전면 창 선호 목표, 마우스 도망 목표, 속도 advance와 Windows 좌상단 좌표 방향을 계산한다. `PetMovementRuntime`은 위치 고정, 마우스 따라가기, 자유 이동과 마우스 도망가기 모드를 schema-v14 활성 펫별 독립 설정과 전역 이동 범위에서 읽어 실제 overlay 좌표에 적용한다. 도망가기의 평상시 자유 이동도 일반 자유 이동과 별도 값을 소유하며 목표는 도착·범위 무효화·도망 상태 전환에서만 다시 고른다. 이동 중에는 16ms tick과 `double` 논리 위치를 사용하고 HWND에 적용할 때만 반올림해 저속 진행량을 보존한다. 모든 화면 범위는 가상 데스크톱의 모니터 사이 공간을 횡단할 수 있고 선택 모니터·사용자 영역만 지정 경계로 제한한다. 정지 포인터 관찰은 100ms, 환경 오류 재시도는 1초다.

이동 설정 UI에서 속도·마우스 거리·정지 반경·자유 이동 dwell·전면 앱 창 주변 선호·도망 거리와 속도·평상시 행동, 모든/선택/저장된 사용자 영역 범위, 모드별 fallback 모션과 쓰다듬기 모션을 선택한다. 저장된 방향 모션도 실제 적용 좌표 방향에 맞춰 사용한다. 전면 창 선호는 창 제목 없이 foreground PID와 보이는 일반 창의 DWM bounds만 최대 1초 캐시해 사용하며 전체 화면·작은 창·조회 실패는 작업 영역으로 복구한다. 자동 이동 좌표와 창 이력은 저장하지 않고 사용자 드래그 완료와 notification area 현재 화면 이동만 원점을 저장한다.

현재 펫의 실제 알파 표시 픽셀에 포인터가 직접 진입해 300ms 머무르면 쓰다듬기 모션을 한 번 재생하고 패널 이탈 뒤 다시 활성화한다. 도망가기와 사용자 드래그 중에는 차단하며 정지 포인터 아래로 펫이 이동한 경우에도 시작하지 않는다. 표시 우선순위는 쓰다듬기, 이동, 행동이며 쓰다듬기 완료 뒤 중단한 행동 시간축으로 복귀한다. 실제 듀얼 모니터 Release QA에서 `DISPLAY2(0, 0)`에서 `DISPLAY1(-1920, 297)`의 음수 좌표로 자유 이동하고 드래그 저장·재실행과 쓰다듬기 복귀를 확인했다. 전체 화면 전면 앱 fallback과 선호 끄기 복원도 실제 Release에서 확인했으며, 알파 쓰다듬기와 일반 창 foreground의 최종 물리 QA는 후속 보강이다.

현재 UI는 위치 고정·자유 이동·마우스 따라가기·마우스 도망가기 중 선택한 방식에 필요한 섹션만 표시한다. 공통 하나·4방향·8방향 이동 모션, 사용자 지정 영역과 모드별 쓰다듬기 설정을 편집할 수 있다.

## 행동 런타임과 기본 설정

`MonglePet.Core`의 순수 cycle scheduler가 모션 한 사이클, 단계별 `repeatCount`, 여러 단계와 루틴 반복을 계산한다. Windows runtime은 `Stopwatch` 단조 시간과 일회성 `DispatcherQueueTimer`로 경계에서만 다음 모션을 요청하며, 숨김 중에는 scheduler와 프레임 timer를 멈추고 다시 표시할 때 남은 시간부터 재개한다. 현재 펫 기본 모션 예약 참조와 누락 모션 fallback도 Composition 재생 경계에서 처리한다.

WinUI 행동 설정에서 현재 펫의 자동·직접 선택·복수 행동 랜덤 모드를 선택하고, 안정 ID와 변경 가능한 표시 이름을 가진 행동·단계·반복을 편집하면 schema-v14 전체 설정에 원자적으로 저장되고 즉시 재생에 반영된다. 자동 모드는 표시 및 이동·입력 없음·앱 사용 규칙을 사용자가 정한 종류 순서로 평가하며 입력 없음 규칙은 하나만 두고 1~86,400초를 입력한다. 랜덤 모드는 shuffle bag으로 선택 행동을 한 번씩 재생한 뒤 다시 섞는다. 기본 행동은 삭제를 막고 행동 삭제 시 이를 참조하는 규칙·대사·이동·쓰다듬기 설정을 함께 정리한다. 내장 펫과 설치 UUID별로 행동 프로필을 분리하며 펫 전환과 재실행 뒤 선택을 복원한다. 세션 잠금·절전 중에는 직접·랜덤 모드를 포함한 재생을 즉시 멈추고 activity polling도 중지한다.

Windows 앱 규칙 식별자는 package identity가 있으면 소문자 `pfn:<package-family-name>`, 일반 Win32 앱이면 소문자 `exe:<file-name>`이다. 규칙 편집기에서 이를 직접 입력하거나 현재 전면 앱 식별자를 채울 수 있고, 창 제목 없이 일반 최상위 창이 열린 앱을 이름·아이콘 목록에서 고르거나 표준 파일 선택기로 `.exe`를 명시적으로 선택할 수 있다. 전체 설치 앱·디스크·레지스트리는 스캔하지 않는다. 선택용 이름·아이콘·경로는 메모리에서만 사용하며 창 제목·문서명·브라우저 주소·실제 입력 내용과 실행 파일 전체 경로는 설정에 저장하지 않는다.

## 로컬 펫 라이브러리

packaged 앱은 `ApplicationData.Current.LocalFolder\MonglePet\Library\<installation-uuid>`, unpackaged 앱은 `%LOCALAPPDATA%\MonglePet\Library\<installation-uuid>`에 검증된 패키지를 설치한다. unpackaged 대상이 비어 있으면 알려진 기존 개발 MSIX `LocalState\MonglePet`을 staging으로 한 번만 복사하고 원본은 남긴다.

설치는 라이브러리와 같은 볼륨의 숨은 staging 디렉터리로 복사한 뒤 전체 패키지를 다시 검증하고 UUID 최종 경로로 rename한다. 같은 패키지 ID는 기본적으로 중복을 거부하며 별도 설치와 같은 ID 설치 교체를 명시적으로 지원한다. 교체 중 실패하면 기존 설치 backup을 복구하고, 손상된 설치와 남은 staging·backup은 사용 가능한 목록에서 제외한다.

개발 화면에서 `.monglepet 가져오기`로 아카이브를 선택하면 이름·버전·제작자·모션 수와 권장 설정을 먼저 검토한다. 권장 설정은 schema-v1~v10을 읽고 사용자가 선택한 경우에만 설치 UUID의 로컬 프로필로 복사한다. v9 이하에는 휴대 표시 설정이 없으므로 현재 표시값을 덮어쓰지 않는다. 중복이면 기존 설정을 기본 보존하는 교체 또는 권장 설정 선택을 유지하는 별도 설치를 결정할 수 있다. `현재 펫 내보내기`는 행동·랜덤 선택·규칙 종류 순서·네 독립 이동 설정·쓰다듬기·말풍선·휴대 표시 설정을 포함하며 `pfn:`/`exe:` 앱 규칙만 별도 동의로 추가한다.

`ApplicationData.Current.LocalFolder\MonglePet\settings.json`의 schema-v14는 `activePetInstances`, 독립 `behaviorProfiles`, `selectedPetInstanceID`를 저장한다. schema-v1부터 v11까지의 사용자 설정은 활성 인스턴스·프로필·알 수 없는 확장 필드를 보존하며 v12 안정 행동 참조, v13 랜덤 선택·머무르기, v14 독립 이동 설정으로 순차 변환한다. 잘못된 UUID·프로필 참조·표시 순서와 행동 참조는 손상된 항목만 복구한다. v1의 유지 시간은 당시 선택 펫 manifest의 모션 한 사이클로 반복 횟수를 계산하며, 선택 펫 정의 자체를 얻지 못하면 원본을 보존하고 쓰기를 차단한다. 전체 설정 저장은 유효하지 않은 Domain 값을 거부하고 살아남은 항목의 알 수 없는 확장 필드를 보존한다. 손상·5MiB 초과 파일은 격리하고 미래 schema도 원본 보호를 위해 쓰기를 차단한다.

packaged 앱을 실행하려면 먼저 빌드 결과의 loose AppX를 개발 등록한 뒤 AUMID로 시작한다. 현재 `Microsoft.Windows.SDK.BuildTools.WinApp` 0.5.0의 `dotnet run` helper는 이 .NET 10 프로젝트에서 `ErrorStartingProcess`를 반환할 수 있으므로 실제 앱 검증 기준으로 사용하지 않는다.

```powershell
dotnet build apps/windows/src/MonglePet.Windows/MonglePet.Windows.csproj --configuration Debug
$manifestPath = Resolve-Path 'apps/windows/src/MonglePet.Windows/bin/Debug/net10.0-windows10.0.26100.0/win-x64/AppxManifest.xml'
Add-AppxPackage -Register $manifestPath
Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\4B7E245F-A59A-4E0F-84D7-52B511356256_1z32rh13vfry6!App'
```

## 웹에서 펫 가져오기

`펫 보관함`은 MonglePet 웹 목록 열기, 공개 상세 주소 직접 가져오기, Windows의
로컬 `.monglepet` 선택과 현재 펫 내보내기를 독립된 세로 섹션으로 제공한다.
Debug의 웹 버튼은 개발 목록, Release는 운영 목록을 연다. 주소 가져오기는
`dev.mapleroom.kr`과 `mapleroom.kr`의 정확한 상세 URL만 허용하고 API envelope,
앱 호환 버전, 상세·다운로드 metadata, same-origin HTTPS redirect, 20MiB 상한과
실제 크기·SHA-256을 검증한다. 검증된 임시 파일은 기존 가져오기 검토·중복 흐름이
끝날 때까지만 유지하며 다운로드·검토·취소만으로 선택 인스턴스를 변경하지 않는다.
현재 앱보다 높은 최소 버전은 설치를 막지 않고 기능 차이 안내와 공식 다운로드 페이지
버튼을 표시하며, 업데이트 조회·자동 다운로드는 수행하지 않는다.

packaged 앱은 manifest의 `monglepet` protocol을, unpackaged 설치기는 현재 사용자
`Software\Classes\monglepet` handler를 사용한다. unpackaged 실행 중 두 번째 요청은
기존 AppInstance와 notification area HWND로 전달한다. 제거 시 현재 command가 해당
설치 EXE와 일치할 때만 protocol tree를 삭제한다.

사용자 펫은 macOS와 같은 schema-v1 `monglepet-editor.json` marker로 편집 가능 상태를 식별하며 새 펫 만들기, 정보 수정, 삭제와 애니메이션 추가·수정·삭제를 지원한다. 가져온 패키지는 읽기 전용이고 편집하려면 새 package ID의 독립 사본을 만든다. 설정의 펫 보관함은 `웹에서 펫 가져오기 / Windows의 패키지 가져오기 / 현재 펫 내보내기` 흐름을 제공한다. 편집은 별도 staging에서 전체 loader 검증 후 같은 설치 UUID에 원자적으로 반영하며 공유 파일에는 editor marker를 포함하지 않는다.

애니메이션·PNG·스프라이트의 staged 편집은 서로 중첩된 `ContentDialog`가 아니라 독립 owned WinUI 창에서 진행하므로 파일 선택 뒤에도 부모 편집 상태를 안전하게 유지한다. PNG 편집기는 왼쪽 원본 crop, 오른쪽 상단 고정 결과와 오른쪽 하단 독립 설정 스크롤을 사용하고 여러 파일 누적 추가, 투명 여백 맞춤, 일괄 flip과 공통 캔버스 배치를 제공한다. 스프라이트 편집기는 알파·모서리 배경 기반 자동 경계와 균등 격자, 독립 경계 편집, 읽기·클릭 순서, frame별 flip과 선택적 단색 배경 제거를 제공한다. 두 경로는 `crop → flip → 공통 캔버스 → atlas` 픽셀 경로를 공유하고 새 프레임은 450ms로 시작한다. 편집 이력은 패키지에 저장하지 않고 확정된 atlas 픽셀만 공유한다.

## 빌드와 테스트

저장소 루트에서 실행한다.

```powershell
dotnet restore apps/windows/MonglePet.slnx
dotnet build apps/windows/MonglePet.slnx --configuration Debug --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Debug --no-build --no-restore --maxcpucount:1
```

SDK는 루트 `global.json`의 .NET 10.0.302로 고정한다. .NET 10이 제공하는 안정 Windows API 계약은 build 26100을 대상으로 컴파일하며, 실제 제품 설치 최소 버전 build 26200은 `Package.appxmanifest`의 MSIX 대상 제품군에서 적용한다.

2026-08-25 Windows `1.3.0.13` Preview는 x64 Debug·Release 전체 빌드와 Activity 27개, Core 38개, Packages 22개, PetLibrary 87개, Settings 72개, Shell 20개로 각 구성 총 266개 xUnit 테스트가 통과했다. Release loose AppX·unpackaged publish·실제 설치본의 공통 built-in 13개 파일은 기준본과 같은 tree SHA-256 `08E8E09643B0CEE5FED8D8246729EBB5CF00E18B72871EA6FCD7BE26DB76DB59`다. packaged `1.2.0.13→1.3.0.13` 업데이트는 LocalState 22개 파일을 보존했고 최종 unpackaged 설치기도 사용자 데이터 22개 파일의 inventory digest를 보존한 채 정상 실행됐다. 미수정 built-in 중립 프로필만 새 기본값으로 이관되고 설치 펫 프로필·라이브러리 자산은 유지됐다. 64,866,058 bytes 설치기 SHA-256 `5F8A14314447F70C74704793BC5ED0EA8744DF0276303470D366500D4777B808`을 `windows-v1.3.0-preview.1`로 게시하고 원격 자산을 재검증했다. 편집 대화상자의 실제 최소 높이·가로/세로 긴 시트·혼합 DPI·키보드/Narrator·큰 이미지 반복 drag, 운영 URL과 Windows→macOS 왕복은 최종 수동 QA로 남아 있다.

2026-08-27 Windows `1.4.0.13` 후보는 Debug·Release 전체 빌드와 Activity 27개, Core 56개, Packages 28개, PetLibrary 88개, Settings 77개, Shell 20개로 각 구성 총 296개 xUnit 테스트가 통과했다. 완료 랜덤 행동과 1초 activity 경계가 겹쳐 timer가 멈추던 경합과 callback 지연으로 행동·frame 시간이 벌어지는 현상을 수정했다. 랜덤은 이동 중 멈추고 이동 종료 시 shuffle bag의 다음 행동을 첫 frame부터 시작해 과거 행동의 짧은 나머지와 가려진 중간 frame을 표시하지 않는다. atlas 준비 전에는 표시 시간을 소비하지 않으며 최근 atlas 16개를 제한 재사용한다. 설정창은 행동·이동·말풍선·오버레이 frame·자원 경고의 실시간 구독과 활성 펫 runtime 문구를 모두 제거하고 저장된 표시 상태·이동 방식만 표시한다. 고정 위치 저장은 설정 화면 갱신 없이 유지한다. 행동 루틴 생성 입력은 별도 카드와 Enter 확정을 제공하고, 이름 변경은 현재 이름이 채워진 대화상자에서 처리하며 애니메이션 단계는 선택 이름이 항상 보이도록 폭과 바인딩을 정리했다. loose AppX와 unpackaged publish의 공통 built-in 16개 파일은 기준본과 같은 tree SHA-256 `0463D7B6897E8D14C3BA053F953D69DC49FB31930DB1D03D3797B9EC37B95503`다. packaged `1.3.0.13→1.4.0.13`은 LocalState 22개 파일을 그대로 보존했고 unpackaged 실제 실행은 schema-v11의 3개 instance·4개 profile·라이브러리 21개를 schema-v14로 보존 이관했다. 설정창을 닫고 도망가기·자유 이동·고정 3펫을 실행한 Release 5분은 평균 CPU 0.680%, private memory 126.51→126.51MiB·최대 129.62MiB, 무응답 0회였다. 혼합 100%·150%·200% DPI, Narrator, 큰 이미지 반복 drag와 Windows→macOS 실제 교차 왕복은 릴리스 전 수동 QA로 남아 있으며 릴리스는 아직 게시하지 않았다.

2026-08-28 후속 후보는 행동 루틴의 상시 이름 입력 카드를 단일 생성 대화상자로 정리하고, 단계 애니메이션을 현재 이름이 표시되는 버튼과 별도 선택 목록으로 바꿔 `ComboBox` placeholder 회귀를 제거했다. 설정창의 남은 runtime 상태 구독도 제거했다. 최종 미서명 설치기는 65,260,678 bytes, SHA-256 `7F608226091564AC0B2841E99DA6CF60FFF542EC5FBE4AACAC492C11B8FBC30A`이며 기존 설치본 위 업그레이드에서 사용자 데이터 40개 파일의 inventory digest를 보존하고 설치본 `1.4.0.13` 실행 응답을 확인했다.

소스 커밋 `7e7f3d9`를 태그 `windows-v1.4.0-preview.1`의 GitHub Pre-release로 게시했다. 원격에서 다시 받은 설치기 크기와 SHA-256, `SHA256SUMS.txt` 내용이 로컬 최종 산출물과 일치한다. 혼합 DPI·Narrator·큰 이미지 반복 편집·Windows→macOS 왕복과 제거 QA는 후속 사용자 검증으로 계속 추적한다.

Windows 기반부터 로컬 공유까지의 완료 기록은 `../../AGENTS/work_plans/INDEX.md`에서 확인한다. 이번 가져오기 검토·권장 설정·내보내기 구현은 `../../AGENTS/work_plans/tasks/2026-08-09-windows-local-sharing.md`에 정리했다. 다음 구현을 시작하기 전 이 디렉터리의 `AGENTS.md`와 새 작업 계획을 함께 확인한다.

## EXE 설치기 만들기

Inno Setup 6.7.3 이상을 설치한 뒤 저장소 루트에서 실행한다. 첫 실행은 self-contained publish를 새로 만들며, 이미 검증된 publish를 재사용할 때만 `-SkipPublish`를 사용한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\apps\windows\scripts\New-WindowsExeInstaller.ps1' `
    -AllowUnsigned
```

기본 출력은 `dist\windows-exe\<version>\MonglePet-Windows-<version>-x64-Setup.exe`와 `SHA256SUMS.txt`다. 같은 버전을 의도적으로 다시 만들 때만 `-OverwriteVersion`을 추가한다. 미서명 Preview는 SmartScreen 경고가 표시될 수 있으며 설치기와 앱의 게시자 신원을 증명하지 못한다.

설치기는 관리자 권한 없이 `%LOCALAPPDATA%\Programs\MonglePet`에 앱과 .NET·Windows App SDK 런타임을 설치한다. 사용자는 새 버전 설치기를 다시 실행해 수동 업데이트하며, 제거해도 `%LOCALAPPDATA%\MonglePet`의 설정과 펫은 남는다.

## 웹 배포 준비

자체 웹사이트와 GitHub Releases용 Windows 배포 구조, 첫 EXE Preview와 향후 코드 서명·App Installer 자동 업데이트 절차는 `distribution/README.md`에 정리했다. `scripts/New-WindowsExeInstaller.ps1`은 EXE와 SHA256SUMS를 만들고, `scripts/New-WindowsReleaseArtifacts.ps1`은 서명된 MSIX 내부 identity를 기준으로 App Installer 산출물을 만들며 개발용 Publisher, 미서명 패키지와 타임스탬프 누락을 기본적으로 거부한다.
