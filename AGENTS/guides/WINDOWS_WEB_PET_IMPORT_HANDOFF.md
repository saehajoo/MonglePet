# Windows 웹 펫 가져오기와 보관함 UI 인계

> 가져오기 검토와 설정 적용 방식은 D-121 및 `WINDOWS_PET_IMPORT_CREATOR_SETTINGS_HANDOFF.md`가 이 문서의 과거 선택형·fallback 설명을 대체한다. URL 검증·다운로드·임시 파일 수명과 보관함 정보 구조는 이 문서를 계속 따른다.

## 목적

이 문서는 macOS에서 확정한 공개 웹 펫 가져오기와 정리된 펫 보관함 UI를
Windows WinUI 3 앱에 반영하기 위한 구현 기준이다. Windows 소스 변경·빌드·실제
QA는 Windows 환경에서 진행한다.

기능 결과와 정보 구조는 macOS를 기준으로 맞추되 WinUI 3의 Mica, 기존
`SettingsCardStyle`, `SettingsSubcardStyle`, `SettingsDividerStyle`, `InfoBar`,
`ContentDialog`와 Windows 파일 선택기를 유지한다. SwiftUI 컨트롤을 그대로
모방하지 않는다.

## 구현 전 확인할 원본

- 공통 패키지·URL 계약: `AGENTS/specifications/PET_PACKAGE.md`의 공개 웹 URL 가져오기
- 제품 결정: `AGENTS/project/DECISIONS.md`의 D-083
- macOS 기준 UI: `apps/macos/MonglePet/SettingsView.swift`의
  `petPackageSection`, `RemotePetImportControls`
- macOS URL·다운로드 검증: `apps/macos/MonglePet/PetLibrary/RemotePetImport.swift`
- Windows 현재 UI: `apps/windows/src/MonglePet.Windows/MainPage.xaml`의
  `PetLibraryCard`
- Windows 기존 로컬 검토·중복·내보내기:
  `apps/windows/src/MonglePet.Windows/MainPage.xaml.cs`

## 확정 URL과 앱 연결 계약

| 환경 | 펫 목록 | 펫 상세 | API origin |
| --- | --- | --- | --- |
| 개발 | `https://dev.mapleroom.kr/monglepet/pets` | `https://dev.mapleroom.kr/monglepet/pets/{slug}` | `https://dev-api.mapleroom.kr/api/v1` |
| 운영 | `https://mapleroom.kr/monglepet/pets` | `https://mapleroom.kr/monglepet/pets/{slug}` | `https://api.mapleroom.kr/api/v1` |

- Debug의 `펫 보러가기`는 개발 목록, Release는 운영 목록을 연다.
- 사용자 입력과 custom scheme에는 API URL, PetVersion UUID, 만료 다운로드 URL,
  token이나 로그인 정보를 넣지 않는다.
- 앱 연결 형식은 두 플랫폼 모두
  `monglepet://install?url=<percent-encoded canonical HTTPS detail URL>`이다.
- 상세 URL은 HTTPS, 정확한 host와 `/monglepet/pets/{slug}` 세 경로 요소만
  허용한다. user info, 명시적 port, 추가 path와 잘못된 slug는 거부한다.
- API는 HTTP 200 안에 오류 envelope를 반환할 수 있으므로 HTTP status와 함께
  `status`, `code`, `message`, `data`를 판정한다.
- 상세 응답의 대표 버전 UUID로 매번 새 download metadata를 조회한다.
- 상세·download metadata의 `size_bytes`, 소문자 64자리 `sha256`이 일치해야
  하며 최소 앱 버전과 20MiB 상한을 먼저 확인한다.
- 다운로드는 같은 API origin의 `/media/monglepet/downloads/{opaque}` 한 경로만
  허용한다. HTTPS downgrade, 다른 origin redirect, cookie와 credential 저장을
  허용하지 않는다.
- 실제 파일 크기와 SHA-256을 다시 확인한 뒤에만 기존 Windows
  `ReviewPackage`와 D-121의 호환성 검토로 넘긴다. package·게시 metadata 최소
  버전 중 높은 값이 현재 앱보다 크면 설치하지 않고 공식 앱 다운로드 페이지
  이동을 제공한다.
- 다운로드만으로 자동 설치하거나 현재 펫을 바꾸지 않는다.

## macOS에서 확정한 펫 보관함 정보 구조

Windows `PetLibraryCard`의 큰 순서는 다음과 같이 맞춘다.

1. 현재 펫 선택과 미리보기·메타데이터
2. 애니메이션 목록과 편집 작업
3. 웹에서 펫 가져오기
4. Windows의 패키지 가져오기
5. 현재 펫 내보내기
6. 펫 관리

현재 Windows의 `MonglePet 패키지` 한 영역 안에 가로로 붙어 있는
`패키지 가져오기…`와 `현재 펫 내보내기…`는 제거한다. 세 작업을 한 행이나 한
버튼 그룹에 다시 합치지 않는다.

## Windows에서 재현할 상세 UI

### 1. 웹에서 펫 가져오기

하나의 세로 `StackPanel` 또는 동일한 grouped subcard 안에 다음 순서로 배치한다.

1. 제목: `웹에서 펫 가져오기`
2. 본문: `MonglePet 웹에서 원하는 펫을 찾아보세요.`
3. 설명: `펫 상세 화면에서 앱으로 가져오거나 주소를 복사할 수 있습니다.`
4. 전체 가로 폭의 accent 버튼: 아이콘과 `펫 보러가기`
5. `SettingsDividerStyle` 구분선
6. 소제목: `주소로 직접 가져오기`
7. 설명: `MonglePet 펫 상세 주소가 있다면 아래에 붙여 넣으세요.`
8. 한 줄 `TextBox`
9. 보조 버튼: `주소에서 가져오기`
10. 진행·오류 상태

`TextBox.PlaceholderText`는 URL 예시가 아니라 정확히
`펫 상세 주소를 붙여 넣으세요`로 표시한다. 실제 URL처럼 보이는 placeholder,
클릭 가능한 링크 또는 입력란과 같은 행에 있는 `펫 보러가기`는 사용하지 않는다.

`펫 보러가기`는 이 영역의 주 작업이므로 `AccentButtonStyle` 또는 프로젝트의
동등한 강조 스타일을 사용하고 카드 가로 폭을 채운다. `주소에서 가져오기`는
보조 작업이므로 일반 `Button` 스타일을 사용한다. 두 버튼을 동시에 accent로
표시하지 않는다.

가져오기 중에는 입력과 두 가져오기 진입점을 중복 실행할 수 없게 하고 버튼 내부
또는 바로 아래에 작은 `ProgressRing`과 `펫 정보를 확인하는 중…`을 표시한다.
Enter는 값이 있을 때 `주소에서 가져오기`와 같은 동작을 수행한다.

### 2. Windows의 패키지 가져오기

웹 영역 다음에 `SettingsDividerStyle`로 분리한다.

- 제목: `Windows의 패키지 가져오기`
- 설명: `PC에 저장된 .monglepet 파일을 선택해 설치 내용을 확인합니다.`
- 버튼: `패키지 파일 선택…`
- 기존 `FileOpenPicker`, `ReviewPackage`, 중복 설치 처리와 원자적 rollback은
  재사용하고, 제작자 설정 적용은 D-118에 따라 자동화한다.

기존 파일 선택 기능을 웹 URL 서비스에 합치지 않는다. URL과 로컬 파일 모두 최종
검토 대화상자는 공유하지만 입력·다운로드 단계는 독립적이다.

### 3. 현재 펫 내보내기

로컬 가져오기 다음에 다시 구분선을 둔다.

- 제목: `현재 펫 내보내기`
- 설명: `선택한 펫과 선택적인 권장 설정을 .monglepet 파일로 저장합니다.`
- 버튼: `패키지 파일로 저장…`
- 내보낼 수 없는 내장 펫이면 버튼 대신 lock 아이콘과
  `내장 몽글이는 패키지 파일로 내보낼 수 없습니다.`를 표시한다.
- 기존 권리 확인, 권장 설정·앱 규칙 선택, `FileSavePicker`와 canonical export를
  재사용한다.

## 반응형·시각 기준

- 기존 `PetLibraryCard`의 좌우 padding, 섹션 간 14px 안팎 spacing과 divider
  스타일을 재사용한다.
- 웹·로컬·내보내기 섹션은 모두 세로 흐름이다. 좁은 창에서도 버튼이나 입력란을
  한 행에 억지로 배치하지 않는다.
- 설명은 `SettingsCaptionStyle`, 섹션 제목은 기존
  `BodyStrongTextBlockStyle`을 우선한다.
- 입력란은 카드의 사용 가능한 폭을 채우되 기존 중앙 최대 폭과 반응형 규칙을
  깨지 않는다.
- 오류 때문에 카드 폭이나 버튼 위치가 좌우로 움직이지 않게 한다.
- macOS와 문구·순서·강조 수준을 맞추고, corner radius·focus visual·hover·키보드
  탐색은 WinUI 기본 동작을 유지한다.
- Tab 순서는 `펫 보러가기 → 주소 입력 → 주소에서 가져오기 → 패키지 파일 선택 →
  패키지 파일로 저장`이어야 한다.
- 각 컨트롤에 안정적인 `x:Name`과 `AutomationProperties.Name`을 제공한다.

## 오류와 복구 UX

웹 가져오기 오류는 전체 보관함의 기존 성공 메시지와 섞지 말고 주소 입력 영역
바로 아래의 전용 inline `InfoBar`에 표시한다. 오류가 생기면 버튼 문구를
`다시 시도`로 바꾸고 주소 수정 시 이전 오류를 닫는다.

| 상황 | 사용자 안내 기준 |
| --- | --- |
| 지원하지 않는 주소·custom scheme | `지원하는 MonglePet 펫 상세 주소를 입력해 주세요.` 또는 `MonglePet에서 열기 링크가 올바르지 않습니다.` |
| 인터넷 없음 | `인터넷 연결을 확인한 뒤 다시 시도해 주세요.` |
| timeout·연결 끊김 | `서버 응답이 늦거나 연결이 끊겼습니다. 잠시 뒤 다시 시도해 주세요.` |
| DNS·host 연결 실패 | `MonglePet 서버에 연결할 수 없습니다. 주소를 확인하거나 잠시 뒤 다시 시도해 주세요.` |
| TLS·인증서 오류 | `MonglePet 서버와 안전하게 연결할 수 없어 가져오기를 중단했습니다.` |
| 잘못된 API 응답 | `펫 서버의 응답을 확인할 수 없습니다. 잠시 뒤 다시 시도해 주세요.` |
| metadata 불일치 | `펫 상세 정보와 다운로드 정보가 일치하지 않아 가져오기를 중단했습니다.` |
| 20MiB 초과 | `패키지가 최대 허용 크기 20 MiB를 초과합니다.` |
| 실제 크기·SHA-256 불일치 | 게시된 정보와 일치하지 않음을 구체적으로 표시 |
| 최소 버전 미달 | 필요한 버전과 현재 버전을 함께 표시 |

어떤 실패에서도 라이브러리, 현재 펫과 설정을 변경하지 않는다. 다운로드 임시
폴더는 실패·취소·설치·중복 처리 완료 후 제거한다. 앱이 비정상 종료된 경우에도
다음 시작이나 OS temp 정리 정책으로 잔여 파일을 회수할 수 있게 Windows 전용
수명 정책을 작업 계획에 기록한다.

## Windows protocol 등록

- packaged MSIX는 `Package.appxmanifest`에 `monglepet` protocol activation을
  등록하고 실행 중·종료 상태 activation을 같은 request router로 전달한다.
- unpackaged EXE 설치기는 현재 사용자 범위의 `monglepet` URL protocol 등록과
  제거를 담당한다. command 문자열은 실행 파일과 `%1`을 각각 안전하게 quote하고
  사용자 입력을 shell 명령으로 다시 해석하지 않는다.
- unpackaged EXE 설치기는 직접 scheme key뿐 아니라 전용 ProgID와 현재 사용자
  `RegisteredApplications`/`Capabilities`의 URL association도 등록한다. 제거 시에는
  각 command와 등록값이 제거 대상 설치본과 정확히 일치할 때만 해당 키를 정리한다.
- 두 배포 채널이 동시에 설치될 수 있는 경우 기본 handler 선택과 제거 후 복구
  정책을 문서화하고 실제 Windows에서 확인한다.
- 잘못된 activation은 앱을 자동 설치 화면으로 넘기지 않고 `펫 보관함`을 연 뒤
  inline 오류를 표시한다.
- Windows Shell은 authority 뒤 빈 path를 `/`로 정규화해
  `monglepet://install/?url=...`를 전달할 수 있다. Windows activation 경계에서만
  이 정확한 한 개의 slash를 제거하고, 공통 deep link parser는 `/`, `//`, 추가
  path와 다른 query를 계속 거부한다.
- packaged는 manifest association을 소유하고 unpackaged 설치기는 HKCU
  `Software\Classes\monglepet` handler를 등록한다. 두 채널이 공존할 때 OS가 고른
  기본 handler를 따르며, unpackaged 제거 시 command가 제거 대상 EXE와 정확히
  일치할 때만 HKCU protocol tree를 삭제한다. packaged 등록 자체는 수정하지 않는다.
- unpackaged 실행 중 요청은 AppInstance 단일 인스턴스 판정 뒤 기존 notification
  area HWND의 class·title·소유 실행 파일을 확인하고 최대 8KiB `WM_COPYDATA`로
  전달한다. 수신 측은 scheme과 공통 deep link 전체를 다시 검증하며 자동 설치하지
  않는다.
- 브라우저는 origin과 custom scheme 조합별로 외부 앱 실행 동의를 별도로 관리할 수
  있다. 앱 설치기는 Chrome·Edge 등 특정 브라우저 프로필이나 기업 정책을 수정하지
  않는다. 웹 상세 화면은 실행 성공을 직접 판정할 수 없음을 전제로, 버튼 클릭 뒤에도
  앱이 보이지 않을 때 확인할 브라우저 외부 앱 실행 안내, 재시도와 `.monglepet` 직접
  다운로드·앱의 로컬 가져오기 대안을 함께 제공한다.

## 권장 구현 경계

- URL parser, 환경 매핑, metadata 비교와 오류 모델은 UI·파일 시스템에서 분리한
  순수 C# 계층으로 둔다.
- `HttpClient`와 temp 파일 소유권은 Windows adapter/service가 담당한다.
- WinUI page는 주소 입력, busy/error state와 기존 import review 연결만 담당한다.
- 현재 `App.ReviewPackage`, `ImportReviewedPackage`, `ResolveDuplicateImport`와
  export 서비스는 그대로 재사용한다.
- `.monglepet` manifest schema와 settings schema는 변경하지 않는다.
- macOS의 Swift 타입이나 App Sandbox 세부사항을 C# 공통 계약에 넣지 않는다.

## 자동 테스트

1. 개발·운영 상세 URL 정상 파싱과 canonical URL 생성
2. 다른 scheme·host·port·userinfo·추가 path·잘못된 slug 거부
3. 정확한 custom scheme query 한 개만 허용
4. 성공·실패 envelope와 HTTP 오류 처리
5. 상세·download metadata 불일치, 최소 버전 미달과 20MiB 초과 거부
6. 다운로드 실제 크기·SHA-256 불일치 거부
7. 다른 origin·HTTPS downgrade redirect 거부
8. 정상 다운로드가 기존 `ReviewPackage`로 전달되고 설치 전에는 라이브러리를
   바꾸지 않음
9. 실패·취소·중복 처리 뒤 temp 폴더 제거
10. ViewModel 또는 UI 테스트에서 URL 수정 시 오류 해제, busy 중 중복 실행 방지,
    버튼 문구와 enable 상태 확인

## 실제 Windows QA

1. Debug `펫 보러가기`가 개발 목록, Release가 운영 목록을 연다.
2. placeholder가 URL이 아닌 `펫 상세 주소를 붙여 넣으세요`로 보인다.
3. 웹 탐색과 주소 직접 입력 사이에 구분선이 있고 두 작업이 한 행에 있지 않다.
4. 로컬 파일 가져오기와 현재 펫 내보내기도 각각 별도 섹션으로 보인다.
5. 실행 중·종료 상태의 `monglepet://install?...`가 같은 검토 화면을 연다.
6. packaged와 unpackaged 설치에서 protocol activation을 각각 확인한다.
7. 정상 개발·운영 주소, 잘못된 주소, offline, timeout과 checksum 불일치 상태를
   확인한다.

8. 설치 취소, 설치, 기존 설치 교체, 별도 설치 뒤 임시 파일과 선택 상태를 확인한다.
9. 키보드 Tab·Enter, Narrator 이름, 100%·150%·200% DPI와 좁은 설정창을 확인한다.
10. Windows에서 URL로 설치한 패키지를 내보내 macOS에서 다시 가져오는 왕복을
    확인한다.

2026-08-24 Windows `1.2.0.13` 개발 MSIX에서 기존 `1.1.0.13` LocalState
22개 파일을 그대로 보존한 등록 업데이트와 실제 packaged 개발 URL activation을
확인했다. 검토 화면의 설치·취소 버튼이 표시됐고 취소 뒤 라이브러리 변경과
`MonglePetRemoteImport-*` 임시 폴더는 0개였다.

2026-09-04 운영 상세 화면의 `MonglePet에 추가` 링크, 현재 사용자 EXE protocol
등록과 실행 중 기본 프로세스 전달을 확인했다. 테스트 장비의 Chrome `Default`
프로필에는 명시적인 차단도 허용도 없었지만 외부 앱 확인창이 나타나지 않았고,
`https://mapleroom.kr`과 `monglepet` 조합을 사용자가 허용한 뒤에는 같은 버튼이
반복해서 정상 동작했다. 이는 앱 설치기가 브라우저 권한을 강제로 쓰는 근거가 아니며,
웹의 실패 안내·재시도·직접 패키지 가져오기 fallback 필요성을 확인한 QA 결과다.

## 완료 조건

- Windows 네이티브 구현·자동 테스트·Debug/Release 빌드와 위 실제 QA를 모두
  완료한다.
- macOS와 Windows에서 사용자가 보는 작업 순서·문구·검토 결과가 동등하다.
- 의도적인 WinUI 차이는 작업 계획에 이유와 대체 UX를 기록한다.
- 완료 후 `AGENTS/project/PLATFORM_PARITY.md`의 `웹 URL 가져오기`를 `동등`으로
  갱신한다.
