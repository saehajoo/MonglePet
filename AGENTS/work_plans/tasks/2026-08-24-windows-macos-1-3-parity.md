# Windows macOS 1.4 행동 중심·이미지 편집기·내장 몽글이 동등성

## 상태

- 상태: in_progress
- 생성일: 2026-08-24
- 마지막 갱신: 2026-08-29

## 목표

- macOS `1.3.1 (6)`에서 확정한 펫 콘텐츠 버전, 최소 앱 버전 권장 정책과 PNG·스프라이트 제작 결과를 Windows 네이티브 앱에서 같은 사용자 결과로 제공한다.
- `shared/BuiltInPets/Mongle.monglepet`을 Windows 내장 몽글이의 단일 공통 기준본으로 사용하고 기존 사용자 설정을 무손실 이관한다.
- 공개된 Windows `1.2.0.13`을 덮어쓰지 않는 Windows `1.3.0` Preview 후보를 검증한다.
- macOS `1.4.0 (8)`에서 확정한 안정적 행동 ID·표시 이름, 자동/직접/랜덤 선택, 종류 우선순위와 독립 이동 설정을 Windows 네이티브 런타임·WinUI에 반영한다.
- schema-v11 사용자 데이터와 활성 펫·보관함을 보존하면서 Windows 설정을 schema-v14 의미까지 순차 승격하고 권장 프로필 v10을 왕복한다.
- 공통 built-in `1.0.3`의 13개 모션·53프레임과 최신 기본 프로필을 output·publish·업데이트 이관에 적용한다.

## 범위

- 펫 콘텐츠 `version` 자유 문자열 보존과 앱 호환 버전 전용 `MAJOR.MINOR.PATCH` 검증
- 로컬·웹 최소 앱 버전 비차단 권장 안내와 운영 다운로드 페이지 버튼
- crop → 좌우·상하 flip → 공통 캔버스 배치 → atlas PNG 픽셀 처리
- 새 프레임 450ms 기본값, 프레임 복사, PNG 누적 추가와 PNG·스프라이트 편집 UI
- 고정 결과 미리보기, 투명 격자·바깥 테두리·실제 crop 경계, 1×~8× 확대와 scroll/pan 소유권
- 독립 스프라이트 경계 편집, 읽기 순서·클릭 순서와 frame별 flip
- 공통 내장 몽글이 output/publish 포함, loader·기본 프로필·미수정 설정 이관
- x64 Debug·Release, loose AppX, unpackaged publish와 실제 Windows QA
- schema-v12 행동 참조 승격, schema-v13 랜덤 행동·머무르기, schema-v14 모드별 독립 이동 설정
- 권장 프로필 v10 전체 휴대 옵션·표시 설정과 v1~v9 호환
- 행동 중심 자동 동작·표시 및 이동 UI, 애니메이션 행동 연결·전체 복제·현재 펫 프레임 추가
- 마우스 도망가기 평상시 자유 이동 목표 수명 회귀 수정과 이동/규칙 우선순위

## 제외 범위

- 업데이트 가능 여부 조회, 자동 다운로드·설치와 자동 업데이트 프레임워크
- `.monglepet` 편집 이력 schema 추가
- macOS Swift·SwiftUI·AppKit 소스 수정 또는 C# 번역
- Windows GitHub Release 게시와 자체 웹 다운로드 페이지 변경
- 현재 인계와 무관한 멀티펫 12단계 잔여 QA
- GitHub Release 게시와 기존 `windows-v1.3.0-preview.1` 태그·자산 변경

## 열린 질문

- Windows에서 만든 최종 패키지의 macOS 실제 가져오기 확인은 macOS 작업 공간 또는 사용자의 Mac에서 수행해야 한다.
- 100%·150%·200% DPI와 혼합 DPI 검증은 연결 가능한 실제 화면 구성 범위에서 수행하고 부족한 조합은 남은 위험으로 기록한다.

## 결정사항

- 기존 공개 Windows 버전은 `1.3.0.13`, 태그는 `windows-v1.3.0-preview.1`로 보존한다. 이번 통합 후보는 마케팅 `1.4.0`, Assembly·File·MSIX·설치기 `1.4.0.13`, 태그 후보 `windows-v1.4.0-preview.1`로 준비하되 실제 설치·업데이트·제거·데이터 보존 QA 전에는 게시하지 않는다.
- 다운로드 안내 URL은 `https://mapleroom.kr/monglepet/download`로 고정하고 업데이트 조회 네트워크 요청은 추가하지 않는다.
- 이미지 편집 draft는 Windows 로컬 메모리 상태로만 유지하고 공유 패키지에는 최종 atlas 픽셀과 기존 frame 좌표·간격만 저장한다.
- `shared/Samples/ReadOnlySample.monglepet`은 테스트 fixture로 유지하며 runtime built-in은 공통 `shared/BuiltInPets/Mongle.monglepet`만 사용한다.
- 종전 1.3 기본값에 사용했던 Codex PFN 기본 규칙은 built-in `1.0.3` 기준에서 제거한다. 사용자가 직접 만든 `pfn:`·`exe:` 규칙은 이관·실행 회귀에서 보존한다.

## 1.4 시작 차이 분석

- 현재 Windows 로컬 저장은 schema-v11이며 행동 목록에 변경 가능한 표시 이름이 없고 이동·쓰다듬기는 애니메이션 ID를 직접 참조한다.
- 현재 `BehaviorMode`는 automatic/manual만 지원하고 랜덤 선택·shuffle bag과 규칙 종류 우선순위가 없다.
- 현재 이동 설정은 속도·정지 반경·머무르기·전면 창 선호를 세 방식과 도망가기 평상시 자유 이동이 공유한다.
- 현재 권장 프로필 codec은 v7이며 독립 이동·랜덤 선택·휴대 표시 설정을 읽고 쓰지 못한다.
- 공통 built-in은 pull로 `1.0.3`으로 바뀌었지만 Windows 기본 프로필·이관 테스트와 배포 계약은 종전 1.0.1 기준이다.
- 펫 보관함과 애니메이션 편집기는 1.3 이미지 작업은 갖췄지만 모든 펫 사본, 단일 복제 진입점과 저장 시 행동 연결 경계가 부족하다.

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

### Windows 1.4 행동 중심 확장

- [x] 18단계: C# Domain·mapper·migrator를 schema-v12 행동 참조와 표시 이름으로 승격하고 공통 v11→v12 fixture를 검증한다.
- [x] 19단계: schema-v13 랜덤 행동·랜덤 머무르기와 schema-v14 독립 이동 설정을 구현하고 v1~v14 순차 이관·항목 복구·확장 필드 보존을 검증한다.
- [x] 20단계: 권장 프로필 v10 codec·v1~v9 승격·휴대 표시 적용/보존과 전체 공유 요약·내보내기·가져오기를 구현한다.
- [x] 21단계: 기본·자동 규칙·직접·랜덤·이동·쓰다듬기 playback 우선순위와 shuffle bag을 구현한다.
- [x] 22단계: 마우스 도망가기 평상시 자유 이동 목표 수명 회귀를 수정하고 독립 수치·고정/랜덤 머무르기를 runtime에 연결한다.
- [x] 23단계: WinUI의 행동·자동 동작·표시 및 이동을 macOS 정보 구조와 같은 사용자 결과로 재구성한다.
- [x] 24단계: 모든 펫 사본, 애니메이션 행 전체 선택, 단일 복제·행동 연결·현재 펫 프레임 추가의 저장/취소 원자성을 구현한다.
- [x] 25단계: 공통 built-in `1.0.3`·13개 모션·53프레임·권장 프로필 v10과 1.0.1/1.0.2 미수정 이관을 반영한다.
- [x] 26단계: Windows `1.4.0.13` 계약, Debug·Release 전체 테스트/빌드, loose AppX와 unpackaged publish를 검증한다.
- [ ] 27단계: packaged/unpackaged 데이터 보존 업데이트, 실제 WinUI·DPI·접근성·이동 5분 성능 QA를 완료한다.

### 1.4 플랫폼 동등성

- [ ] 28단계: macOS v10 권장 프로필의 Windows 왕복과 Windows 내보내기의 macOS 재가져오기를 확인한다.
- [x] 29단계: 실제 QA가 끝난 항목만 플랫폼 현황·테스트·Windows 문서에 반영하고 릴리스 후보 결과를 보고한다.

### Windows 펫 제작기 UX 후속 보정

- [x] 30단계: 스프라이트 경계의 이동·크기 조절 입력을 분리하고 드래그 좌표가 흔들리지 않도록 고정한다.
- [x] 31단계: 스프라이트 읽기 순서를 경계 생성 시점의 안정 순서로 유지하고 좁은 설정 열의 뒤집기 버튼 잘림을 제거한다.
- [x] 32단계: Windows 새 펫·편집 가능한 사본을 선택 인스턴스 교체가 아닌 독립 활성 인스턴스 추가로 바꾼다.
- [x] 33단계: Windows 신규·수정 펫 버전 입력을 `MAJOR.MINOR.PATCH`로 제한하되 기존 자유 문자열 패키지 로드는 보존한다.
- [x] 34단계: 애니메이션 배율을 실제 프레임 콘텐츠 크기로 적용하고 캔버스 밖 부분 배치·안전한 clip 합성을 지원한다.
- [x] 35단계: 모든 제작기 미리보기의 투명 격자와 버튼 계층을 테마 대응 공통 리소스로 정돈한다.
- [x] 36단계: Windows Debug 빌드와 정적 검사를 수행하고, 사용자가 직접 확인할 QA 목록과 macOS 후속 변경 인계를 작성한다. 사용자 요청에 따라 자동 테스트는 실행하지 않는다.
- [x] 37단계: 작은 스프라이트 경계에서 8개 크기 조절점의 입력 영역이 중앙 이동 영역을 침범하지 않게 조절하고, 모달 고정 좌표와 취소 복원 경계로 간헐적 이동·축소 튐을 막는다.
- [x] 38단계: 다크·라이트 테마의 버튼·라디오·슬라이더·토글 대비를 공통 리소스로 통일하고 활성 펫 작업 버튼의 계층과 클릭 통과 상태 문구를 명확히 한다.

## 검증 방법

- geometry·RGBA 픽셀 변환과 viewport 정책 단위 테스트
- Packages·PetLibrary·Settings 관련 대상 테스트
- `dotnet restore apps/windows/MonglePet.slnx`
- x64 Debug·Release 전체 솔루션 빌드와 테스트
- packaged loose AppX 파일·등록 실행, unpackaged self-contained publish·설치 후보 실행
- `git diff --check`
- 실제 Windows UI·DPI·접근성·성능 QA와 Windows→macOS 교차 왕복

### 2026-08-29 후속 사용자 QA

- 스프라이트 `범위 편집`에서 중앙 이동과 8개 조절점을 각각 끌어 시작 순간 위치가 튀지 않는지 확인한다.
- 경계를 옮겨도 읽기 순서가 즉시 바뀌지 않고 `현재 위치로 읽기 순서 적용` 뒤에만 바뀌는지 확인한다.
- 새 펫과 펫 사본을 만든 뒤 기존 펫이 활성 목록·화면에 남고, 사본의 행동·overlay를 바꿔도 원본이 바뀌지 않는지 재실행까지 확인한다.
- `1.0.0`은 생성·수정 저장되고 `v1.0`, `01.0.0`, `1.0.0-beta`는 필드 오류로 남는지, 자유 문자열 외부 패키지는 계속 가져와지는지 확인한다.
- 애니메이션 `펫 크기` 25%·100%·400%에서 캔버스는 고정되고 펫만 바뀌는지, 일부를 캔버스 밖에 둔 뒤 저장·재로드 결과가 같은지 확인한다.
- 밝은/어두운 테마와 좁은 창에서 격자 대비, 상하 뒤집기 버튼, 키보드 초점 표시가 읽을 수 있는지 확인한다.
- 클릭 통과를 켠 뒤 위치 고정·자유 이동·마우스 따라가기·마우스 도망가기 각각에서 펫이 움직이는 동안에도 뒤쪽 앱의 버튼·텍스트 입력이 즉시 클릭되고 대기 커서가 나타나지 않는지 확인한다.

## 진행 로그

- 2026-08-29: ToggleSwitch가 Dark에서 시스템 강조색을 유지하는 실제 사용자 피드백에 따라 공식 WinUI 템플릿의 modern fill/stroke/knob와 legacy curtain/track 전체 상태 키를 확인했다. Normal뿐 아니라 pointer over·pressed·disabled를 템플릿이 요구하는 Brush/Color 타입으로 모두 정의했다. Dark는 slider 활성 값·toggle 켜짐을 `#D0D0D0`, 비활성 track·꺼짐을 `#858585`로 맞췄다. Light는 활성 값·thumb·radio 선택·toggle 켜짐을 더 어두운 `#5F5F5F`, 비활성 track·toggle 꺼짐을 더 밝은 `#D0D0D0`로 반전하고 knob 대비도 함께 조정했다. Debug 앱 빌드와 Release publish는 경고·오류 0개로 통과했다. Computer Use는 작업공간 HWND의 소유 경로를 설치본으로 잘못 매핑해 캡처를 거부했으므로 실제 두 테마 시각 확인은 사용자 QA로 남겼다.
- 2026-08-29: 저장 JSON은 선택 펫의 `clickThrough: true`를 보존하고 자식 HWND도 `WS_EX_TRANSPARENT`였지만, 실제 표시된 최상위 펫 HWND는 `DesktopChildSiteBridge.Show()` 뒤 `WS_EX_TRANSPARENT`가 제거되고 no-redirection이 복구된 상태임을 네이티브 window probe로 확인했다. 실행 중 부모에 누락 비트만 적용하자 같은 좌표의 `WindowFromPoint`가 MonglePet HWND에서 뒤쪽 Explorer HWND로 즉시 바뀌고 2초 뒤에도 유지됐다. `Show()` 완료와 부모 이동·크기·z-order 변경 뒤 부모 `WS_EX_LAYERED | WS_EX_TRANSPARENT`와 현재 bridge 자식 HWND를 함께 재검증하고, 핸들이나 스타일이 실제로 달라진 경우에만 frame을 갱신한다. 전체 Debug 앱 빌드와 Release publish는 경고·오류 0개로 통과했다. 최신 Release에서 펫 바로 뒤 다른 프로세스의 임시 버튼을 두고 중앙을 물리 클릭한 검증은 Click 이벤트 1회를 수신해 위치 고정의 실제 교차 프로세스 입력 통과를 확인했다. 세 자동 이동 모드의 이동 중 반복 클릭은 사용자 QA로 남겼다.
- 2026-08-29: 사용자 시각 기준에 따라 slider 값 구간·thumb, toggle on 배경·stroke, radio checked 배경·stroke를 다크·라이트 모두 `#D0D0D0` 중성 밝은 회색으로 통일했다. pointer over는 `#E0E0E0`, pressed는 `#B8B8B8`을 사용하고 스위치 knob와 라디오 중앙점은 `#303030`으로 분리해 활성 상태를 흰색보다 살짝 어둡게 보이면서 형태로도 구분한다. 실제 화면과 자동 테스트는 사용자 요청에 따라 실행하지 않았다.
- 2026-08-29: 클릭 통과를 설정 저장이 아닌 실제 교차 프로세스 입력 기준으로 다시 검증했다. 펫이 덮지 않은 활성 펫 카드는 선택되지만 같은 카드의 펫 불투명 픽셀 아래는 선택되지 않는 회귀를 재현했다. `HTTRANSPARENT`는 같은 스레드 아래 창에만 전달되고 최상위 `WS_EX_TRANSPARENT` 단독 사용은 다른 프로세스 창의 입력 통과 계약이 아니라는 DWM 경계를 확인했다. 클릭 통과 중에는 부모 오버레이 HWND를 `WS_EX_LAYERED | WS_EX_TRANSPARENT`로 전환하고 `DesktopChildSiteBridge`의 실제 WS_CHILD HWND에도 `WS_EX_TRANSPARENT`를 적용한다. 클릭 가능 모드에서는 부모를 `WS_EX_NOREDIRECTIONBITMAP` Composition target으로 복구해 기존 알파 기반 `HTCAPTION` 드래그를 유지한다. Debug 빌드와 Release unpackaged publish는 경고·오류 0개로 통과했다. 자식 HWND 수정 뒤 최종 실제 클릭 반복은 사용자가 Esc로 화면 제어를 중지해 사용자 QA로 남겼다. 설치기 SHA-256은 `4B82BE2FD2E0D12E80B44CD09C9E352B1B2D6B5544A04E47CA099F91D8D13F24`다.
- 2026-08-29: 실제 다크 모드 설치본에서 메인 설정의 일반 버튼, 활성 펫 작업, 이동 라디오, 슬라이더와 토글이 WinUI 기본의 약한 fill·stroke를 사용해 카드와 상태 구분이 어려운 것을 확인했다. Default(Dark)·Light별 버튼 normal/hover/pressed/disabled, 파란 slider value·thumb, radio checked, toggle on과 선명한 off stroke를 Application 공통 리소스로 정의하고 모든 편집기와 동적 컨트롤까지 같은 최소 높이·경계를 사용하게 했다. 활성 펫의 전체 작업은 동일 폭 3열, 인스턴스 작업은 2×2로 분리하고 제거는 경고색으로 구분했다. 실제 클릭 통과 토글은 선택 인스턴스 `true→false→true` 왕복에서 저장 JSON과 위치 고정 안내가 즉시 일치해 저장·선택 경계가 정상임을 확인했고, `켬/끔` 대신 `클릭 통과 중/펫 클릭 가능`으로 결과를 명시했다. 오래된 `일반 탭` 안내도 같은 화면 상단을 가리키도록 수정했다. 최종 설치본에서 선택 라디오의 파란 테두리·중앙점, 슬라이더의 파란 값 구간, 활성 펫 버튼 경계와 제거 경고색을 실제 확인했다. Debug 빌드는 경고·오류 0개였고 사용자 요청에 따라 자동 테스트는 생략했다. 새 `1.4.0.13` 설치기 SHA-256은 `23802B890C5EA62EA7DF0FD7927F1F6832794E84F73CFF37C9D70A9C15FEC85B`이며 설치본 DLL이 Release unpackaged publish DLL과 일치하고 앱이 정상 응답한다.
- 2026-08-29: 1536×1024 시트를 9×9로 나눈 실제 편집 화면에서 각 경계가 약 55×37 DIP인데 8개 크기 조절점의 입력 영역이 각각 14×14 DIP라 중앙 이동 영역이 세로 약 9 DIP만 남는 것을 확인했다. 이동 의도의 누름이 상단·좌우 조절로 판정되면 Y가 0으로 붙거나 너비·높이가 1px까지 접혀 최상단·화면 밖으로 튄 것처럼 보였다. 조절점은 표시 경계 크기의 20%·6~10 DIP로 제한하고 18 DIP 미만 경계에서는 숫자 입력만 사용하도록 숨겼다. 드래그 delta는 편집 모달 루트 좌표로 고정하고 왼쪽 버튼이 실제로 눌린 유효 좌표만 반영하며, cancel·capture lost는 시작 경계로 되돌린다. Windows 앱 Debug 빌드는 경고·오류 0개로 통과했고 자동 테스트는 사용자 요청에 따라 생략했다. 새 `1.4.0.13` 설치기 SHA-256은 `89A50055294A26D1A7593383DB0810AF5EDFBEC9299C2C5C4D940903FC044575`이며 설치본 DLL이 publish DLL과 일치하고 앱이 정상 응답함을 확인했다.
- 2026-08-29: 실제 사용자 QA에서 스프라이트 범위 이동이 간헐적으로 중앙·아래쪽으로 튀고 `균등 경계 다시 만들기`가 잘리는 후속 회귀를 확인했다. 이동 delta를 스크롤 가능한 시트 좌표 대신 고정 ScrollViewer 뷰포트 좌표로 계산하고 드래그 frame·배율·pointer ID를 시작 시점에 고정했다. 마우스 상호작용의 자동 focus/bring-into-view를 막고 drag 중 스크롤 소유권을 잠그며, capture lost·cancel에서 이전 drag 상태를 즉시 폐기한다. 경계 재생성 버튼은 오른쪽 고정 열에서 한 줄씩 전체 너비를 쓰도록 세로 배치했다. Windows 앱 프로젝트 Debug 빌드는 경고·오류 0개로 통과했으며 실제 반복 drag 확인은 사용자 QA로 남겼다.
- 2026-08-29: 스프라이트 범위 편집을 명시적 이동 영역과 8개 크기 조절점으로 나누고 drag 시작 배율을 고정했다. 읽기 순서는 사용자의 명시적 적용 시점에만 갱신하고 오른쪽 설정 작업은 2열 버튼으로 재배치했다. 새 펫과 편집 가능한 사본은 기존 선택 인스턴스를 교체하지 않고 독립 인스턴스·프로필로 추가한다. Windows 제작 UI는 D-104의 숫자형 `MAJOR.MINOR.PATCH`를 검증하되 외부 패키지의 자유 문자열 로드는 보존한다. 애니메이션 크기는 실제 content 배치를 25~400%로 조절하고 음수·캔버스 밖 좌표를 clip 합성하며, 제작기 격자와 버튼 스타일을 저대비 테마 공통 리소스로 정돈했다. 전체 Debug 솔루션 빌드는 경고·오류 0개로 통과했다. 사용자 요청에 따라 자동 테스트와 실제 UI QA는 실행하지 않았고 macOS 후속 항목은 `MACOS_PET_EDITOR_FOLLOWUP.md`로 분리했다.
- 2026-08-29: 모든 이동 방식의 클릭 통과가 실제 최상위 overlay와 composition bridge child에 함께 유지되도록 창 표시·이동·크기·z-order 뒤 스타일을 저비용 재검증한다. 물리 포인터로 고정 펫 뒤의 별도 프로세스 버튼이 한 번 클릭되는 것을 확인했다. 다크·라이트 테마의 slider 활성 구간, radio 선택과 모든 toggle 상태를 같은 명암 체계로 맞췄고 Debug 빌드와 Release publish가 경고·오류 없이 통과했다. 후속 릴리스는 D-105에 따라 마케팅 `1.4.0`, 파일·MSIX·설치기 `1.4.0.14`, 태그 `windows-v1.4.0-preview.2`로 준비한다. 사용자 요청에 따라 전체 자동 테스트는 다시 실행하지 않는다.

- 2026-08-27: 깨끗한 `main`을 `a1b528e`에서 `71a1ea2`로 fast-forward하고 macOS `1.4.0 (8)` 행동 중심 인계·schema-v14·권장 프로필 v10·built-in `1.0.3`을 확인했다. 현재 Windows는 schema-v11·권장 프로필 v7·공유 이동 수치·애니메이션 직접 참조이므로 portable 저장·Domain부터 순차 승격하기로 했다.
- 2026-08-27: Windows Domain·DTO·mapper·migrator를 schema-v14까지 승격하고 안정 행동 ID·표시 이름, 랜덤 shuffle bag, 자동 규칙 종류 우선순위, 1~86,400초 입력 없음 규칙, 네 독립 이동 설정과 권장 프로필 v10 왕복을 구현했다. 공통 built-in `1.0.3`의 13개 모션·53프레임과 PNG digest, schema-v11 사용자 설정의 인스턴스·프로필·확장 필드 보존을 자동 테스트했다.
- 2026-08-27: WinUI에 10~200% 크기와 빠른 선택·화면 복구 안내, 문제 해결 하위 안전 모드, 자동/직접/랜덤 행동, 자동 규칙 종류 순서와 전용 입력 없음 카드, 모든 펫 사본·전체 행 애니메이션 선택·단일 복제·저장 시 행동 연결·현재 펫 프레임 추가·flip·1×~8× 미리보기를 연결했다. 실제 Release loose AppX에서 해당 정보 구조와 취소 시 무변경을 확인했다.
- 2026-08-27: Debug·Release 빌드는 경고·오류 없이 통과했고 각 구성에서 Activity 27개·Core 46개·Packages 22개·PetLibrary 88개·Settings 76개·Shell 20개, 총 279개 테스트가 통과했다. loose AppX와 unpackaged publish의 공통 built-in은 16개 파일과 tree SHA-256 `0463D7B6897E8D14C3BA053F953D69DC49FB31930DB1D03D3797B9EC37B95503`로 기준본과 일치했다.
- 2026-08-27: 개발 package `1.3.0.13→1.4.0.13` 등록 업데이트에서 LocalState 22개 파일 digest를 보존했고 실행 뒤 schema-v14·3개 instance·4개 profile·라이브러리 21개를 확인했다. unpackaged publish도 기존 schema-v11의 3개 instance·4개 profile·라이브러리 21개를 schema-v14로 무손실 이관해 정상 응답했다.
- 2026-08-27: 설정창을 닫고 마우스 도망가기·자유 이동·고정 3펫을 함께 실행한 깨끗한 Release 5분 측정은 평균 CPU 0.680%, private memory 126.51→126.51MiB·최대 129.62MiB, 증가 0.00MiB와 무응답 0회로 기준을 통과했다. 설정창과 펫 보관함 미리보기까지 연 별도 5분 표본은 CPU 5.915%, private memory 189.40→226.91MiB였고 창을 닫은 뒤 추가 5분 동안 227.44→227.28MiB로 안정돼 상주 runtime 누수와 구분했다.
- 2026-08-27: 활성 펫에서 내장 몽글이를 선택할 때 실제 WER `RO_E_CLOSED (0x80000013)` 종료를 확인했다. 현재 펫 애니메이션 미리보기의 프레임별 `SoftwareBitmapSource` 수명을 atlas decode cache·순수 crop·독립 `WriteableBitmap`과 generation 취소 경계로 교체했다. 자동 이동 중 실제 Win32 overlay 원점과 소수점 이동 누산 원점이 달라지면 과거 좌표로 돌아가던 경로도 실제 픽셀 원점이 다를 때만 재동기화하도록 수정했다. 수정된 Release loose AppX의 설치 펫↔내장 몽글이 왕복, 15초 응답 표본과 신규 Application 오류 0건을 확인했고 Debug·Release 각 281개 테스트가 통과했다.
- 2026-08-27: 마우스 도망가기의 평상시 자유 이동이 매 60Hz tick마다 목표를 새로 뽑고 이동 행동을 해제해 좌표·방향이 떨리던 원인을 확인했다. 도망 상태에서 평상시 상태로 바뀌는 순간에만 목표를 한 번 초기화하고 이후 자유 이동 목표와 dwell을 유지하며, 실제 도망 목표도 24px 미만 포인터 변화에는 유지한다. 표시 및 이동 입력은 350ms 저장 병합과 편집 중 부분 갱신을 사용하고 숨겨진 활성 펫 목록의 runtime 반복 갱신을 건너뛴다. 펫 HWND는 기존 `WS_EX_TOPMOST | WS_EX_NOACTIVATE`를 유지하고 투명 frame 픽셀만 입력을 통과시킨다. Debug·Release 경고·오류 없는 빌드와 각 283개 테스트를 통과했다.
- 2026-08-27: 최종 packaged Release 30초 응답 표본은 전체 시스템 환산 평균 CPU 약 1.12%, private memory 136.9~143.6MiB, 무응답·새 Application Error·WER 0회였다. 여러 topmost overlay 때문에 자동 UI 도구가 설정 WinUI HWND를 안정적으로 고르지 못해 이동 숫자 입력의 실제 포커스 유지와 평상시 자유 이동의 시각 판정은 사용자 확인으로 남겼다.
- 2026-08-27: 펫 보관함의 `펫 사본 새로 만들기`가 새 설치로 전환하면서 현재 프로필을 중립 기본값으로 교체해 행동 모드·루틴·자동 규칙·이동·쓰다듬기·말풍선을 잃는 회귀를 수정했다. 새 패키지 키와 새 프로필 ID를 사용하되 현재 프로필 전체와 인스턴스 overlay를 한 번의 원자적 설정 저장으로 복사하며, 중립 기본 행동의 내부 ID는 사용자에게 보이지 않도록 표시 이름을 `기본`으로 고정했다. 말풍선 대사 요약과 행동 실행 상태도 안정 ID 대신 현재 행동 표시 이름을 사용하고 누락 참조는 사용자용 안내로 표시한다. 행동 모드 선택은 macOS 정보 구조처럼 `행동 루틴`에서 `자동 규칙` 화면으로 옮기고 자동 모드에서만 우선순위·입력 없음·앱 규칙을 표시한다. 행동 저장 중 숨겨진 펫 보관함과 이미지 미리보기를 다시 만들지 않도록 갱신 범위를 줄였다. Settings 대상 77개와 Debug·Release 전체 각 284개 테스트, 경고·오류 없는 두 구성 빌드를 통과했다. 최신 x64 Release loose AppX에서 랜덤 선택 카드가 `자동 규칙`에 표시되고 `행동 루틴`에는 모드 선택이 없는 것, 읽기 전용 펫의 사본 안내에 행동·자동 동작·이동·쓰다듬기·말풍선 복사 범위가 표시되며 취소 시 보관함이 바뀌지 않는 것을 확인했다. 실제 사본 생성 후 재실행 데이터 보존은 사용자 보관함을 변경하므로 최종 사용자 QA로 남겼다.
- 2026-08-27: 1초 activity 갱신이 5초 랜덤 행동 경계보다 먼저 완료 cursor를 소비하면 같은 요청이 동등 요청으로 무시되어 timer가 멈추는 경합을 수정했다. 완료된 단일 랜덤 행동도 새 cursor로 재시작하고, 모든 갱신 경로에서 유효한 선택만 shuffle bag으로 이어간다. 프레임 재생은 callback당 한 프레임 이동 대신 단조 경과 시간으로 현재 프레임을 seek하며 atlas 전환 중에는 요청 atlas 준비까지 표시 시간축을 기다리고 최근 16개 atlas를 제한 cache한다. 이동 중 랜덤을 뒤에서 계속 진행하는 방식은 이동 종료 시 중간 프레임이 갑자기 보이는 실제 QA 문제가 있어 채택하지 않았다. 랜덤은 이동 동안 멈추고 종료 시 shuffle bag의 다음 행동을 첫 frame·첫 cycle부터 시작하며, 자동·직접 모드의 중단 복원은 보존한다. 설정의 말풍선 실행 상태·이동 상태 진단·행동 상태 진단 UI와 숨겨진 화면의 지속 갱신을 제거하고 활성 펫 화면이 보일 때만 카드 상태를 합쳐 갱신한다. Debug·Release 빌드 경고·오류 0개와 각 Activity 27개·Core 56개·Packages 28개·PetLibrary 88개·Settings 77개·Shell 20개, 총 296개 테스트를 통과했다. 첫 수정 Release의 5분 표본은 one-core CPU 5.806%, private memory 137.03→132.57MiB·최대 141.38MiB, 무응답 0회였으며 이동 종료 랜덤 재시작 최종 시각 판정은 최신 x64 Release 사용자 QA로 남았다.
- 2026-08-28: 설정창에서 행동·이동 runtime, 오버레이 frame, 자원 경고 구독과 활성 펫 runtime 문구를 제거했다. 고정 위치 변경은 원자적으로 저장하되 설정 화면 갱신을 발생시키지 않고, 활성 펫 목록은 저장된 표시 상태·이동 방식만 표시한다. 새 행동 루틴의 상시 입력 카드는 제거하고 `새 행동 루틴 만들기` 버튼과 이름 입력 대화상자로 단순화했으며 이름 변경도 같은 흐름을 사용한다. 단계 행은 현재 애니메이션 이름을 버튼 본문으로 직접 표시하고 목록 대화상자에서 교체하도록 바꿔 WinUI `ComboBox`의 placeholder 회귀를 제거했다.
- 2026-08-28: 최종 Debug·Release 각 296개 테스트와 경고·오류 없는 빌드, x64 unpackaged publish를 다시 통과했다. 65,260,678 bytes의 미서명 `MonglePet-Windows-1.4.0.13-x64-Setup.exe`를 생성했고 SHA-256은 `7F608226091564AC0B2841E99DA6CF60FFF542EC5FBE4AACAC492C11B8FBC30A`다. 기존 설치본 위 자동 업그레이드 종료 코드는 0이었고 `%LOCALAPPDATA%\MonglePet`의 40개 파일 inventory digest `F361D17DDF21F5E49D9FC2A57F12C51823CFC6E2215D3AEAA8595308492F029E`가 전후 일치했으며 설치본 FileVersion `1.4.0.13`·응답 상태를 확인했다.
- 2026-08-28: 소스 커밋 `7e7f3d9`를 `origin/main`에 푸시하고 태그 `windows-v1.4.0-preview.1`, 제목 `MonglePet Windows 1.4.0 Preview 1`의 GitHub Pre-release를 게시했다. 원격 자산을 다시 내려받아 Setup EXE 65,260,678 bytes와 SHA-256 `7F608226091564AC0B2841E99DA6CF60FFF542EC5FBE4AACAC492C11B8FBC30A`, 107 bytes `SHA256SUMS.txt`의 일치를 확인했다. 릴리스 URL은 `https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.4.0-preview.1`이다.
- 2026-08-29: 후속 소스 커밋 `682acfa50b8a48ca6c2ce6531c4dd0be673ab082`를 `origin/main`에 푸시하고 `1.4.0.14` 미서명 x64 설치기를 생성했다. Setup EXE는 65,270,050 bytes, SHA-256은 `C1B8066BFF2BCB1840E594AF668A6E3EF0226FAB5590804594AF3A2E05D64678`이다. 태그 `windows-v1.4.0-preview.2`, 제목 `MonglePet Windows 1.4.0 Preview 2`의 GitHub Pre-release를 게시하고 두 원격 자산을 다시 내려받아 크기·digest·107 bytes 체크섬 파일과 태그 대상 커밋의 일치를 확인했다. 릴리스 URL은 `https://github.com/saehajoo/MonglePet/releases/tag/windows-v1.4.0-preview.2`이다.

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
