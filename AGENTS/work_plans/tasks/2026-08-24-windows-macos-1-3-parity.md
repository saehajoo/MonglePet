# Windows macOS 1.3.1 호환성·이미지 편집기·내장 몽글이 동등성

## 상태

- 상태: in_progress
- 생성일: 2026-08-24
- 마지막 갱신: 2026-08-25

## 목표

- macOS `1.3.1 (6)`에서 확정한 펫 콘텐츠 버전, 최소 앱 버전 권장 정책과 PNG·스프라이트 제작 결과를 Windows 네이티브 앱에서 같은 사용자 결과로 제공한다.
- `shared/BuiltInPets/Mongle.monglepet`을 Windows 내장 몽글이의 단일 공통 기준본으로 사용하고 기존 사용자 설정을 무손실 이관한다.
- 공개된 Windows `1.2.0.13`을 덮어쓰지 않는 Windows `1.3.0` Preview 후보를 검증한다.

## 범위

- 펫 콘텐츠 `version` 자유 문자열 보존과 앱 호환 버전 전용 `MAJOR.MINOR.PATCH` 검증
- 로컬·웹 최소 앱 버전 비차단 권장 안내와 운영 다운로드 페이지 버튼
- crop → 좌우·상하 flip → 공통 캔버스 배치 → atlas PNG 픽셀 처리
- 새 프레임 450ms 기본값, 프레임 복사, PNG 누적 추가와 PNG·스프라이트 편집 UI
- 고정 결과 미리보기, 투명 격자·바깥 테두리·실제 crop 경계, 1×~8× 확대와 scroll/pan 소유권
- 독립 스프라이트 경계 편집, 읽기 순서·클릭 순서와 frame별 flip
- 공통 내장 몽글이 output/publish 포함, loader·기본 프로필·미수정 설정 이관
- x64 Debug·Release, loose AppX, unpackaged publish와 실제 Windows QA

## 제외 범위

- 업데이트 가능 여부 조회, 자동 다운로드·설치와 자동 업데이트 프레임워크
- `.monglepet` 편집 이력 schema 추가
- macOS Swift·SwiftUI·AppKit 소스 수정 또는 C# 번역
- Windows GitHub Release 게시와 자체 웹 다운로드 페이지 변경
- 현재 인계와 무관한 멀티펫 12단계 잔여 QA

## 열린 질문

- Windows에서 만든 최종 패키지의 macOS 실제 가져오기 확인은 macOS 작업 공간 또는 사용자의 Mac에서 수행해야 한다.
- 100%·150%·200% DPI와 혼합 DPI 검증은 연결 가능한 실제 화면 구성 범위에서 수행하고 부족한 조합은 남은 위험으로 기록한다.

## 결정사항

- Windows 마케팅 버전은 `1.3.0`, Assembly·File·MSIX·설치기 버전은 `1.3.0.13`, 태그는 `windows-v1.3.0-preview.1`이다. macOS patch 번호를 자동 재사용하지 않는다.
- 다운로드 안내 URL은 `https://mapleroom.kr/monglepet/download`로 고정하고 업데이트 조회 네트워크 요청은 추가하지 않는다.
- 이미지 편집 draft는 Windows 로컬 메모리 상태로만 유지하고 공유 패키지에는 최종 atlas 픽셀과 기존 frame 좌표·간격만 저장한다.
- `shared/Samples/ReadOnlySample.monglepet`은 테스트 fixture로 유지하며 runtime built-in은 공통 `shared/BuiltInPets/Mongle.monglepet`만 사용한다.
- 현재 Windows Codex 설치에서 확인한 PFN은 `OpenAI.Codex_2p2nqsd0c76g0`이다. 앱 선택기의 정규화 결과를 실제 QA한 뒤 built-in 전용 규칙에만 적용한다.

## 작업 순서

### 공통 계약

- [x] 1단계: 최신 main과 macOS `1.3.1 (6)` 인계·D-086~D-090·공통 built-in digest를 확인한다.
- [x] 2단계: 자유 문자열 펫 버전과 비차단 최소 앱 버전 advisory 모델·테스트를 추가한다.
- [x] 3단계: 원본 픽셀 좌표 기반 crop·flip·canvas placement·viewport geometry를 순수 C# 모델과 fixture로 고정한다.

### macOS

- [x] 4단계: 기준 구현은 `macos-v1.3.1-preview.1`, 소스 `89ceb5444478eeb2717ac29ec930f4661503a794`로 완료됐다.

### Windows

- [x] 5단계: 로컬·웹 가져오기 검토에 합쳐진 advisory와 다운로드 버튼을 구현한다.
- [x] 6단계: Windows 이미지 decoder/encoder가 crop → flip → canvas placement 순서로 atlas를 만들고 미리보기와 같은 경로를 사용하게 한다.
- [x] 7단계: PNG 다중 추가·crop·일괄 flip·고정 결과·확대/pan·독립 설정 스크롤을 구현한다.
- [x] 8단계: 스프라이트 독립 경계·선택/편집 모드·읽기/클릭 순서·frame별 flip·고정 결과를 구현한다.
- [x] 9단계: 애니메이션 편집에 프레임 복사·직접 배치·첫 프레임 비교와 450ms 새 프레임 기본값을 적용한다.
- [x] 10단계: 공통 내장 몽글이 loader·output/publish·전용 기본 프로필·미수정 프로필 이관을 구현한다.
- [ ] 11단계: Windows 앱 선택기로 Codex 식별자를 확인하고 built-in 전용 앱 규칙과 전면 전환을 검증한다.
- [x] 12단계: Windows `1.3.0 / 1.3.0.13` 버전 계약과 배포 스크립트 기대값을 갱신한다.
- [x] 13단계: x64 Debug·Release 전체 빌드·테스트와 loose AppX·unpackaged publish 콘텐츠를 확인한다.
- [ ] 14단계: 최소 높이, PNG 다수, 가로·세로 긴 시트, 1×/확대 scroll ownership, DPI·키보드·Narrator·큰 이미지 반복 drag를 실제 앱에서 확인한다.

### 플랫폼 동등성

- [ ] 15단계: Windows 내보내기 패키지를 macOS에서 가져와 atlas 픽셀·frame 순서·duration·표시 크기를 교차 확인한다.
- [ ] 16단계: 취소 원자성, packaged/unpackaged 업데이트 보존과 공통 built-in 사용자 시나리오를 확인한다.
- [ ] 17단계: `AGENTS/project/TESTING.md`, `AGENTS/project/PLATFORM_PARITY.md`, Windows 문서와 이 계획의 완료 결과를 갱신한다.

## 검증 방법

- geometry·RGBA 픽셀 변환과 viewport 정책 단위 테스트
- Packages·PetLibrary·Settings 관련 대상 테스트
- `dotnet restore apps/windows/MonglePet.slnx`
- x64 Debug·Release 전체 솔루션 빌드와 테스트
- packaged loose AppX 파일·등록 실행, unpackaged self-contained publish·설치 후보 실행
- `git diff --check`
- 실제 Windows UI·DPI·접근성·성능 QA와 Windows→macOS 교차 왕복

## 진행 로그

- 2026-08-24: `165168a`에서 최신 main `9edc6de`까지 사용자 변경 없이 fast-forward했다. 인계 문서 전체와 현재 Windows 코드를 대조해 웹 최소 버전 선차단, 120ms·균등 격자 편집기, 테스트 샘플 built-in과 중립 기본 프로필 결합을 주요 차이로 확인했다.
- 2026-08-24: 공통 built-in의 10개 PNG digest, 10개 모션·36프레임과 메타데이터가 인계 계약과 일치함을 확인했다.
- 2026-08-24: 로컬·웹 최소 앱 버전을 비차단 advisory로 통합하고 자유 문자열 콘텐츠 버전 fixture를 추가했다. PNG·스프라이트 편집기는 원본당 decode·알파 경계 cache, crop·flip·배경 제거·공통 캔버스·atlas 순수 픽셀 경로, 1×~8× viewport와 포인터 드래그 중 레이아웃 전용 갱신을 사용한다.
- 2026-08-24: 스프라이트 자동/균등/독립 경계, 읽기/클릭 순서, 키보드·Narrator 선택, frame별 flip과 선택적 단색 배경 제거를 연결했다. 프레임 복사는 독립 ID와 이미지·crop·flip·450ms/기존 간격·배치를 보존한다.
- 2026-08-24: 공통 built-in을 Debug·Release loose output과 unpackaged publish에 포함했고 세 위치의 13개 파일 tree SHA-256 `08E8E09643B0CEE5FED8D8246729EBB5CF00E18B72871EA6FCD7BE26DB76DB59`가 일치했다. 실제 Codex PFN `OpenAI.Codex_2p2nqsd0c76g0`를 정규화한 built-in 전용 규칙을 적용했다.
- 2026-08-24: `1.2.0.13` 개발 패키지를 `1.3.0.13` loose 패키지로 업데이트 등록해 LocalState 22개 파일을 보존했다. 첫 실행에서는 기존 미수정 built-in 중립 프로필만 새 기본 루틴·규칙으로 이관되고 설치 펫 프로필과 라이브러리 파일은 유지됐다.
- 2026-08-24: 최종 Debug·Release 전체 빌드와 각 Activity 27개·Core 38개·Packages 22개·PetLibrary 87개·Settings 72개·Shell 20개, 총 266개 테스트를 통과했다. 격리 환경 NuGet audit endpoint의 `NU1900` 1개 외 빌드 오류는 없다.
- 2026-08-24: 최종 unpackaged publish와 loose AppX 콘텐츠를 재검증하고 `1.3.0.13` 미서명 설치기 후보를 기존 `1.2.0.13` 위에 설치했다. unpackaged 데이터 11개 파일과 라이브러리 digest를 보존했고 실행 응답·schema-v11·built-in 전용 프로필을 확인했다. 실행 중 후보 위 최종 후보 재설치도 전용 종료와 데이터 보존을 통과했다. 최종 설치기 SHA-256은 `46069D07F7C4BD5A54E60CFA491B00333E8313A59E9EC2ADEFEAB907A48C0EF3`다.
- 2026-08-25: 실제 설치본에서 `애니메이션 추가…`를 누르면 `PetAnimationEditorControl` 생성 중 MainPage 범위의 `SettingsSubcardStyle`을 찾지 못해 `XamlParseException (0x802B000A)`으로 종료되는 회귀를 Application Error·WER 로그로 확인했다. 편집기들이 사용하는 카드·설명 스타일을 Application 공용 리소스로 이동하고 초기 값 이벤트 준비 경계와 편집기 열기 오류 경계를 추가했다. Debug·Release 빌드와 각 266개 테스트를 다시 통과했으며, 교체 설치기 SHA-256은 `5AF4DA39E2B62FE3DA8DF201A5780A2E11D50C4262CEDD51B986FF0372C526C6`이다. 교체 설치본의 `펫 보관함 → 애니메이션 추가…`를 UI Automation으로 호출해 프로세스 응답, 대화상자 제목과 공통 캔버스·PNG·스프라이트 진입 요소를 확인했다.
- 2026-08-25: 위 대화상자에서 `개별 PNG 추가…` 파일을 선택한 뒤 같은 `XamlRoot`에 두 번째 `ContentDialog`를 여는 경로가 WinRT `0x80000019`와 `Microsoft.UI.Xaml.dll 0xc000027b` 종료를 일으키는 것을 WER로 확인했다. 애니메이션·PNG·스프라이트 단계를 Mica 기반 독립 owned WinUI 편집 창으로 바꾸고, macOS와 같은 헤더·스크롤 본문·고정 푸터 및 `왼쪽 원본 / 오른쪽 상단 고정 결과 / 오른쪽 하단 독립 설정 스크롤` 정보 구조로 재배치했다. 실제 Release loose AppX에서 `애니메이션 추가 → 프레임 선택 → 개별 PNG 추가 → 파일 선택 → PNG 자르기 → 프레임 반환 → 취소`를 완료해 프로세스 생존, 프레임 추가와 취소 시 사용자 데이터 불변을 확인했다. 이미지 geometry 대상 21개와 Debug·Release 각 266개 전체 테스트, 경고·오류 없는 두 구성 빌드가 통과했다.
- 2026-08-25: PNG 편집기에서 `PNG 더 추가…` 뒤 새 항목을 선택하면 `RO_E_CLOSED (0x80000013)`로 종료되는 회귀를 실제 WER 두 건에서 확인했다. `SoftwareBitmapSource`를 목록 썸네일과 결과 이미지가 공유하는 닫힘 수명을 제거하기 위해 독립 `WriteableBitmap` 픽셀 소스로 전환하고, 추가된 항목 선택·포커스·미리보기 render를 직렬화했으며 `ItemClick`과 `SelectionChanged`의 중복 render를 합쳤다. 실제 Release loose AppX에서 두 PNG를 추가한 뒤 selection pattern 12회와 실제 포인터 클릭 8회로 왕복해 프로세스 응답과 신규 WER 0건을 확인했다. 애니메이션 이름 입력은 360×59 DIP 전체 경계의 한 줄 필드로 축소했다. Debug·Release 각 266개 전체 테스트와 경고·오류 없는 빌드가 통과했다.
- 2026-08-25: 스프라이트 `범위 편집`의 동적 `Button` 경계가 기본 최소 크기·내부 포인터 처리에 종속되어 이동과 8방향 크기 조절을 시작하지 못하는 회귀를 수정했다. 프레임 전체를 그리는 접근 가능한 `ContentControl` 템플릿, 캔버스 좌표 기반 적중·포인터 캡처, 현재 프레임 우선 적중과 z-order를 적용했다. Release loose AppX에서 공통 1050×150 atlas를 열어 중앙 드래그가 `X 9→22`, `141×141` 보존으로 이동하고 오른쪽 아래 드래그가 위치 `22,0`을 유지한 채 `151×149`로 바뀌는 것을 실제 상대 마우스 입력으로 확인했다. 편집을 취소해 사용자 데이터가 바뀌지 않았고 이미지 geometry 21개와 Debug·Release 각 266개 전체 테스트, 경고·오류 없는 빌드가 통과했다.
- 2026-08-25: 커밋 `2715cbb799687cbf26084c607848cc052fea666c`에서 최종 미서명 x64 설치기를 생성했다. `MonglePet-Windows-1.3.0.13-x64-Setup.exe`는 64,866,058 bytes, SHA-256 `5F8A14314447F70C74704793BC5ED0EA8744DF0276303470D366500D4777B808`이다. 실제 업그레이드 설치에서 사용자 데이터 22개 파일의 inventory digest를 보존하고 설치본 응답·Application 오류 0건을 확인했다. `windows-v1.3.0-preview.1` GitHub Pre-release 게시 후 두 자산을 다시 내려받아 크기·digest·체크섬 파일의 일치를 확인했다.

## 완료 결과

- 진행 중

## 남은 위험 / 후속 작업

- 실제 macOS 교차 가져오기는 Windows 환경 단독으로 완료할 수 없다.
- 동일 PC에 개발 MSIX와 공개 EXE가 함께 등록된 custom scheme 선택 충돌은 별도 깨끗한 사용자 환경 QA가 필요하다.
- 실제 코드 서명과 Microsoft Store 배포는 이번 Preview 범위가 아니다.
