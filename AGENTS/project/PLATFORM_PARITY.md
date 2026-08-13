# MonglePet 플랫폼 기능 동등성

## 목적

MonglePet의 신규 기능과 수정은 macOS 기준 구현에서 먼저 설계·검증하고, 안정화된 제품 동작과 공통 데이터 규격을 Windows 네이티브 앱에 순차 반영한다.

두 플랫폼의 화면과 운영체제 연동 코드를 같게 만드는 것이 아니라 사용자가 얻는 기능과 `.monglepet` 호환 결과를 동등하게 유지하는 것이 목표다.

## 개발 순서

1. 제품 요구사항과 개인정보 범위를 루트 `AGENTS/` 문서에서 확정한다.
2. `apps/macos/`에서 기능을 구현하고 단위 테스트·Debug 빌드·필요한 실제 앱 QA를 완료한다.
3. 플랫폼 공통 데이터가 바뀌면 구현과 같은 작업에서 명세, schema fixture와 호환성 시나리오를 갱신한다.
4. macOS 동작이 안정화되면 확정 동작, 공통 계약, fixture, Windows 구현 범위와 필수 QA를 인계 체크포인트로 기록한다.
5. Windows 앱의 소스 변경, 빌드와 테스트는 Windows 환경에서 진행하며 Windows 네이티브 API와 UX로 같은 사용자 결과를 구현한다.
6. 공통 fixture, 플랫폼별 자동 테스트와 실제 앱 QA를 통과하면 해당 기능을 `동등`으로 표시한다.

macOS에서 개발을 시작했다는 이유만으로 AppKit 타입, Bundle Identifier, 화면 UUID와 macOS 파일 경로를 공통 스키마에 넣지 않는다.

## 기능 상태 값

- `기준 구현`: macOS에서 구현과 필수 검증을 완료해 Windows가 따라갈 제품 기준으로 사용할 수 있음
- `진행 중`: 해당 플랫폼에서 구현 또는 필수 검증이 남아 있음
- `계획됨`: 범위는 확인했지만 구현을 시작하지 않음
- `동등`: 두 플랫폼이 공통 사용자 시나리오와 데이터 호환 검증을 통과함
- `플랫폼 전용`: 운영체제 차이로 같은 구현이 불가능하며 대체 UX와 이유를 기록함

## 현재 진행 현황

기준일: 2026-08-13

| 영역 | macOS | Windows | 비고 |
| --- | --- | --- | --- |
| 저장소 구조 | 기준 구현 | 진행 중 | `MonglePet.slnx`와 Core·Packages·WinUI·xUnit 프로젝트 생성 |
| 개발·빌드 환경 | 기준 구현 | 진행 중 | Visual Studio 2026·.NET SDK 10.0.302·Windows App SDK 2.3.1 설치, x64 Debug·Release 전체 빌드 통과; CI 남음 |
| 앱 셸·상태 메뉴 | 기준 구현 | 동등 | Windows notification area에서 현재 펫, 깨우기·재우기, 클릭 통과, 현재 화면 이동, 설정 숨김·재열기와 명시적 종료를 packaged Release 확인 |
| 투명 펫 오버레이 | 기준 구현 | 진행 중 | 별도 Win32 HWND·ContentIsland Composition에서 공통 PNG 프레임과 입력 통과 말풍선 XAML Island, 가변 크기·투명도·nearest 렌더링·클릭 통과·awake/tuckedAway, 드래그·화면 위치 저장과 실제 알파 픽셀 겹침 투명화를 구현; 고정·포인터 workload 성능 통과, 말풍선·프레임 지연 workload와 실제 시각 QA 남음 |
| 펫 패키지·애니메이션 | 기준 구현 | 진행 중 | 공통 fixture와 보안 검증, PNG·WebP 재생에 더해 macOS 호환 편집 marker, 사용자 펫 생성·정보 수정·편집 사본과 atlas 기반 애니메이션 추가·수정·삭제를 구현; 실제 대형·다중 프레임 이미지와 macOS 교차 왕복 QA 남음 |
| 자동·수동 행동 | 기준 구현 | 진행 중 | 행동 결정기·cycle scheduler·Composition 전환, 대상 펫·루틴·재생·단계 편집과 앱 규칙·입력 없음 규칙의 별도 생성 흐름, 이동·쓰다듬기 표시 우선순위와 행동 대사 우선·주기 대사 timer를 연결; 실제 말풍선·재실행 QA 남음 |
| 전면 앱·입력 없음 감지 | 기준 구현 | 진행 중 | PFN/실행 파일명과 `GetLastInputInfo` 1초 polling, WTS·전원 메시지, 실행 중 앱 이름·아이콘 선택·현재 앱 채우기·`.exe` 파일 선택 Release QA 통과; 실제 물리 잠금·절전 복귀 수동 QA 남음 |
| 설정·펫 라이브러리 | 기준 구현 | 진행 중 | LocalState 라이브러리와 schema-v1~v10 저장에 더해 현재 펫·애니메이션 미리보기와 편집, `MonglePet 패키지 / 패키지 가져오기 / 현재 펫 내보내기`, 새 펫·정보 수정·편집 사본·삭제 흐름을 구현; 실제 picker·재실행·macOS 교차 QA 남음 |
| 이동·다중 모니터 | 기준 구현 | 진행 중 | 네 모드별 조건부 설정, 이동 감각·범위·공통/4/8방향 모션·사용자 영역·상호작용을 구현하고 16ms 논리 소수점 위치 누적으로 저속 끊김과 모든 화면의 모니터 경계 고착을 수정; 혼합 DPI 물리 횡단 QA 남음 |
| 쓰다듬기·말풍선 | 기준 구현 | 진행 중 | 실제 frame 알파 쓰다듬기와 행동 우선·주기 runtime, 행동/주기 대사 분리, draft·즉시 저장·위치 미리보기를 구현; gap을 잇는 가변 꼬리와 행동 대사 유지 중 주기 예약을 보완했으며 물리 포인터·혼합 DPI·성능 최종 QA 남음 |
| 로컬 가져오기·내보내기 | 기준 구현 | 진행 중 | 설치 전 메타데이터·모션·권장 설정 검토, schema-v1~v7 호환, 펫만/권장 설정 적용, 교체 기본 보존·별도 설치, canonical 자산 선별·권리 확인·ZIP 왕복·원자적 저장 구현; 실제 대화상자와 macOS 교차 왕복 QA 남음 |
| 배포·업데이트 | 진행 중 | 진행 중 | 1.0.0.13 x64 self-contained EXE 설치기·SHA256SUMS 생성과 사용자별 설치·동일 버전 업그레이드·MSIX 데이터 이전·로그인 실행·실행 중 제거 QA 통과; 첫 Preview는 웹 수동 업데이트, 서명·HTTPS·깨끗한 PC와 향후 App Installer 자동 업데이트 QA 남음 |
| 멀티펫 | 진행 중 (`1.1.0`) | 계획됨 (`1.1.0`) | macOS schema-v11 Domain·원자적 저장, `PetInstanceManager`·독립 `PetRuntimeContext`와 저장된 전체 인스턴스의 다중 `NSPanel`·위치·깨움 상태 복원 완료; 다음은 전역 pointer·screen snapshot과 이미지·알파 캐시 공유, Windows는 macOS 인계 후 Windows 환경에서 반영 |

Windows 개발 환경과 첫 솔루션을 구성했고 2026-08-09 기준 x64 Debug·Release 빌드와 Activity 27개·Core 36개·Packages 18개·PetLibrary 10개·Settings 37개·Shell 8개로 총 136개 단위 테스트가 통과한다. 별도 최상위 Win32 HWND에 ContentIsland 기반 `Microsoft.UI.Composition`으로 공통 `.monglepet` PNG 프레임을 표시하고 항상 위·비활성 동작과 96–384px 크기, 10–100% 투명도, linear/nearest 렌더링, 클릭 통과와 `awake`/`tuckedAway` 저장 복원을 구현했다. 최대 64px frame 알파 마스크로 실제 표시 픽셀만 판정해 300ms 호버 쓰다듬기와 클릭 통과 겹침 투명화를 같은 100ms 관찰에 연결했으며, 비활성 시작·투명 모서리 100%·불투명 중앙 20%와 설정 복원을 packaged Release에서 확인했다. notification area의 네이티브 메뉴는 현재 펫, 깨우기·재우기, 클릭 통과, 포인터가 있는 현재 화면으로 가져오기, 설정과 종료를 제공하며 설정창 X 숨김·재열기, 명시적 종료와 위치 재실행 복원을 확인했다. 네 이동 모드와 전역 이동 범위, 실제 좌표 방향 모션, 드래그 위치 저장과 창 제목 없는 전면 앱 대표 창 선호를 연결했고 음수 좌표 듀얼 모니터 자유 이동·쓰다듬기 행동 복귀, 전체 화면 대표 창 fallback을 실제 Release에서 확인했다. 순수 cycle scheduler와 monotonic 일회성 timer runtime이 단계 반복·루틴 반복·동적 모션 전환·숨김 pause를 처리하며 WinUI에서 자동·수동 모드, 루틴 단계와 앱·입력 없음 규칙을 생성·수정·삭제하고 저장·즉시 적용한다. Windows activity adapter는 PFN 또는 실행 파일명만으로 전면 앱을 식별하고 `GetLastInputInfo`를 1초 polling하며 WTS·전원 메시지로 잠금·절전을 즉시 반영한다. 자동 규칙 앱 선택기는 창 제목 없이 일반 최상위 창 프로세스만 열거해 이름·지연 아이콘·식별자를 보여주며 packaged Release에서 Notepad PFN 규칙 저장과 이름·경로 비저장을 확인했다. 표준 파일 선택기에서 KakaoTalk 실행 파일을 골라 `exe:kakaotalk.exe` 규칙 저장과 실제 전면 앱 루틴 전환도 확인했다. LocalState UUID 라이브러리, schema-v1~v10 순차 마이그레이션, schema-v10 전체 Domain 매핑·항목 복구·원자적 전체 저장과 `.monglepet` 가져오기·관리 개발 UI도 구현했다. 고정 PNG workload 30초 기준 CPU 0.017%(전체 시스템 기준), private memory 100.2MiB, 3D GPU 0%를 기록했고 전면 창 감지 자유 이동 workload는 전체 시스템 CPU 0.364%, private memory 126.2MiB를 기록했다. 실제 Explorer 재시작·혼합 DPI 다중 모니터와 물리 잠금·절전 복귀 QA, 알파 쓰다듬기와 일반 창 foreground의 최종 물리 QA, 가져오기 검토·내보내기, 다중 프레임·WebP와 말풍선 성능 측정은 아직 남아 있다.

말풍선 후속 구현에서는 행동 우선·주기/표시 timer, 동일 루틴 중복 억제, 재우기·잠금·절전·펫 전환 정리, 자동·위·아래 및 음수 좌표 경계 배치를 Windows 순수 runtime·geometry로 구현했다. 별도 non-activating·click-through Win32 HWND에 WinUI 3 `DesktopWindowXamlSource`를 연결해 대사·preset/사용자 테마·꼬리를 표시하고, 전체 대사·정책·테마·배치를 schema-v10 펫별 프로필 편집 UI에 연결했다. Settings 대상 테스트는 기존 37개에서 46개로 늘어 모두 통과했고 x64 Debug 앱 빌드가 경고·오류 없이 성공했다. 전체 Windows 145개 테스트 재실행과 Release·MSIX·물리 시각·성능 QA는 남은 구현을 마친 뒤 수행한다.

로컬 공유 후속 구현에서는 권장 프로필 schema-v1~v7 codec과 검토 후 SHA-256 원본 변경 거부, 잘못된 선택 권장 데이터 격리와 1 MiB 보안 제한을 구현했다. 내보내기는 manifest·미리보기·참조 atlas와 선택 권장 설정만 새 staging에 구성해 전체 loader·ZIP 왕복 검증 후 목적지를 원자적으로 교체한다. WinUI 검토 대화상자에서 신규·별도 설치 권장 설정 적용과 교체 기본 보존을 구분하고, 내보내기 권리 확인과 저장 picker를 연결했다. Debug·Release 전체 153개 테스트와 두 구성 빌드, startup task를 포함한 Release MSIX 생성이 통과했다. 실제 picker·로그인 실행·macOS 교차 왕복 QA는 남아 있다.

Windows 앱 정리 단계에서는 민트·크림 발바닥 아이콘을 실행 파일 내장 리소스, AppWindow 작업 표시줄 전용 API, HWND 큰·작은 창 아이콘, 시작 메뉴, 스토어 타일과 스플래시 자산에 적용하고 설정 화면을 macOS의 6개 탭 정보 구조에 맞춘 WinUI 상단 탐색으로 분리했다. x64 Debug 빌드와 전체 153개 테스트, 1.0.0.5 Release MSIX 생성을 통과했으며 Release EXE에서 추출한 32px 아이콘, loose 설치 위치의 Square44 후보와 기존 LocalState를 보존한 개발 패키지 업데이트 등록에서 `MonglePetStartupTask` 포함과 패키지 상태 `Ok`를 확인했다.

Windows 설정 시각 정렬 단계에서는 일반 탭을 펫 표시·행동 모드·화면 표시·앱 실행·앱 정보로 재구성하고, 활성 패키지의 실제 미리보기와 제작자·버전·설명·모션 요약을 현재 펫 카드에 연결했다. 이동 방식은 설명형 2×2 선택 카드로 바꾸고 말풍선 편집에는 현재 펫과 테마가 함께 보이는 미리보기를 추가했으며, 파일 경로와 런타임 상태는 접힌 진단 영역으로 이동했다. 기존 설정 스키마와 런타임 동작은 변경하지 않았다.

Windows macOS 기능 동등성 후속 단계에서는 편집 가능한 사용자 펫과 atlas 애니메이션 추가·수정·삭제, 현재 펫 미리보기, 패키지 가져오기·현재 펫 내보내기와 펫 관리 흐름을 macOS 설정 구조에 맞췄다. 네 이동 방식별 조건부 섹션과 공통·방향별 이동 모션, 사용자 영역을 편집할 수 있으며 논리 좌표 소수점 누적과 16ms tick으로 저속 이동 손실을 제거하고 모든 화면의 모니터 사이 횡단을 허용했다. 행동 루틴·앱 규칙·입력 없음 규칙과 행동/주기 대사를 분리했고 말풍선 draft·즉시 저장·꼬리와 상대 위치 미리보기를 보완했다. Activity 27개·Core 38개·Packages 18개·PetLibrary 18개·Settings 52개·Shell 8개로 총 161개 테스트, x64 Debug·Release 빌드와 1.0.0.7 MSIX 생성이 통과했으며 loose Release 패키지 등록·실행도 확인했다. 혼합 DPI 물리 횡단, 실제 이미지 picker와 macOS 교차 패키지 왕복은 수동 QA로 남아 있다.

말풍선 타이밍·UI 보완에서는 macOS 기준대로 꼬리 높이는 고정하고 펫 사이 간격이 바뀌면 말풍선과 꼬리가 한 덩어리로 이동하도록 실제 창과 미리보기를 수정했다. `다음 대사까지 유지` 행동 대사도 다음 주기 대사를 예약·교체하고 간격 변경은 기존 예약을 취소한 뒤 새 값으로 다시 시작한다. Enter로 주기 값을 확정하면 다음 컨트롤로 포커스를 이동한다. 설정 카드의 모서리·경계·패딩을 완화하고 행동 단계의 애니메이션과 반복 횟수 입력을 같은 높이와 명시적 레이블로 정리했다. Settings 58개를 포함한 전체 167개 테스트, x64 Debug·Release와 1.0.0.10 MSIX 생성이 통과했으며 개발 패키지 상태 `Ok`와 앱 정상 응답을 확인했다.

실제 시각 QA에서 연결되지 않은 Windows XAML 요소의 `DesiredSize`가 0으로 반환돼 말풍선 HWND가 `72×1px`로 생성되는 문제를 재현했다. 호스트 연결 후 측정과 글자·여백 기반 안전 크기를 추가해 실제 `72×59px` 본체·글자·꼬리 표시 및 5초 주기 중 3초 표시·2초 숨김을 확인했다. 설정 미리보기는 실제 이미지 로드 뒤 대체 아이콘을 숨긴다. 서로 다른 PNG atlas 사이 행동 전환은 새 surface 디코딩 중 현재 프레임을 유지하고 성공 시 원자적으로 교체해 투명 번쩍임을 제거했다. 14.5초 동안 180회 펫 영역 샘플에서 빈 프레임이 없었고, 전체 167개 테스트와 1.0.0.11 패키지 검증을 통과했다.

말풍선 본체의 사각형 테두리와 별도 삼각형 꼬리가 겹치며 접합부에 내부 실선이 남는 현상은 macOS와 같은 단일 연속 `PathGeometry` 외곽선으로 교체했다. 실제 1.0.0.12 화면 확대 캡처에서 본체와 꼬리 사이 내부선이 사라지고 바깥 윤곽만 이어지는 것을 확인했다. 전체 167개 테스트와 x64 Debug·Release·MSIX 생성, 개발 패키지 상태 `Ok`를 다시 확인했다.

Windows 설정창은 기능 구조를 유지하면서 Mica 배경이 드러나는 투명 페이지, 중앙 반응형 960px 최대 폭, 탭별 아이콘 헤더와 20px/14px 카드 계층으로 정돈했다. 넓은 창에서 콘텐츠가 왼쪽 좁은 열에 몰리던 문제를 줄이고 각 탭의 제목·설명·설정 카드가 한 축에서 읽히도록 했다. 1.0.0.13 전체 167개 테스트와 x64 Debug·Release·MSIX 생성, Release 개발 패키지 상태 `Ok`를 확인했다.

Windows 웹 배포 준비에서는 MSIX 내부 identity를 읽고 Authenticode 서명·인증서 subject·타임스탬프를 검증한 뒤 버전별 MSIX, 고정 URL App Installer와 SHA256SUMS를 생성하는 PowerShell 자동화를 추가했다. 자체 웹사이트를 기본 다운로드 경로, GitHub Releases를 보조 경로로 사용하며 패키지를 먼저 게시하고 고정 App Installer를 마지막에 교체한다. 현재 `CN=AppPublisher` 미서명 개발 패키지는 공개 기본 조건에서 거부하며, 실제 인증서 선택과 최종 Publisher 확정 뒤 깨끗한 PC 설치·업데이트 QA가 남아 있다.

Windows 첫 EXE Preview 후속 단계에서는 package identity 감지, packaged `LocalState`와 unpackaged `%LOCALAPPDATA%\MonglePet` 데이터 루트, MSIX `StartupTask`와 현재 사용자 Run 자동 실행을 분리했다. .NET·Windows App SDK를 포함한 x64 publish 538개 파일 약 225MiB를 Inno Setup 사용자별 설치기 약 60.8MiB로 압축하고 SHA256SUMS를 생성한다. 실제 1.0.0.13 설치·동일 버전 업그레이드에서 실행 파일 해시와 단일 제거 항목을 확인했으며, `--startup` 설정창 숨김, MSIX 데이터 11개 파일 비파괴 이전, 실행 중 정상 종료 제거, 설치 폴더·시작 메뉴·자동 실행 값 삭제와 사용자 데이터 해시 보존을 통과했다. Shell 12개를 포함한 전체 테스트 수는 171개다.

## 신규 기능 작업 규칙

- macOS 신규 기능 계획에는 Windows 반영 여부와 공통 데이터 변경 여부를 명시한다.
- macOS에서 완료된 기능은 이 문서의 macOS 상태를 갱신하고 Windows 후속 범위를 남긴다.
- Windows 작업을 시작하기 전에 기능별 작업 계획에 macOS 확정 동작, 공통 schema·fixture, Windows 구현 범위와 실제 환경 QA 항목을 남긴다.
- Windows 앱의 소스 변경·빌드·테스트는 Windows 환경에서 수행한다.
- Windows 적용 작업은 macOS 코드를 복사하는 작업이 아니라 확정된 제품 동작을 Windows adapter와 UI로 구현하는 작업으로 계획한다.
- Windows에서 동일 동작이 불가능하거나 부자연스러우면 임의로 생략하지 않고 `플랫폼 전용` 차이와 대체 UX를 결정 기록에 남긴다.
- 공통 schema를 변경하면 이전 버전 읽기, macOS 왕복, Windows 왕복과 두 플랫폼 교차 왕복 fixture를 완료 조건에 포함한다.
- 한 플랫폼의 화면 좌표, 설치 식별자, 앱 식별자와 권한 상태는 다른 플랫폼으로 내보내지 않는다.

## Windows 적용 우선순위

Windows 개발 환경을 확정한 뒤 다음 순서로 적용한다.

1. C#·.NET·WinUI 3 솔루션 기준선과 `.monglepet` 로더·공통 fixture
2. Win32 `HWND`·`Microsoft.UI.Composition` 오버레이 성능 실험과 프레임 재생 기준선
3. 설정 저장과 펫 라이브러리
4. 자동·수동 행동과 전면 앱·입력 없음 감지
5. 이동·다중 모니터·상호작용
6. 말풍선과 공유 권장 프로필
7. 시스템 트레이, 자동 실행, 설치·배포와 성능 검증

## 동등성 완료 조건

- 같은 `.monglepet` 패키지가 두 플랫폼에서 같은 메타데이터·애니메이션 의미로 열린다.
- 공통 행동·말풍선·권장 프로필 fixture가 두 플랫폼에서 같은 제품 규칙으로 해석된다.
- 플랫폼별 앱 식별자와 화면 설정이 다른 플랫폼의 로컬 설정을 오염시키지 않는다.
- 잠금·절전·숨김 상태에서 각 플랫폼의 렌더링과 자동 이동이 중지된다.
- 각 플랫폼에서 기능별 자동 테스트, 실제 앱 QA와 성능 기준을 독립적으로 통과한다.
- 의도적인 플랫폼 차이가 사용자 문서와 결정 기록에 설명되어 있다.

---

문서 상태: active
마지막 갱신: 2026-08-13
