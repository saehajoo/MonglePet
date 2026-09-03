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

기준일: 2026-09-02

| 영역 | macOS | Windows | 비고 |
| --- | --- | --- | --- |
| 저장소 구조 | 기준 구현 | 진행 중 | `MonglePet.slnx`와 Core·Packages·WinUI·xUnit 프로젝트 생성 |
| 개발·빌드 환경 | 기준 구현 | 진행 중 | Visual Studio 2026·.NET SDK 10.0.302·Windows App SDK 2.3.1 설치, x64 Debug·Release 전체 빌드 통과; CI 남음 |
| 앱 셸·상태 메뉴 | 진행 중 | 진행 중 | macOS는 자주 쓰는 `설정…`을 최상위에 유지하고 저빈도 `안전 모드로 전환…`을 구분된 `문제 해결` 하위 메뉴로 이동했다. Windows notification area는 현재 펫, 깨우기·재우기, 클릭 통과, 현재 화면 이동, 설정 숨김·재열기와 명시적 종료를 packaged Release 확인했으며 같은 안전 모드 정보 계층의 후속 적용·QA가 남았다. |
| 투명 펫 오버레이 | 기준 구현 | 진행 중 | 별도 Win32 HWND·ContentIsland Composition에서 공통 PNG 프레임과 입력 통과 말풍선 XAML Island, 가변 크기·투명도·nearest 렌더링·클릭 통과·awake/tuckedAway, 드래그·화면 위치 저장과 실제 알파 픽셀 겹침 투명화를 구현; 고정·포인터 workload 성능 통과, 말풍선·프레임 지연 workload와 실제 시각 QA 남음 |
| 펫 패키지·애니메이션 | 진행 중 | 진행 중 | macOS 최신 기준은 내장 몽글이 `1.0.3`의 13개 모션·53프레임과 권장 프로필 v11이다. 앱이 새로 제작·편집 저장하는 펫 버전은 ASCII `MAJOR.MINOR.PATCH`만 허용하되 외부·레거시 자유 문자열 버전 읽기는 유지한다. 새 펫과 사본은 기존 활성 펫을 교체하지 않고 새 설치·인스턴스·독립 프로필로 추가하며 사본의 행동·이동·말풍선·overlay를 독립 복사한다. 설정 저장 실패 시 신규 설치를 rollback한다. v11은 세 이동 방식과 도망가기 평상시 자유 이동을 독립 저장하고 평상시 행동 선택·규칙·쓰다듬기·말풍선·휴대 표시 전체를 담는다. PNG·스프라이트 1×~8× 확대·좌우/상하 flip, PNG 편집 중 추가와 프레임 복사에 더해 편집 가능한 펫의 애니메이션 전체 복제와 현재 펫 프레임 조합을 제공한다. 현재 펫 프레임은 애니메이션별로 조회해 클릭 순서·원본 간격을 보존하고 새 전용 atlas로 독립 저장한다. 전체 복제는 단일 `애니메이션 복제…`에서 원본 표시 편집 화면을 열고 저장 시 공통 행동 연결 선택을 적용하며 취소 시 복사본을 제거한다. 실제 macOS 생성·사본·재실행 QA와 Windows 교차 왕복이 남아 있다. |
| 평상시 행동·조건 규칙 | 진행 중 | 진행 중 | macOS는 선택 펫 설정을 `화면 표시`, `평상시 행동`, `이동`, `상호작용`, `규칙 설정`으로 분리했다. 평상시 행동은 하나 선택·랜덤 선택으로 두고 `규칙 설정`에는 이동·입력 없음·앱 사용 우선순위와 조건만 둔다. 조건 규칙은 두 선택 방식 모두에서 독립 평가되며 일치 규칙이 없을 때 평상시 행동이 fallback이다. D-115부터 평상시 `하나 선택`은 펫이 깨어 있는 동안 행동 전체를 계속 순환하고, 랜덤의 각 행동·조건 규칙·쓰다듬기는 한 번 통과하며 랜덤만 다음 shuffle bag 행동을 새 cursor에서 시작한다. 양 플랫폼 runtime은 저장 `repeats` 값 대신 이 문맥별 playback 정책을 적용했고 관련 자동 회귀를 통과했다. 실제 장시간 runtime·접근성 QA와 교차 왕복 전까지 진행 중이다. |
| 전면 앱·입력 없음 감지 | 기준 구현 | 진행 중 | PFN/실행 파일명과 `GetLastInputInfo` 1초 polling, WTS·전원 메시지, 실행 중 앱 이름·아이콘 선택·현재 앱 채우기·`.exe` 파일 선택 Release QA 통과; 실제 물리 잠금·절전 복귀 수동 QA 남음 |
| 설정·펫 라이브러리 | 진행 중 | 진행 중 | macOS와 Windows는 보관 상태 없이 모든 설치를 독립 설정을 가진 단일 `내 펫` 목록으로 표시한다. 재우기는 설정과 콘텐츠를 보존하고 완전 삭제는 instance·profile과 마지막 installation을 transaction으로 제거하며 과거 비활성 설치는 잠든 펫으로 한 번 복구한다. Windows 로컬·웹 가져오기는 항상 새 installation·instance·profile을 만들고 settings 실패 시 설치를 정리한다. 생성·통합 가져오기·사본·내보내기를 card 문맥에 두고 선택 펫 `펫 정보·애니메이션`에서 읽기 전용 구분 없이 단독 설치는 in-place, 내장·공유 설치는 instance/profile/overlay를 유지한 copy-on-write로 편집한다. Windows 선택 펫 화면은 상단의 반복적인 `설정 대상 펫` 요약을 제거하고, 펫 정보 수정·화면 표시·평상시 행동·이동의 정보 구조를 macOS 기준에 맞췄다. 같은 대상 요약 제거는 macOS 후속 반영이 필요하다. Debug·Release 전체 308개 테스트가 통과했으며 실제 transaction 오류 주입 QA와 양 플랫폼 v11 교차 왕복 전까지 진행 중이다. |
| 이동·다중 모니터 | 기준 구현 | 진행 중 | macOS는 33ms 이동 cadence·속도를 유지하면서 이동 Timer 재사용, 화면·이동 범위 cache와 기능 수요 기반 30Hz 포인터 감시를 적용했다. Windows는 16ms 논리 소수점 위치 누적과 공유 포인터·화면 snapshot으로 저속 끊김과 모니터 경계 고착을 수정했다. `마우스 도망가기 + 평상시 자유 이동`은 escape/idle 상태 전환 한 번에만 목표를 초기화하고 평상시 100회 반복 tick 동안 목표를 유지하는 테스트와 설치 Release 사용자 확인을 통과했다. 네 모드·공통/4/8방향 행동·사용자 영역의 혼합 DPI 물리 횡단은 계속 확인한다. |
| 쓰다듬기·말풍선 | 기준 구현 | 진행 중 | 실제 frame 알파 쓰다듬기와 행동 우선·주기 runtime, 행동/주기 대사 분리, draft·즉시 저장·위치 미리보기를 구현했다. macOS와 Windows 말풍선은 현재 프레임의 캐시된 불투명 경계를 anchor로 사용하고 표시 중 자동 위·아래 방향을 가능한 동안 고정한다. Windows는 mask 미준비 시 aspect-fit 콘텐츠와 HWND 순서로 fallback하고 이동 중 XAML tree를 재생성하지 않는다. 실제 이동·투명 여백 프레임의 장시간 시각 QA, 혼합 DPI와 성능 검증이 남았다. |
| 로컬 가져오기·내보내기 | 진행 중 | 진행 중 | macOS는 설치 전 메타데이터·모션·권장 설정 검토, 권장 프로필 schema-v1~v11 호환, 패키지 저장 시 앱 규칙을 제외한 모든 휴대 옵션의 상시 포함, canonical 자산 선별·권리 확인·ZIP 왕복·원자적 저장을 구현했다. 일반 가져오기는 중복과 관계없이 새 installation·instance·profile을 추가하고 검토에서 기본/권장 설정을 선택하며 settings 실패 시 installation까지 되돌린다. 공통 확인 화면은 평상시 선택·조건 규칙 전체/사용 수·이동/입력 없음/앱 사용 우선순위·네 독립 이동 설정과 정확한 휴대/기기 전용 범위를 보여준다. 실제 대화상자와 Windows v11 교차 왕복 QA가 남았다. |
| 웹 URL 가져오기 | 기준 구현 | 진행 중 | Windows도 게시·manifest 최소 앱 버전을 합쳐 높은 값은 설치 가능한 권장 안내와 운영 다운로드 페이지 버튼으로 표시한다. 기존 URL allowlist·20MiB·크기·SHA-256·redirect·임시 수명 검증은 유지한다. 실제 운영 고버전 패키지 검토·설치 QA가 남았다. |
| 배포·업데이트 | 진행 중 | 진행 중 | macOS 1.6.0 (12)와 Windows 1.6.0.17 GitHub Pre-release를 게시하고 원격 digest 검증을 통과했다. macOS ZIP은 Developer ID 미서명·Apple 미공증 제한 Preview이고 Windows 설치기는 미서명 x64 Preview다. 업데이트 확인·자동 업데이트는 D-087에 따라 보류 |
| 멀티펫 | 기준 구현 (`1.1.0`) | 진행 중 (`1.1.0`) | Windows 10~11단계 schema-v11 계약, `PetInstanceManager`, instance별 HWND/runtime, NavigationView 활성 펫·notification area·일시정지·자원 경고·안전 시작 완료; 실제 환경 QA는 12단계 |

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

Windows 첫 EXE Preview 후속 단계에서는 package identity 감지, packaged `LocalState`와 unpackaged `%LOCALAPPDATA%\MonglePet` 데이터 루트, MSIX `StartupTask`와 현재 사용자 Run 자동 실행을 분리했다. .NET·Windows App SDK를 포함한 x64 publish를 Inno Setup 사용자별 설치기로 압축하고 SHA256SUMS를 생성한다. 실제 설치·동일 버전 업그레이드, `--startup` 설정창 숨김, MSIX 데이터 비파괴 이전, 실행 중 정상 종료 제거와 사용자 데이터 보존을 통과했다. 멀티펫 `1.1.0.13`은 병합 커밋에서 다시 만든 63,829,785 bytes 설치기와 SHA-256 `4E1572A58440B8450081B7F4FA90B182D9EF4414BA40F802749139D733E55AF7`을 태그 `windows-v1.1.0-preview.1`의 GitHub Pre-release로 게시했고 원격 asset digest 일치까지 확인했다. 자체 웹 다운로드 화면 반영은 별도 서버 담당자에게 전달할 문서를 준비한 상태다.

Windows 웹 펫 가져오기 `1.2.0.13` Preview는 소스 커밋 `3ee61a22979a12c42cdaf7d7bbc2c0b08640792b`에서 63,847,413 bytes 설치기와 SHA-256 `95C4446A42266E279D55138862EE4E2076BA46661F33E4FAFAA26D4CDF064A8A`을 생성했다. 기존 EXE 데이터 11개 파일과 개발 MSIX LocalState 22개 파일을 보존한 업데이트, packaged·unpackaged 실제 개발 URL 검토·취소, 라이브러리 무변경·임시 폴더 제거와 명시적 종료 후 프로세스 0개를 확인했다. 태그 `windows-v1.2.0-preview.1`의 GitHub Pre-release에 게시한 자산을 다시 내려받아 로컬 digest와 일치함을 확인했다. 같은 PC에 개발 MSIX와 공개 EXE를 동시에 등록한 Windows Shell scheme 선택은 충돌해 깨끗한 사용자 환경 후속 QA로 남겼다.

macOS 편집기·호환성 `1.3.0 (5)` Preview는 소스 커밋 `bf7874b3ef197f2badbe5fc8f3060864dda38843`에서 7,334,062 bytes ZIP과 SHA-256 `187629C944C4FAD36AC21548413B212EE9F2ED16CF669B84559BDD9C3CEE6B5F`을 생성했다. 전체 단위 테스트, Universal Release 빌드, 압축 해제본 실행과 새 내장 몽글이 설정 표시를 확인했다. 태그 `macos-v1.3.0-preview.1`의 GitHub Pre-release에 ZIP·체크섬·manifest를 게시하고 원격 자산을 다시 내려받아 바이트 단위 일치를 확인했다. Windows는 `WINDOWS_MACOS_1_3_HANDOFF.md`의 공통 fixture·호환성·편집 UI를 구현하고 실제 QA하기 전까지 동등 완료가 아니다.

macOS 이미지 편집 UI 보정 `1.3.1 (6)` Preview는 소스 커밋 `89ceb5444478eeb2717ac29ec930f4661503a794`에서 7,413,980 bytes Universal ZIP과 SHA-256 `BD0E59171DE502AC123ABE71F8EDD73D4C12A938D65A06186B644F2C8761CC04`를 생성했다. 전체 단위 테스트 469개 중 468개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 PNG·스프라이트 편집 화면을 확인했다. 태그 `macos-v1.3.1-preview.1`의 GitHub Pre-release에 세 자산을 게시하고 원격 자산의 바이트 단위 일치와 태그 대상을 검증했다. Windows 구현·실제 QA 전까지 플랫폼 상태는 계속 진행 중이다.

macOS 이동 런타임 성능 보정 `1.3.2 (7)` Preview는 소스 커밋 `8cae849167d71daa28566e930167e3e11e00201d`에서 7,430,815 bytes Universal ZIP과 SHA-256 `96617b60e5187eb0deb16088ab2706a572b0ee750c6adb55b494b9ee40a0b6cd`를 생성했다. 전체 472개 중 471개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개와 Debug·Universal Release 빌드를 통과했고, 압축 해제본의 버전·Bundle ID·두 아키텍처와 자유 이동·설정 창·기본 펫 표시를 확인했다. 태그 `macos-v1.3.2-preview.1`의 GitHub Pre-release에 세 자산을 게시하고 원격 자산의 바이트 단위 일치와 태그 대상을 검증했다. 이동 33ms cadence와 사용자 동작은 유지하며 공통 schema·fixture와 Windows 소스 변경은 없다.

macOS 행동 중심 설정·최종 몽글이 `1.4.0 (8)` Preview는 소스 커밋 `78ac0dfb52f0cb4e0d436649603c29dea91e652d`에서 8,833,960 bytes Universal ZIP과 SHA-256 `ebb3a12f0b829671399d44e1fd71ab16486e590f46ac1ec57f0c904aecf55820`을 생성했다. 전체 503개 중 502개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 `1.4.0 (8)`·Bundle ID·arm64/x86_64를 확인했다. 태그 `macos-v1.4.0-preview.1`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시하고 원격 자산의 바이트 단위 일치와 태그 대상을 검증했다. 실제 다른 Mac의 설정 마이그레이션·시각 동작 QA와 Windows 후속 구현은 남아 있다.

macOS 펫 제작기·활성 인스턴스 후속 `1.4.0 (10)` Preview는 소스 커밋 `1e142bb20dff2864917db2cbecd6c455944ede7c`에서 10,881,166 bytes Universal ZIP과 SHA-256 `0243ab285aaa27d6d26effa4749e0e3724b80d1b4702576c474dda3d985d454b`을 생성했다. 전체 515개 중 514개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 `1.4.0 (10)`·Bundle ID·arm64/x86_64·앱 아이콘을 확인했다. 태그 `macos-v1.4.0-preview.2`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시하고 원격 자산을 다시 내려받아 바이트 단위 일치와 태그 대상을 검증했다. 새 펫·사본의 실제 앱 QA와 Windows 교차 왕복은 남아 있으므로 해당 후속 기능의 플랫폼 동등 상태는 계속 진행 중이다.

macOS 평상시 행동·조건 규칙 분리 `1.5.0 (11)` Preview는 소스 커밋 `80b01678b41c0b80df5f5ad44d5df8987d908b09`에서 10,944,162 bytes Universal ZIP과 SHA-256 `43d375f6b1463bc3ebe9845b284c24c02ae796406258d4149aba60e153a74838`을 생성했다. 전체 521개 중 520개 성공·선택형 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 `1.5.0 (11)`·Bundle ID·arm64/x86_64·앱 아이콘, 격리된 3초 QA 실행을 확인했다. 태그 `macos-v1.5.0-preview.1`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시하고 원격 자산을 다시 내려받아 바이트 단위 일치와 태그 대상을 검증했다. Windows 자동 구현은 완료했지만 양 플랫폼 실제 UI·오버레이 QA와 권장 프로필 v11 교차 왕복 전까지 동등 상태는 계속 진행 중이다.

macOS 단일 `내 펫`·행동 런타임 보정 `1.6.0 (12)` Preview는 소스 커밋 `617af2e11ff9f404922227d1ca8aa6f60d8e999d`에서 10,889,967 bytes Universal ZIP과 SHA-256 `b48937ffdd03892b52049e9dc06d7a7698edf3c59da1cb589f6f1bc63f650129`을 생성했다. 전체 531개 중 530개 성공·조건부 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 `1.6.0 (12)`·Bundle ID·arm64/x86_64·앱 아이콘, 격리된 3초 QA 실행을 확인했다. 태그 `macos-v1.6.0-preview.1`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시하고 원격 자산을 다시 내려받아 바이트 단위 일치와 태그 대상을 검증했다. Windows는 `WINDOWS_MY_PETS_RUNTIME_POLISH_HANDOFF.md`의 최종 D-111~D-113 결과를 구현하고 실제 QA·교차 왕복을 마치기 전까지 플랫폼 동등 완료가 아니다.

macOS 문맥별 행동 반복 보정 `1.6.0 (13)` Preview는 소스 커밋 `c886a68e56520ff40e0bec27baf0ca2d9b40d430`에서 10,887,529 bytes Universal ZIP과 SHA-256 `c74d394a05301eb5ba39f12452fd7aa3d0c3c61769a657b2b287e7a223b430ca`를 생성했다. 전체 536개 중 535개 성공·조건부 WebP fixture 1개 건너뜀·실패 0개, Debug·Universal Release 빌드와 압축 해제본의 `1.6.0 (13)`·Bundle ID·arm64/x86_64·앱 아이콘, 격리된 3초 QA 실행을 확인했다. 태그 `macos-v1.6.0-preview.2`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시하고 원격 자산을 다시 내려받아 바이트 단위 일치와 태그 대상을 검증했다. schema-v15·권장 프로필 v11·저장 `repeats`는 유지하며 실제 교차 왕복 전까지 동등 상태는 계속 진행 중이다.

Windows `1.6.0.16` Preview 2는 D-115에 따라 평상시 `하나 선택` 행동을 깨어 있는 동안 연속 순환하고, 랜덤의 각 행동·조건 규칙·쓰다듬기의 1회 재생은 유지한다. 마우스 도망가기 평상시 자유 이동은 무작위 머무르기가 꺼진 경우 숨겨진 최소값을 검증하지 않고 저장 가능한 최대값 이하로 보정한다. 실행 중 앱 업데이트는 Inno Setup Restart Manager 대신 앱 전용 종료 메시지와 최대 30초 정리 대기를 사용한다. Debug·Release 각 313개 테스트, 실행 중 설치 업데이트와 48개 사용자 파일의 inventory digest 보존, 설치 DLL 일치·실행 응답을 통과했다. 소스 커밋 `3f91dec335300f6d29af41046819a9fd48f58e8a`를 태그 `windows-v1.6.0-preview.2`로 게시했고 65,279,431 bytes 설치기의 SHA-256 `228D1B459F6BA6A9E067294C35A2FDE0CEC9747299791C9F3785B302C594F6EA`와 원격 자산을 재검증했다. macOS도 D-115 runtime과 UI 안내를 반영해 관련 42개·머무는 시간 회귀 26개·전체 536개 테스트 및 Debug 빌드를 통과했다. 양 플랫폼 실제 장시간·교차 QA 전까지 동등 상태는 계속 진행 중이다.

Windows `1.6.0.17` Preview 3는 설치 직후 첫 프로세스에서 settings XAML이 준비되기 전에 overlay timer가 시작되던 순서를 Loaded 이후 dispatcher 경계로 옮기고 초기 activation을 대기시켰다. atlas의 일시적 첫 decode 실패는 성공 상태만 준비 완료로 간주하며 3회 제한 재시도한다. overlay physical pixel과 composition scale을 맞추고 `WM_DPICHANGED`, 화면 식별자 없는 좌표 복구, `내 펫` compact 배치와 settings `800×600` 최소 크기를 반영했다. Debug·Release 각각 313개 테스트와 경고·오류 없는 빌드, 기존 설치 위 업데이트와 48개 사용자 파일의 inventory digest 보존, 설치 DLL 일치·실행 응답을 통과했다. 소스 커밋 `18b13f7e26e70bbd55cd103ac2bbd363dea4521d`를 태그 `windows-v1.6.0-preview.3`으로 게시했고 65,273,031 bytes 설치기의 SHA-256 `4BDA35324A7BDEEC829DD41B943D954A7268BABC7502B67613E88345B2305FA3`와 원격 자산을 재검증했다. 설치 완료 화면 첫 실행과 실제 혼합 DPI 교차 모니터 QA 전까지 Windows 상태는 계속 진행 중이다.

Windows macOS 1.3.1 인계 구현은 Windows 마케팅 `1.3.0`, File·Assembly·MSIX `1.3.0.13` 후보로 펫 콘텐츠 자유 버전과 비차단 최소 앱 버전 advisory, PNG·스프라이트 제작 결과와 공통 내장 몽글이를 반영했다. crop→flip→선택적 배경 제거→공통 캔버스→atlas의 순수 픽셀 경로, 자동/균등/독립 경계, 읽기/클릭 순서, 1×~8× pan 소유권, 프레임별 flip·450ms·독립 복사와 알파 기준 공통 배치를 테스트했다. 공통 built-in의 10개 모션·36프레임·10개 PNG digest와 built-in 전용 Codex PFN 규칙·미수정 프로필 이관을 검증했다. 스프라이트 범위 편집은 Release loose AppX에서 현재 프레임의 중앙 이동과 겹친 경계의 8방향 크기 조절을 실제 상대 마우스 입력으로 확인했다. Debug·Release 각 Activity 27개, Core 38개, Packages 22개, PetLibrary 87개, Settings 72개, Shell 20개로 총 266개 테스트가 통과했고 loose AppX·unpackaged publish·설치본의 13개 built-in 파일 tree digest가 기준본과 일치했다. `1.2.0.13→1.3.0.13` packaged 22개·unpackaged 11개 사용자 파일을 보존한 업데이트와 실제 앱 실행을 확인했지만 최소 높이·혼합 DPI·Narrator·큰 이미지 반복 drag와 Windows→macOS 교차 왕복 전까지 상태는 계속 진행 중이다.

Windows `1.3.0.13` Preview는 소스 커밋 `2715cbb799687cbf26084c607848cc052fea666c`에서 64,866,058 bytes 설치기와 SHA-256 `5F8A14314447F70C74704793BC5ED0EA8744DF0276303470D366500D4777B808`을 생성했다. 사용자 데이터 22개 파일의 설치 전후 inventory digest를 보존했고 설치본 실행 응답과 Application 오류 0건을 확인했다. 태그 `windows-v1.3.0-preview.1`의 GitHub Pre-release에 설치기와 `SHA256SUMS.txt`를 게시하고 다시 내려받아 크기·digest·체크섬 파일이 로컬 최종본과 일치함을 확인했다.

Windows 멀티펫 10단계에서는 마케팅 버전 `1.1.0`과 schema-v11 `activePetInstances`·독립 `behaviorProfiles`·`selectedPetInstanceID`를 C# Domain·Settings에 반영했다. v1~v10 순차 이관, 공통 고정 UUID fixture, 동일 원본 두 인스턴스의 독립 profile·overlay 왕복, UUID·프로필 참조·소유권·선택·별명·표시 순서의 항목별 복구와 확장 필드 보존을 검증했다. 10단계 당시에는 단일 펫 WinUI·런타임의 선택 인스턴스 호환 view만 유지했고 다중 HWND·관리 UI는 아래 11단계에서 후속 완료했다. Debug·Release 각 176개 테스트가 통과했다.

Windows 멀티펫 11단계에서는 `PetInstanceManager`가 저장된 전체 instance를 `displayOrder` 순으로 복원하고 각 `PetRuntimeContext`가 별도 Win32/Composition 펫·말풍선 HWND와 행동·이동·말풍선·쓰다듬기 상태를 소유한다. activity·WTS/전원 메시지는 한 overlay만 구독해 전체에 배포하고 포인터·모니터·전면 창 snapshot과 같은 패키지의 atlas surface·알파 마스크 참조 계수 캐시를 공유한다. 설정 첫 화면을 왼쪽 `NavigationView`의 `활성 펫`으로 바꾸고 같은 원본 추가, 독립 설정 복사/기본값, 선택·별칭·display order·개별/전체 표시·제거·전체 일시정지와 단계적 안전 시작을 연결했다. notification area는 전체 명령과 instance별 선택·표시·클릭 통과·현재 화면 이동을 제공한다. 5초 저빈도 CPU·private memory 연속 압력만 비차단 경고로 표시하며 자동 중지나 삭제는 하지 않는다. Debug·Release 각 186개 테스트와 두 구성 빌드가 통과했으며 실제 다중 모니터·잠금·절전·설치 업데이트 검증 전까지 상태는 계속 진행 중이다.

2026-08-13 Windows 12단계 부분 실기기 QA에서 1.0.0.13→1.1.0.13 등록 업데이트, schema-v10→v11과 라이브러리 무손실 보존, 동일 설치본 3개 instance/profile/HWND 독립 생성, 개별·전체 표시와 일시정지, 재실행 복원, notification area 하위 메뉴, Explorer 재시작, 안전 시작 복원을 통과했다. 음수 좌표 화면 경계 보정값의 저장 누락을 수정했고 말풍선을 비활성 독립 tool window로 분리한 뒤 manager가 `말풍선→펫` HWND 그룹을 명시적 체인으로 정렬해 `displayOrder`와 실제 z-order가 일치하도록 했다. 말풍선 2개 동시 표시, 순서 변경과 재실행을 포함한 반복 샘플을 통과했다. 활성 펫 목록은 상태 갱신 때 기존 카드 view model과 container를 유지하도록 보완해 반복 등장 전환과 편집 포커스 초기화를 제거했고 실제 Release UI 포커스 유지 표본을 통과했다. 100% DPI 화면 2대만 연결된 환경이어서 혼합 DPI·물리 분리/재연결·잠금/절전은 검증하지 못해 Windows 상태는 계속 진행 중이다.

Windows 설정 정보 구조는 전환 탭과 보관 구역이 없는 단일 `내 펫` 대시보드와 `선택한 펫`의 `펫 정보·애니메이션`·`화면 표시`·`평상시 행동`·`이동`·`상호작용`·`행동 편집`·`말풍선`·`규칙 설정`으로 구현했다. `내 펫`은 macOS와 같은 순서로 독립 설정 안내, primary `펫 만들기`·secondary `펫 가져오기`, 전체 깨우기·재우기·일시정지를 표시한다. 각 카드는 항상 펼친 상태로 84px 실제 펫 미리보기, 이름·선택 badge·표시 상태, 원본 이름, 이동·클릭 통과, 별칭 저장, 사본·패키지 내보내기를 가운데에 두고 우측에 label 없는 화면 표시 switch·borderless 앞뒤 순서·삭제를 둔다. 내장 펫 내보내기는 숨기며 마지막 펫과 마지막 기본 몽글이 삭제는 비활성화한다. 선택 card는 옅은 accent 배경과 1.5px stroke를 사용한다. 목록은 WinUI `ListView` 단일 선택·시스템 초점 표시를 사용해 키보드와 Narrator 선택 경계를 유지하며 `NavigationView`와 Mica, grouped form 카드 계층도 유지한다. 실제 테마·좁은 창·키보드·Narrator QA 전까지 동등 완료로 표시하지 않는다.

위치 고정·클릭 통과 끔 조합의 드래그는 Composition `ContentIsland`를 입력 비활성인 그리기 전용 표면으로 고정하고, 공유 120Hz 포인터·버튼 snapshot과 실제 frame 알파 hit-test를 사용한 부모 overlay drag gesture로 처리한다. 실제 캐릭터 픽셀을 누른 드래그와 위치 저장을 사용자 실기기에서 확인했다.

활성 펫 카드는 앱 로고 대신 instance의 실제 패키지 미리보기를 표시하고 선택 포커스와 `설정 중` 상태를 분리했다. 선택은 runtime 전체 재동기화 없이 manager의 선택 경계만 변경하고 180ms debounce 원자적 저장과 페이지 진입 시 지연 갱신을 사용한다. 표시 중 말풍선은 위치 갱신 때 XAML site를 숨기거나 content를 교체하지 않고 캐시한 layout과 기존 tail geometry만 갱신한다.

이동 성능 점검에서 이동 애니메이션이 없는 마우스 따라가기가 100ms cadence로 제한되고, unchanged 1초 activity snapshot이 모든 instance의 행동·이동·manager UI 상태와 행동 timer를 갱신하던 두 원인을 확인했다. 이동 중 cadence를 정확한 60Hz 반복 timer로 분리하고 정지 반경 안에서만 100ms를 사용하며, 동일 activity 알림과 중복 창 위치 갱신·programmatic `WM_MOVE`의 좌표 재조회는 생략한다. 포인터·화면 범위 snapshot도 공유·캐시한다. 마우스 따라가기 1마리와 자유 이동 1마리의 Release 5분 60표본은 전체 시스템 CPU 평균 1.484%·최대 3.594%, private memory 127.73→133.29MiB(+5.57MiB)·최대 134.68MiB였고 120초 이후 안정됐다. 무응답·관련 Application 오류는 0건으로 D-079의 5분 기준을 통과했다. 혼합 DPI·다수의 동시 추적 펫과 잠금·절전은 아직 남아 있어 Windows 상태는 진행 중이다.

macOS 행동 설정 후속 단계에서는 펫 크기를 기존 pt 저장과 호환되는 192pt=100%·10~200% UI로 바꾸고 단위가 포함된 직접 입력과 빠른 크기 선택, 25% 미만 복구 안내를 추가했다. 자유 이동 머무르기는 고정 또는 최소~최대 랜덤 범위와 같은 크기의 0.5초 증감·별도 `초` 단위를 둔 네이티브 숫자 입력을 제공하며 목표 도착당 한 번만 추첨하고 변경값을 저장한다. `표시 및 이동` 첫 섹션은 `설정 대상 펫`과 별도 `펫 깨우기` 행으로 구성하고, 화면 표시·정지 반경·방향별 행동은 접지 않고 항상 노출하며 이동 범위가 모든 펫 공통임을 섹션에 표시한다. 모든 이동·방향별·쓰다듬기 행동 선택기는 행동 이름 대신 현재 애니메이션 이름 또는 `첫 애니메이션 외 N개`를 표시한다. 애니메이션 저장 시 자동 생성된 한 단계 `복사본` 행동 이름을 현재 애니메이션 이름으로 동기화하되 사용자 지정·여러 단계·이름 충돌은 보존한다. 입력 없음 규칙은 기존 밀리초 저장 계약을 유지하면서 `1...86,400초` 정수 입력과 1초 증감을 제공한다. 새 행동은 이름·첫 애니메이션·반복을 정하는 sheet에서 만들고, `랜덤 선택`은 복수 행동을 shuffle bag으로 각각 한 번씩 재생한다. 애니메이션 복제는 단일 버튼으로 복제본 편집 화면을 열고, 애니메이션 추가·수정과 같은 `행동 연결`에서 저장 시 새 행동이나 기존 행동 연결을 선택한다. 저장 전에는 행동을 만들지 않고 취소 시 복사본을 되돌리며 오류는 하단 작업 영역에 표시한다. 수정 화면은 현재 사용 행동을 표시하고 같은 애니메이션 중복 단계는 안내 뒤 허용한다. 후속 schema-v14에서는 따라가기·자유 이동·도망가기와 도망가기의 평상시 자유 이동 값을 완전히 분리했다. 권장 프로필 v10과 패키지 저장은 모든 행동·이동·쓰다듬기·말풍선·휴대 표시 옵션을 보존하고, v9 이하 적용은 없던 표시 설정을 덮어쓰지 않는다. Windows는 `WINDOWS_BEHAVIOR_CENTRIC_HANDOFF.md`에 따라 같은 정보 순서와 C# codec·WinUI·런타임, 교차 왕복·DPI·실제 이동 QA를 완료하기 전까지 진행 중이다.

Windows `1.4.0.13`은 schema-v11 사용자를 v12 안정 행동 ID·표시 이름, v13 랜덤 행동·랜덤 머무르기, v14 네 독립 이동 설정으로 순차 이관하고 권장 프로필 v10을 왕복한다. 자동/직접/랜덤 행동과 종류별 자동 규칙 우선순위, 하나의 1~86,400초 입력 없음 규칙, 이동보다 우선하는 자동 규칙의 실제 좌표 정지·재개, 목표 수명이 안정된 도망가기 평상시 자유 이동을 C# runtime에 연결했다. 행동 모드 선택은 `자동 규칙` 화면으로 옮겼고 자동 모드에서만 조건 규칙을 표시한다. 펫 보관함 사본은 새 패키지·프로필 식별자를 가지면서 현재 행동·이동·쓰다듬기·말풍선과 overlay를 복사하며, 중립 기본 행동도 내부 ID 대신 `기본`으로 표시한다. 말풍선 대사 요약과 행동 실행 상태 역시 안정 ID를 노출하지 않고 현재 표시 이름을 사용한다. 도망가기 평상시 자유 이동의 목표·행동을 매 tick 초기화하던 회귀를 상태 전환 1회 초기화로 고쳤고, 이동 설정은 350ms 저장 병합과 편집 중 부분 UI 갱신으로 포커스를 보존한다. 완료 랜덤 cursor·1초 activity 경합은 완료 요청 재시작과 중앙 random selector로 제거했고, callback 지연에도 프레임을 단조 시간으로 seek한다. atlas 준비 시간은 표시 행동에서 제외하고 최근 atlas를 제한 cache한다. 이동 시작 때 랜덤 cursor를 다음 shuffle bag 행동의 첫 frame으로 교체하는 결과는 macOS에도 반영했으며 실제 양 플랫폼 이동 QA가 남았다. 설정창은 말풍선·이동·행동·오버레이 frame·자원 경고의 runtime 구독과 활성 펫 runtime 문구를 모두 제거하고 저장된 표시 상태·이동 방식만 표시하며, 고정 위치 저장도 설정 화면을 갱신하지 않는다. 새 행동 루틴 생성과 이름 변경을 분리하고 단계 선택 상자의 애니메이션 이름 표시를 보완했다. 펫 HWND의 항상 위·비활성화 정책은 유지하며 투명 frame 픽셀만 입력을 통과시킨다. WinUI는 192px=100%의 10~200% 표시, 문제 해결 하위 안전 모드, 모든 펫 사본, 전체 행 애니메이션 선택, 단일 복제·저장 시 행동 연결, 현재 펫 프레임·flip·확대를 제공한다. 내장 펫 선택 중 닫힌 `SoftwareBitmapSource` 미리보기와 네이티브 overlay 원점·이동 누산 좌표 불일치 회귀를 각각 독립 `WriteableBitmap` generation 경계와 실제 픽셀 원점 재동기화로 수정했다. Debug·Release 각 296개 테스트와 loose AppX·unpackaged publish, packaged LocalState 22개 보존, unpackaged schema-v11의 3개 instance·4개 profile·라이브러리 21개 보존 이관을 통과했다. 설정창을 닫은 도망가기·자유 이동·고정 3펫 Release 5분은 평균 CPU 0.680%, private memory 126.51→126.51MiB·최대 129.62MiB, 무응답 0회였다. 랜덤 경합 첫 수정 Release의 별도 5분은 private memory 137.03→132.57MiB·최대 141.38MiB와 무응답 0회였고 이동 종료 랜덤 재시작의 최신 x64 Release 시각 QA가 남았다. 최종 미서명 설치기의 기존 설치본 업데이트와 사용자 데이터 40개 파일 보존, 설치본 실행 응답을 확인하고 `windows-v1.4.0-preview.1` GitHub Pre-release로 게시했다. 후속 `1.4.0.14`는 제작기 드래그·미리보기·독립 활성 인스턴스, 다크·라이트 설정 대비와 네 이동 방식의 실제 클릭 통과를 보완해 `windows-v1.4.0-preview.2`로 게시했다. 사용자 요청에 따라 후속 전체 자동 테스트는 생략했고 Debug 빌드·Release publish·별도 프로세스 클릭 통과를 확인했다. 혼합 100%·150%·200% DPI, Narrator, 큰 이미지 반복 drag, 실제 사본 생성·재실행 보존, Windows→macOS 실제 교차 왕복과 제거 QA가 남아 있으므로 Windows 플랫폼 동등 상태는 계속 진행 중이다.

macOS 평상시 행동·규칙 분리 단계에서는 로컬 schema-v15와 권장 프로필 v11을 도입했다. Windows도 같은 저장 결과와 WinUI 정보 구조를 구현하고 공통 v14→v15 fixture, v10→v11 codec, 고정·랜덤 공통 규칙 평가와 별도 rule scheduler를 검증했다. v14 automatic은 규칙 상태를 유지하며 manual·random의 휴면 규칙은 갑작스러운 활성화를 막기 위해 비활성화하되 설정값을 보존한다. macOS는 전체 521개 중 520개 성공·선택형 fixture 1개 건너뜀, Windows는 마우스 도망가기 목표 수명 회귀 2개를 포함해 Debug·Release 각 301개 성공과 두 구성 빌드를 통과했다. 실제 DPI·테마·접근성 QA와 macOS→Windows→macOS 권장 프로필 v11 왕복 전까지 진행 중이다.

## 스프라이트 시트 순서·프레임 간격 Windows 인계 체크포인트

### macOS에서 확정한 사용자 동작

- 앱 안의 `AI 제작 프롬프트 복사` 메뉴와 내장 프롬프트는 제거한다. 제작 안내는 `https://dev.mapleroom.kr/monglepet` 웹페이지에서 제공한다.
- 자동 감지한 경계가 여러 행에 걸치면 고유한 X·Y 시작 좌표를 기준으로 실제 행·열 수를 초기 표시한다. 예를 들어 7열×8행에서 감지한 56개 경계는 `8행`, `7열`로 표시한다.
- 기본 `읽기 순서`는 위에서 아래, 같은 행에서는 왼쪽에서 오른쪽으로 프레임을 구성한다.
- `클릭 순서`로 전환하면 기존 선택을 비우고 사용자가 경계를 클릭한 순서를 1번부터 기록한다. 다시 클릭하면 선택에서 제거하고 남은 프레임의 번호를 연속으로 다시 매긴다.
- `전체 선택`은 두 모드 모두 읽기 순서를 사용하며 `전체 해제`는 선택과 클릭 순서를 함께 비운다.
- 행·열은 1~32 범위에서 숫자를 직접 입력하거나 stepper로 바꿀 수 있다. 프레임 수 안전 상한은 기존 1,000개를 유지한다.
- 새 펫 생성, 새 애니메이션 추가와 기존 애니메이션에 프레임 추가의 새 프레임 간격 기본값은 모두 450ms다. 기존 저장 프레임의 간격은 임의로 바꾸지 않는다.
- 프레임 간격은 숫자 직접 입력, 10ms stepper와 100·250·450·1,000ms 빠른 선택을 제공하며 저장 허용 범위는 기존 16~60,000ms다.
- `범위 편집`에서는 스프라이트 경계를 독립적으로 이동·8방향 크기 조절하고 X·Y·너비·높이를 직접 입력하거나 선택 경계의 크기를 전체 경계에 적용할 수 있다.
- 스프라이트 시트의 별도 crop 미리보기는 포함·제외 클릭 및 범위 편집 대상과 분리하고, 현재 선택된 프레임만 최종 재생 순서대로 이전·다음 버튼이나 미리보기 클릭으로 순환해 확인한다.
- 개별·다중 PNG는 추가 전에 프레임별 crop을 확인하며 `⌘` 다중 선택, 선택 묶음 미리보기, 현재 크기 일괄 적용, 원본 전체 복원과 선택적인 투명 여백 자동 맞춤을 제공한다.
- crop과 최종 크기·위치를 분리한다. 공통 캔버스에서 선택 프레임을 직접 드래그하고 바닥 중심 기준의 위쪽 핸들로 크기를 바꾸며 첫 프레임을 반투명 기준으로 겹쳐볼 수 있다.
- 서로 다른 crop 크기의 한 가져오기 묶음에는 공통 초기 배율을 적용해 자동 맞춤 때문에 프레임별 크기가 달라지지 않게 한다.
- crop은 고정 미리보기 좌표와 원본당 1회 투명 경계 분석을 사용하고, 직접 배치는 드래그 중 경량 좌표 렌더링 후 종료 시 최종 캔버스를 합성한다.

### 공통 계약

- `.monglepet` manifest schema는 변경하지 않는다. 확정한 재생 순서는 기존 `frames` 배열 순서로, 간격은 기존 `durationMs`로 저장한다.
- 자동 감지 결과와 클릭 중간 상태는 편집 UI의 로컬 상태이며 패키지에 추가하지 않는다.
- PNG·스프라이트 원본, crop과 직접 배치 편집 이력도 패키지에 추가하지 않고 최종 atlas 픽셀로만 확정한다.
- 플랫폼 교차 확인은 같은 최종 `frames` 순서와 `durationMs`를 읽고 쓰는지로 판단한다.

### Windows 구현 범위와 필수 QA

1. WinUI 편집 UI에서 자동 경계의 고유 X·Y 좌표로 행·열을 추론하고, 실패 시 안전한 기본값으로 폴백한다.
2. 읽기 순서와 클릭 순서를 네이티브 선택 UI로 제공하고 최종 선택 배열이 그대로 패키지 프레임 순서가 되게 한다.
3. 사용자 펫 생성·애니메이션 추가·기존 애니메이션 프레임 추가의 기본값과 입력 UX를 450ms 기준으로 맞춘다.
4. Windows에 AI 프롬프트 복사 진입점이 있으면 제거하고 웹 안내를 제품 전달 경로로 사용한다.
5. 7열×8행 56프레임, 일부 빈 셀, `4→1→3` 클릭 순서, 선택 제거 후 재번호, 전체 선택, 450ms 추가와 기존 간격 보존을 자동·실제 앱에서 확인한다.
6. Windows에서 내보낸 패키지를 macOS에서, macOS에서 내보낸 패키지를 Windows에서 가져와 프레임 순서와 간격이 보존되는지 왕복 확인한다.
7. 스프라이트 경계 이동·8방향 크기 조절·숫자 좌표, 다중 PNG 개별 crop·투명 여백 맞춤과 공통 배율을 구현한다.
8. 첫 프레임 비교를 켠 상태에서 프레임별 직접 이동·크기 조절 후 전체 재생의 크기·기준점 안정성을 확인한다.
9. crop·배치 저장 뒤 내보낸 패키지에 원본이나 편집 이력이 포함되지 않고 macOS와 같은 최종 atlas 결과만 남는지 확인한다.
10. 스프라이트 선택 영역 미리보기를 포함·제외 및 범위 편집 대상과 분리하고, 선택된 프레임만 최종 재생 순서대로 이전·다음 탐색하게 한다. PNG 다중 선택·묶음 미리보기·일괄 crop 동작을 구현하고, 큰 이미지 드래그 중 전체 알파 재분석이나 전체 캔버스 재합성을 반복하지 않는지 확인한다.

## 멀티펫 1.1.0 Windows 인계 체크포인트

### 확정된 사용자 동작

- 제품상 활성 마릿수 제한을 두지 않는다. 저장 파일 손상 방어 상한은 사용자 제한과 구분하며 성능 저하만으로 앱이 펫을 자동 중지·숨김·삭제하지 않는다.
- 같은 설치 펫을 여러 번 추가해도 각 항목은 별도 instance ID, behavior profile ID, 별칭, 표시 상태, overlay, 이동·행동·말풍선 설정과 런타임을 가진다.
- 원본 펫 정의를 편집하면 선택 인스턴스만 편집 사본으로 전환하고 같은 원본의 다른 인스턴스는 유지한다.
- 사용자가 정한 `displayOrder`가 창의 앞뒤 순서이며 클릭이나 마지막 상호작용이 순서를 영속적으로 바꾸지 않는다.
- 전체 일시정지는 저장 설정을 바꾸지 않는 실행 전용 상태다. 자원 경고는 비차단 안내이며 사용자가 재개·재우기·제거를 선택한다.
- 시작 중 비정상 종료 저널이 남으면 다음 실행에서 자동 복원을 멈추고 개별·전체·마지막 항목 제외 복원을 제공한다.

### 공통 계약과 fixture

- 이 체크포인트 당시 공통 설정 형식은 schema-v11이었다. macOS 현재 형식은 schema-v12이며 Windows는 v11을 유지한 채 `WINDOWS_BEHAVIOR_CENTRIC_HANDOFF.md`에 따라 v12로 후속 이관한다. `activePetInstances`, `behaviorProfiles`, 선택 instance 참조와 UUID 소유권의 의미는 유지한다.
- `shared/Fixtures/Settings/schema-v10-single-pet.json`과 `schema-v11-single-instance.expected.json`을 Windows portable codec의 첫 교차 검증 입력·기대 결과로 사용한다.
- 화면 식별자·좌표, macOS bundle identifier, Windows PFN/실행 파일명과 권한 상태는 플랫폼 로컬 값이며 교차 설정이나 `.monglepet` 패키지에 섞지 않는다.
- 앱 마케팅 버전은 두 플랫폼 모두 `1.1.0`이며 플랫폼별 빌드 번호는 독립적으로 증가시킨다.

### Windows 구현 범위

1. C# portable Domain·Settings에서 schema-v11 읽기·쓰기, v1~v10 순차 이관, 항목 단위 복구와 공통 fixture를 먼저 통과시킨다.
2. `PetInstanceManager`가 instance별 runtime을 소유하고 전면 앱·입력 없음·포인터·화면 snapshot과 디코딩 자원은 프로세스 단위로 공유한다.
3. 펫마다 별도 Win32 `HWND`와 `Microsoft.UI.Composition` 표시를 만들고 위치·표시 상태·이동·행동·쓰다듬기·말풍선을 독립 적용한다.
4. 설정 첫 화면은 WinUI `NavigationView`의 `활성 펫`으로 구성하고 같은 원본 추가, 선택, 별칭, 순서, 개별/전체 깨우기·재우기·일시정지와 제거를 제공한다.
5. notification area에는 전체 명령 뒤 인스턴스별 빠른 제어를 제공하고, 비차단 CPU·private memory 경고와 시작 복구 UX를 Windows 방식으로 구현한다.

### Windows 실제 환경 완료 조건

- 동일 펫 여러 인스턴스의 독립 편집·창·위치·앞뒤 순서와 앱 재실행 복원
- 혼합 DPI·음수 좌표 다중 모니터 왕복, 화면 분리·재연결과 Explorer 재시작
- 잠금·절전·재개 중 모든 인스턴스의 timer·Composition 중지와 안전 복귀
- 다수 펫 packaged Release CPU·GPU·private memory·프레임 지연과 장시간 증가량
- 시작 중 강제 종료 후 안전 시작, 손상·미래 schema·과대 컬렉션의 창 생성 전 방어
- 기존 1.0.x 설치의 설정·펫 보관함을 보존한 1.1.0 설치·업데이트·제거

## 신규 기능 작업 규칙

2026-08-27 macOS와 공통 기준본은 사용자 제공 패키지 SHA-256
`d33c6265475969278012b96d4906311d73891c68b1b13c8e0464ac0bbaf47f9b`를 검증해
내장 몽글이 `1.0.3`, 13개 모션·53프레임과 권장 프로필 v10으로 갱신했다. 종전
미수정 기본 프로필만 새 값으로 승격하고 사용자 수정 프로필의 안정적 행동 ID와
규칙·이동 설정은 보존한다. Windows는 이 공통 기준본과
`WINDOWS_BUILTIN_MONGLE_HANDOFF.md`를 적용하고 실제 QA하기 전까지 진행 중이다.

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

## 2026-08-29 Windows 펫 제작기 UX 후속

Windows는 스프라이트 이동·8방향 크기 조절의 명시적 입력 영역과 드래그 시작 배율 고정, 사용자가 적용할 때만 바뀌는 읽기 순서, 좁은 설정 열의 2열 뒤집기 버튼을 반영했다. 작은 경계에서는 조절점 입력 영역을 경계 크기에 맞춰 제한하고 모달 루트 좌표·실제 버튼 상태·취소 복원을 사용해 이동 의도가 상단/좌우 축소로 오인되는 튐을 막는다. 새 펫과 편집 가능한 사본은 현재 펫 키를 교체하지 않고 새 활성 인스턴스·프로필로 추가하며 사본은 현재 프로필·overlay를 복사한다. D-104에 따라 Windows 제작 UI의 신규·수정 버전은 숫자형 `MAJOR.MINOR.PATCH`로 제한하지만 외부 자유 문자열 패키지 로드는 보존한다.

Windows 설정 컨트롤은 Default(Dark)·Light별 공통 버튼 fill·stroke와 pointer/pressed/disabled 상태를 사용한다. primary button과 선택 badge는 따뜻한 MonglePet 강조색을 유지하며 Dark는 `#F2B46D`와 어두운 glyph `#2D2117`, Light는 `#9A520F`와 밝은 glyph `#FFF7F0`을 사용한다. 중립 보조 버튼은 Dark `#484848`/`#898989`, Light `#F3F3F3`/`#737373` fill·stroke로 primary와 구분한다. Slider와 ToggleSwitch는 장시간 설정 화면에서 주황색이 과도하게 반복되지 않도록 별도 중립 상태 팔레트를 쓴다. Dark slider는 밝은 값 구간과 중간 회색 나머지 track을 사용하고 switch는 `켜짐=밝은 track+어두운 knob`, `꺼짐=어두운 track+밝은 knob`로 두 색을 반전한다. Light는 값/켜짐 구간을 진하게, 비활성 track을 밝게 표시한다. ToggleSwitch는 현대 fill/stroke/knob와 구형 curtain/track의 normal·pointer·pressed·disabled 리소스를 모두 덮어 시스템 강조색 복귀를 막는다. 라디오는 선택 테두리와 중앙점을 함께 표시하며 슬라이더는 선택 값 구간과 나머지 track을 분리해 색상에만 의존하지 않는다. 클릭 통과는 선택 인스턴스 overlay에 즉시 저장·동기화되며 토글 본문이 `클릭 통과 중`과 `펫 클릭 가능`으로 실제 결과를 설명한다.

Windows 클릭 통과는 다른 프로세스의 뒤쪽 창이 실제 입력을 받는 것을 완료 기준으로 한다. 클릭 통과 중에는 최상위 펫 HWND의 `WS_EX_LAYERED | WS_EX_TRANSPARENT`와 `DesktopChildSiteBridge` 자식 HWND의 `WS_EX_TRANSPARENT`를 함께 사용한다. `DesktopChildSiteBridge.Show()`가 부모 Composition 스타일을 다시 적용할 수 있으므로 Show 완료와 부모의 이동·크기·z-order 변경 뒤에는 부모·현재 자식 HWND를 모두 확인하고 핸들 또는 스타일이 달라진 경우에만 투명 입력 스타일을 복구한다. 클릭 가능 모드에서는 최상위 창을 no-redirection Composition target으로 복구하고 프레임 알파 기반 `HTCAPTION` 드래그를 유지한다. 네 이동 방식의 최종 실제 교차 창 QA는 남아 있다.

애니메이션 배율은 뷰포트가 아니라 실제 펫 배치를 25~400%로 바꾸고 캔버스 밖 배치는 최종 합성에서 clip한다. 제작기 투명 격자는 저대비 테마 색상, 버튼은 공통 높이·테두리 계층을 사용한다. Debug 빌드는 통과했지만 사용자가 직접 수행할 실제 UI QA와 `MACOS_PET_EDITOR_FOLLOWUP.md`의 macOS 반영 전까지 이 항목은 플랫폼 동등 완료가 아니다.

## 2026-09-03 Windows 첫 실행·DPI·좁은 창 보정

Windows 설치 완료 화면의 `postinstall` 실행은 일반 재실행보다 빠르게 새 프로세스를 시작하므로, settings 창의 XAML content가 Loaded 되고 dispatcher가 첫 메시지 처리를 마친 다음 overlay·행동·이동 runtime을 생성하도록 시작 경계를 옮겼다. 이 경계 이전에 들어온 protocol activation도 초기화 완료 뒤 순서대로 처리한다. atlas surface는 성공 완료만 재생 준비로 취급하고 일시적 디코딩 실패를 동일 프로세스에서 제한 재시도한다.

펫 크기는 Win32 화면·작업 영역과 같은 물리 픽셀 계약으로 유지하고 `DesktopChildSiteBridge`의 monitor DPI 자동 확대가 중복 적용되지 않게 scale을 1로 고정했다. `WM_DPICHANGED`에서 물리 크기를 다시 적용하고 이동 runtime의 display cache와 저장 위치 보정을 갱신한다. 화면 식별자가 없는 첫 좌표는 현재 화면 우하단 안전 위치를 사용하며 레거시 좌표는 가장 가까운 작업 영역 안으로 clamp하고 적용 결과를 instance overlay에 되돌린다.

`내 펫`은 좁은 창과 높은 DPI에서 NavigationView가 자동 compact 모드로 바뀌고, 생성·가져오기와 전체 펫 제어는 균등 열로 줄어든다. 카드도 compact 상태에서 preview와 간격을 줄이고 이동·상호작용 설명을 세로로 배치하며 사본·내보내기 작업은 아이콘과 접근성 이름·tooltip을 유지해 잘림을 피한다. 실제 619px 폭 QA에서 내보내기 버튼이 잘리는 결과를 반영해 settings HWND의 최소 추적 크기는 `800×600` effective pixel을 현재 monitor DPI로 환산하되 작업 영역보다 커지지 않게 제한하고, 실행 시 더 작은 창도 즉시 최소 크기로 넓힌다. Debug·Release 각각 313개 테스트와 두 구성 빌드가 경고·오류 없이 통과했다. `1.6.0.17` 설치본 업데이트·데이터 보존·실행 응답과 GitHub 원격 digest를 확인했으며 Inno Setup 완료 화면 첫 실행 및 100%·150%·200% 혼합 DPI 교차 모니터 QA 전까지 Windows 상태는 진행 중이다.

---

문서 상태: active
마지막 갱신: 2026-09-03
