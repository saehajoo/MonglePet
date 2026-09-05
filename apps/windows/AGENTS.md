# MonglePet Windows Instructions

## 적용 범위

이 파일은 `apps/windows/` 아래의 후속 Windows 앱 작업에 적용한다. 저장소 공통 원칙과 데이터 규격은 루트 `../../AGENTS.md`와 `../../AGENTS/` 문서를 따른다.

## 현재 상태

- Windows 앱은 개발 도구, 첫 WinUI 솔루션과 공통 계약 테스트 기반을 준비했다.
- 기준 기술은 C#·.NET·WinUI 3와 별도 Win32/Composition 펫 오버레이로 확정했다.
- 최소 Windows 버전은 Windows 11 25H2 build 26200, 런타임은 .NET 10 LTS, Windows App SDK는 2.3.1 Stable, 초기 대상은 x64로 확정했다.
- 초기 앱은 packaged WinUI 3·MSIX의 단일 full-trust 프로세스로 시작했으며, 첫 웹 Preview를 위해 같은 실행 파일의 package identity 없는 self-contained EXE 설치 채널도 지원한다. Core·패키지 테스트는 xUnit을 사용한다.
- 첫 작업 계획은 `../../AGENTS/work_plans/tasks/2026-08-08-windows-foundation-and-overlay.md`다.
- 현재 구현은 행동 결정기와 cycle scheduler, Windows 전면 앱·입력 없음·세션·전원 활동 감지, 안전한 디렉터리·ZIP 패키지 로더, LocalState 펫 라이브러리, schema-v1~v10 순차 이관과 schema-v11 활성 인스턴스·독립 프로필·선택 참조 Domain 매핑·항목 복구·원자적 전체 저장, 파일 선택 가져오기·활성화·삭제 개발 UI, Win32/ContentIsland Composition 모션 재생, 화면 표시 설정과 자동·수동 모드·루틴 단계·자동 규칙 전체 편집 WinUI, notification area 빠른 제어, 네 이동 모드·다중 모니터·드래그, 실제 frame 알파 기반 호버 쓰다듬기·겹침 투명화와 전면 앱 대표 창 선호까지다. 실제 Release 고정·포인터·전면 창 감지 workload, LocalState 시작 복구와 v1 packaged 마이그레이션, 행동 편집·전환·숨김·재실행 복원, 창 제목 없는 실행 중 일반 앱 이름·아이콘 선택, PFN 규칙 저장과 `.exe` 파일 선택·Win32 전면 앱 전환, 앱·입력 없음 자동 규칙과 잠금·절전 pause, notification area 빠른 제어, 음수 좌표 화면 자유 이동·드래그 저장·쓰다듬기 행동 복귀, 투명 모서리·불투명 중앙 겹침 판정과 전체 화면 대표 창 fallback QA를 통과했다. 실제 Explorer 재시작·혼합 DPI 다중 모니터와 물리 잠금·절전 복귀 QA, 알파 쓰다듬기·일반 창 foreground 최종 물리 QA, 설치 전 전 이미지 실제 디코딩, 실제 다중 프레임·WebP와 말풍선 workload는 후속 단계다.
- 말풍선은 행동 우선·주기/표시 일회성 timer, 순차·무작위 목록, 닫기·유지 정책과 재우기·잠금·절전·펫 전환 정리를 순수 runtime으로 구현했다. 펫 HWND가 소유하는 별도 입력 통과 Win32/XAML Island 창이 preset·사용자 테마와 자동·위·아래 경계 배치를 표시한다. WinUI 설정은 행동 대사와 주기 대사를 분리하고 draft 저장·취소, 즉시 설정 저장, 꼬리·정렬·상대 위치 미리보기를 제공한다. 실제 시각·혼합 DPI·성능 QA는 남아 있다.
- 로컬 공유는 설치 전 패키지·권장 설정 검토, schema-v1~v7 호환과 설치 UUID 프로필 적용, 검토 후 SHA-256 원본 변경 거부를 구현했다. 내보내기는 공유 권한 확인 후 canonical manifest·참조 자산·선택 권장 설정만 staging하고 loader·ZIP 왕복 검증을 통과한 결과를 원자적으로 저장한다. macOS 호환 `monglepet-editor.json` marker를 사용하는 사용자 펫 생성·정보 수정·편집 사본과 PNG/WebP atlas 애니메이션 추가·수정·삭제도 구현했다. 설정창은 중앙 반응형 최대 폭, 탭별 아이콘 헤더와 계층적인 카드 스타일로 정돈했다. Activity 27개·Core 38개·Packages 18개·PetLibrary 18개·Settings 58개·Shell 12개로 총 171개 테스트와 x64 Debug·Release·1.0.0.13 MSIX가 통과했다. 실제 picker·macOS 교차 왕복 QA는 남아 있다.
- 멀티펫 1.1.0 Windows 10~11단계에서 schema-v11 `activePetInstances`·독립 `behaviorProfiles`·`selectedPetInstanceID`, v1~v10 순차 이관과 공통 fixture에 이어 instance별 `PetRuntimeContext`·Win32/Composition HWND를 소유하는 `PetInstanceManager`를 연결했다. 전역 activity·포인터·화면·전면 창 snapshot과 atlas surface·알파 마스크 참조 계수 캐시를 공유하고 선택되지 않은 펫도 독립 행동·이동·말풍선·쓰다듬기를 유지한다. WinUI `NavigationView`의 `활성 펫` 첫 화면은 같은 펫 추가·선택·별칭·앞뒤 순서·개별/전체 깨우기·재우기·제거·전체 일시정지와 안전 시작 복원을 제공하며 notification area도 전체와 인스턴스별 빠른 제어를 제공한다. 시작 복원 저널과 비차단 CPU·private memory 경고를 추가했고 Debug·Release 각 186개 테스트를 통과했다. 실제 다중 모니터·잠금·절전·설치 업데이트 QA는 12단계 범위다.
- 설정 `NavigationView`는 macOS와 같은 `데스크톱`·`선택한 펫`·`보관함` 그룹과 `활성 펫`·`일반`·`표시 및 이동`·`행동 루틴`·`말풍선`·`자동 규칙`·`펫 보관함` 목적지를 사용한다. 기능 배치는 macOS 정보 구조를 따르되 Mica, WinUI grouped card와 Windows 네이티브 컨트롤을 유지한다.
- 활성 펫 카드는 instance별 실제 패키지 미리보기를 캐시해 표시하며 선택은 runtime 전체 동기화와 분리된 manager 경계, 180ms debounce 원자적 저장, 페이지 진입 시 설정 컨트롤 갱신을 사용한다. 이동 runtime은 애니메이션 유무와 무관한 60Hz 반복 cadence, 정지 반경 내 100ms idle cadence, 120Hz 공유 포인터 snapshot, 캐시된 화면 범위와 unchanged activity 억제를 사용한다. programmatic overlay 이동은 중복 `SetWindowPos`와 `WM_MOVE`의 `GetWindowRect` 왕복을 생략한다. 마우스 따라가기 1마리와 자유 이동 1마리의 Release 15초 포인터 이동 표본은 전체 시스템 CPU 1.86%, private memory 122.50MiB였다.
- 필수 장시간 성능 검증은 Release 대표 이동 workload를 5분간 5초 간격으로 측정한다. 초기 기준은 전체 시스템 평균 CPU 5% 미만, private memory 200MiB 미만·증가 10MiB 미만, 무응답·충돌 0회이며 1시간 soak는 누수 징후가 있을 때 선택적으로 확장한다. 2026-08-14 마우스 따라가기 1마리·자유 이동 1마리 표본은 평균 CPU 1.484%, private memory 127.73→133.29MiB, 무응답·오류 0건으로 통과했다.
- 자체 웹과 GitHub Releases 배포를 위해 MSIX identity·Authenticode·인증서 subject·타임스탬프를 검증하고 고정 URL App Installer와 SHA256SUMS를 생성하는 자동화를 준비했다. 현재 `CN=AppPublisher` 미서명 MSIX는 공개 조건에서 거부하며 실제 코드 서명 방식과 최종 Publisher 확정, HTTPS 설치·업데이트 QA가 남아 있다.
- 첫 웹 Preview용 unpackaged x64 publish와 Inno Setup 사용자별 EXE 설치기를 추가했다. packaged는 `ApplicationData.LocalFolder`·`StartupTask`, unpackaged는 `%LOCALAPPDATA%\MonglePet`·현재 사용자 Run을 사용한다. 대상 데이터가 비었을 때만 기존 개발 MSIX LocalState를 원본 보존 복사하고, 제거는 전용 종료 메시지로 실행 중 앱을 정리한 뒤 사용자 데이터를 남긴다. 실제 설치·업그레이드·로그인 숨김 실행·데이터 이전·실행 중 제거 QA를 통과했다. Windows `1.3.0.13`은 태그 `windows-v1.3.0-preview.1`의 GitHub Pre-release로 게시했고 원격 설치기 digest를 검증했으며, 자체 웹 다운로드 화면은 별도 서버 반영을 위한 전달 자료를 제공한다.
- 신규 기능은 macOS 기준 구현과 필수 검증이 완료된 뒤 순차 반영한다.
- 웹 URL 펫 가져오기는 개발·운영 URL allowlist, API envelope·앱 호환 버전·20MiB·크기·SHA-256·same-origin redirect 검증, 검토 수명 temp session과 최신 보관함 UI를 구현했다. 높은 최소 앱 버전은 로컬·웹 모두 설치를 막지 않고 기능 차이 안내와 운영 다운로드 버튼을 표시한다. 기존 packaged·unpackaged protocol QA는 통과했고 운영·설치·중복·교차 왕복·혼합 DPI QA 전까지 `../../AGENTS/guides/WINDOWS_WEB_PET_IMPORT_HANDOFF.md`를 계속 완료 기준으로 사용한다.
- macOS `1.3.1 (6)` 기준의 펫 콘텐츠 자유 버전, 최소 앱 버전 권장 안내, PNG·스프라이트 crop·flip·확대·자동/독립 경계·배경 제거, 공통 캔버스 배치, 450ms와 프레임 복사를 Windows `1.3.0.13` Preview에 반영했다. staged 애니메이션·PNG·스프라이트 편집은 중첩 `ContentDialog` 대신 부모를 소유한 독립 Mica WinUI 창을 사용하며, PNG 화면은 원본/고정 결과/독립 설정 스크롤의 macOS 정보 구조를 따른다. 공통 `shared/BuiltInPets/Mongle.monglepet`을 output/publish runtime 기준본으로 사용하고 미수정 built-in 프로필만 새 기본값으로 이관한다. Debug·Release 각 266개 테스트와 loose AppX·unpackaged 설치·실행, 편집기 주요 실제 입력을 검증하고 `windows-v1.3.0-preview.1`로 게시했다. 혼합 DPI·Narrator·큰 이미지 반복 drag와 macOS 교차 왕복 실제 QA 전까지 플랫폼 동등 완료로 표시하지 않는다. 최신 완료 기준은 `../../AGENTS/guides/WINDOWS_MACOS_1_3_HANDOFF.md`다.
- Windows `1.4.0.13`은 schema-v12 안정 행동 ID·표시 이름, v13 랜덤 shuffle bag·랜덤 머무르기, v14 네 독립 이동 설정과 권장 프로필 v10을 C# Domain·Settings·runtime·WinUI에 반영했다. 공통 built-in `1.0.3`의 13개 모션·53프레임을 직접 포함하고 정확한 1.0.1/1.0.2 기본 프로필만 승격한다. 모든 펫 사본, 단일 애니메이션 복제·저장 시 행동 연결·현재 펫 프레임·flip·확대와 전체 휴대 설정 공유를 제공한다. Debug·Release 각 296개 테스트, loose AppX·unpackaged publish와 실제 schema-v11 사용자 데이터 보존, 설정창을 닫은 3펫 Release 5분 CPU 0.680%·private memory 최대 129.62MiB를 통과했다. 후속 `1.4.0.14`는 펫 제작기 드래그·미리보기·독립 활성 인스턴스, 다크·라이트 컨트롤 대비와 네 이동 방식의 클릭 통과를 보완해 `windows-v1.4.0-preview.2` Pre-release로 게시했다. 사용자 요청에 따라 후속 전체 자동 테스트는 생략했으며 Debug 빌드, Release publish와 실제 별도 프로세스 클릭 통과를 확인했다. 혼합 DPI·Narrator·큰 이미지 반복 drag·Windows→macOS 교차 왕복과 제거 QA 전까지 플랫폼 동등 완료로 표시하지 않는다. 최신 구현 기준은 `../../AGENTS/guides/WINDOWS_BEHAVIOR_CENTRIC_HANDOFF.md`, `../../AGENTS/guides/MACOS_PET_EDITOR_FOLLOWUP.md`와 `../../AGENTS/work_plans/tasks/2026-08-24-windows-macos-1-3-parity.md`다.
- macOS `1.5.0 (11)` 인계에 따라 Windows 로컬 schema-v15와 권장 프로필 v11을 구현했다. 종전 automatic/manual/random은 fixed/random 평상시 선택과 독립 조건 규칙으로 이관하며 manual·random의 휴면 규칙은 값과 순서를 보존한 채 비활성화한다. 평상시 선택은 `표시 및 이동`, 조건과 이동 우선순위는 `규칙 설정`에서 편집한다. 고정 행동은 별도 규칙 scheduler 뒤 진행 위치를 재개하고 랜덤은 이동·규칙 시작 때 다음 shuffle bag 행동을 첫 프레임으로 준비한다. 마우스 도망가기의 escape/idle 전환은 평상시 목표를 매 tick 지우지 않으며 100회 반복 tick 회귀 테스트를 포함한다. 공통 v14→v15 fixture와 v10→v11 codec을 포함해 Debug·Release 각 301개 테스트와 두 구성 빌드가 통과했다. Windows `1.5.0.15`를 `windows-v1.5.0-preview.1` Pre-release로 게시하고 설치 업데이트·데이터 보존·원격 digest를 검증했다. 실제 DPI·테마·접근성과 macOS 교차 왕복 전까지 플랫폼 동등 완료로 표시하지 않는다.
- macOS `1.6.0 (12)`의 D-111~D-113 인계에 따라 Windows는 행동 전체 반복 UI를 제거하고 저장 `repeats` 왕복, 랜덤 새 cursor와 이동 중 반복을 구현했다. D-115 후속 보정으로 평상시 `하나 선택`은 펫이 깨어 있는 동안 행동 전체를 계속 순환하고 랜덤의 각 행동·조건 규칙·쓰다듬기는 한 번 재생한다. 설정은 보관 구분 없는 단일 `내 펫`과 선택 펫의 정보·표시·평상시·이동·상호작용·행동·말풍선·규칙 목적지로 나눴다. 로컬·웹 항상 새 installation·instance·profile 가져오기와 rollback, 보편 편집의 in-place/copy-on-write, 사본·재우기·완전 삭제·legacy orphan 복구를 연결했다. 말풍선은 캐시된 현재 frame alpha 경계와 표시 중 자동 방향 잠금을 사용한다. schema-v15·권장 프로필 v11은 유지한다. Preview 2 뒤 설치 직후 첫 실행 runtime 순서, atlas 제한 재시도, overlay DPI·좌표 복구, 좁은 `내 펫` 배치와 설정창 `800×600` 최소 크기를 보정한 Windows `1.6.0.17`을 `windows-v1.6.0-preview.3`으로 게시했다. Debug·Release 각 313개 테스트와 설치 업데이트·사용자 데이터 보존·원격 digest 검증이 통과했으며 실제 혼합 DPI와 설치 완료 화면 첫 실행 QA는 계속 필요하다.
- D-120의 `행동 완료 후` 이동은 Windows 후속 작업이다. 로컬 schema-v16과 제작자 설정 v12의 `dwellMode: fixed | random | behaviorCompletion`, 행동 한 회차 완료 event, 도망가기 즉시 취소와 500ms fallback을 `../../AGENTS/guides/WINDOWS_MOVE_AFTER_STATIONARY_BEHAVIOR_HANDOFF.md`에 따라 구현한다. Windows 소스·테스트·실제 QA와 macOS 교차 왕복 전에는 동등 완료로 표시하지 않는다.
- D-118 인계에 따라 로컬·웹 가져오기의 기본/권장 선택을 단일 `펫 추가`로 통합하고 유효한 제작자 설정 전체와 휴대 표시를 새 profile·overlay에 자동 적용한다. 설정 없음·미래·손상은 안전한 최소값과 구분된 성공 상태로 처리하며 기존 fingerprint·1 MiB 제한·별도 installation·settings rollback을 유지한다. NavigationView의 `행동 편집`은 `펫 정보·애니메이션` 바로 다음이다. 웹이 실행 중 앱을 열 때 보조 프로세스가 검증된 기본 프로세스에 전면 권한을 전달해 settings 창이 브라우저 뒤에 남지 않게 한다. unpackaged 설치기는 기존 URL protocol key에 더해 전용 ProgID와 Windows Registered Applications 계약을 등록한다. Debug·Release 각 320개 테스트, 실제 운영 웹 실행, `1.6.0.17→1.6.0.18` 데이터 보존 업데이트와 원격 digest 검증을 통과해 `windows-v1.6.0-preview.4`로 게시했다. 브라우저 권한 fallback과 macOS 교차 왕복은 남아 있다.
- Windows 앱의 신규 소스 변경, 빌드와 테스트는 Windows 환경에서 진행한다. macOS 환경에서는 Windows 인계를 위한 공통 명세·fixture와 작업 계획만 정리한다.

## 기술 기준

- 언어: C#
- 최소 OS: Windows 11 25H2 build 26200
- 런타임: .NET 10 LTS
- Windows App SDK: 2.3.1 Stable
- 배포 아키텍처: x64 packaged WinUI 3·MSIX와 x64 unpackaged self-contained EXE의 단일 full-trust 프로세스
- 단위 테스트: xUnit
- 설정 및 일반 앱 UI: Windows App SDK와 WinUI 3
- 펫 오버레이 창: 별도 Win32 `HWND`
- 펫·이동·말풍선 렌더링: `Microsoft.UI.Composition` Visual layer
- Composition 창 연결: 최상위 Win32 부모 `HWND` 아래 `ContentIsland`·`DesktopChildSiteBridge`
- 저수준 창·입력·notification area 연동: CsWin32를 우선하는 명시적인 Win32 interop 경계
- WPF: 성능 비교 또는 호환성 대안이며 최종 기준 기술로 사용하지 않음
- C++/WinRT: 전체 앱 구현에는 사용하지 않고 프로파일링으로 확인한 성능 병목 모듈에만 후속 검토

## 구현 원칙

- Windows 네이티브 UI와 운영체제 API를 사용한다.
- macOS Swift·AppKit 소스를 이식하거나 조건부 컴파일로 공유하지 않는다.
- `.monglepet` 패키지, 권장 프로필, 공통 스키마 fixture와 사용자 시나리오만 플랫폼 간 공유한다.
- macOS Bundle Identifier 기반 앱 규칙은 Windows 실행 파일·패키지 식별자와 분리한다.
- 화면 좌표, 모니터 식별자, 시작 프로그램과 창 표시 정책은 Windows 전용 설정·adapter로 구현한다.
- 실제 키 입력 내용, 화면 내용과 창 제목을 수집하지 않는 개인정보 원칙을 유지한다.
- 루트 `../../AGENTS/project/PLATFORM_PARITY.md`의 사용자 동작과 완료 조건을 기준으로 구현 상태를 추적한다.
- macOS 구현 세부사항을 그대로 복제하지 않고 Windows에서 자연스러운 네이티브 UX로 같은 결과를 제공한다.
- 설정 UI 생명주기와 펫 오버레이 생명주기를 분리해 설정창이 닫혀도 오버레이와 notification area가 유지되게 한다.
- 투명·항상 위·비활성·클릭 통과와 다중 모니터 정책은 Win32 `HWND` adapter가 담당한다.
- ContentIsland 자식 HWND는 Composition 표면만 담당하고 최상위 창 정책과 위치의 단일 원본은 부모 오버레이 HWND로 유지한다.
- 프레임 교체, 이동과 말풍선 합성은 UI 스레드의 지속적인 layout·redraw에 의존하지 않고 `Microsoft.UI.Composition`을 우선한다.
- 투명 펫 오버레이를 일반 WinUI 창이나 `SwapChainPanel`에 직접 의존시키지 않는다. 실제 알파 합성과 click-through 동작을 최소 실험에서 먼저 검증한다.
- JSON·ZIP·스키마 마이그레이션, 행동 엔진과 설정 편집은 우선 관리형 C#으로 구현한다.
- packaged 앱의 로컬 설정과 펫 라이브러리 루트는 `ApplicationData.Current.LocalFolder\MonglePet`, unpackaged 앱은 `%LOCALAPPDATA%\MonglePet`이다. package identity 감지와 데이터 이전은 Shell adapter 경계에서 처리하고 `unvirtualizedResources` 제한 capability를 사용하지 않는다.
- C++ 도입은 독립 실행 Release 측정에서 C#·Composition 경로의 병목이 확인되고 관리형 최적화로 기준을 만족하지 못할 때만 별도 계획으로 결정한다.
- C++ 모듈을 추가할 경우 관리형 경계, 소유권, 오류 변환과 자동 테스트를 명시하고 UI·제품 규칙을 넣지 않는다.

## 시작 조건

Windows 구현을 확장하기 전에 별도 작업 계획에서 다음을 확인하거나 확정한다.

1. 고정한 최소 Windows 버전, Windows App SDK 버전과 C#·WinUI 3 프로젝트가 실제 개발 환경에서 빌드되는지 확인
2. Win32 `HWND`·Composition 투명 항상 위 창, 클릭 통과와 시스템 트레이 방식
3. 전면 앱·입력 없음·다중 모니터 감지 API
4. 설정 저장 위치와 앱 식별자
5. `.monglepet` 호환 fixture와 CPU·GPU·메모리·프레임 지연 성능 기준
6. 실제 Windows Release 빌드에서 고정·마우스 따라가기·자유 이동·도망가기와 말풍선을 포함한 오버레이 성능 실험

## 적용 순서

1. macOS에서 완료된 제품 동작, 공통 명세·fixture와 Windows 인계 체크리스트를 확인한다.
2. Windows 환경에서 플랫폼 차이와 대체 UX가 필요한 항목을 작업 계획에 기록한다.
3. Windows 환경에서 네이티브 구현과 플랫폼별 테스트를 작성하고 빌드한다.
4. 공통 fixture의 Windows 왕복과 macOS·Windows 교차 호환을 검증한다.
5. 실제 Windows 환경 QA 후 기능 동등성 현황을 갱신한다.

## 공식 참고

- [Windows 앱 개발 개요](https://learn.microsoft.com/windows/apps/)
- [WinUI 3 개요](https://learn.microsoft.com/windows/apps/winui/winui3/)
- [Windows App SDK 개요](https://learn.microsoft.com/windows/apps/windows-app-sdk/)
- [Composition Visual layer](https://learn.microsoft.com/windows/apps/develop/composition/visual-layer)
- [데스크톱 앱의 Visual layer](https://learn.microsoft.com/windows/uwp/composition/visual-layer-in-desktop-apps)
- [C#에서 Win32 API 호출](https://learn.microsoft.com/windows/apps/develop/interop/call-win32-apis)
