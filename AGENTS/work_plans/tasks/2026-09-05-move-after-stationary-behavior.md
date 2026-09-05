# 평상시 행동 완료 후 이동

## 상태

- 상태: in_progress
- 생성일: 2026-09-05
- 마지막 갱신: 2026-09-05

## 목표

- 자유 이동과 마우스 도망가기의 평상시 자유 이동에 `행동 완료 후` 시간 방식을 추가한다.
- 목표 도착 뒤 현재 평상시 행동의 한 회차가 끝나면 다음 이동을 시작한다.
- 기존 고정·랜덤 시간, 조건 규칙·이동 우선순위와 즉시 도망가기 반응을 보존한다.
- macOS 기준을 schema-v16·제작자 설정 v12로 확정하고 Windows와 웹 서버 검증기에 전달한다.

## 범위

- 이동 시간 방식 Domain과 로컬 schema-v16 마이그레이션
- 제작자 설정 v12 codec과 내보내기·가져오기
- macOS 행동 완료 경계와 이동 런타임 조정
- 자유 이동·도망가기 평상시 자유 이동의 독립 설정 UI
- 공통 명세·fixture·제품 결정·플랫폼 현황
- Windows 네이티브 후속 구현과 웹 서버 패키지 검증 인계

## 제외 범위

- `.monglepet` package formatVersion 변경
- 마우스 접근 시 도망가기의 즉시 반응 변경
- 조건 규칙과 이동의 사용자 지정 우선순위 변경
- Windows와 별도 웹 서버 저장소의 소스 구현
- 자동 업데이트와 코드 서명 배포

## 열린 질문

- 없음

## 결정사항

- 시간 방식은 `fixed`, `random`, `behaviorCompletion` 세 값의 명시적 enum으로 저장한다.
- `behaviorCompletion`은 목표 도착 후 표시되는 평상시 행동의 현재 한 회차가 끝나는 시점을 다음 이동 시작점으로 사용한다.
- 고정 평상시 행동은 현재 회차 끝, 랜덤 평상시 행동은 선택된 행동 한 번의 끝을 경계로 사용한다.
- 실제 포인터 접근에 따른 도망가기는 행동 완료를 기다리지 않는다.
- 재생 가능한 평상시 행동이 없으면 500ms 안전 지연 뒤 이동해 빠른 재시도 루프를 막는다.
- 기존 고정·랜덤 값은 schema-v16과 제작자 설정 v12 이관에서 그대로 보존한다.

## 작업 순서

### 공통 계약

- [x] D-120과 행동·설정·패키지 명세에 세 시간 방식과 우선순위 경계를 기록한다.
- [x] schema-v15→v16 및 제작자 설정 v11→v12 호환 규칙과 fixture를 추가한다.

### macOS

- [x] Domain·저장 mapper·store를 schema-v16으로 올린다.
- [x] 제작자 설정 codec·요약·가져오기·내보내기를 v12로 올린다.
- [x] 행동 런타임이 평상시 행동 한 회차 완료 경계를 이동 런타임에 전달하도록 구현한다.
- [x] 자유 이동과 도망가기 평상시 자유 이동에 독립적인 `행동 완료 후` UI를 추가한다.
- [x] 관련 단위 테스트, 전체 macOS 단위 테스트와 Debug 빌드를 통과한다.
- [x] 실제 macOS 앱 QA를 완료한다.

### 배포

- [x] 앱 버전과 버전 테스트를 `1.7.0 (15)`로 올린다.
- [x] 기능·명세·Windows·서버 인계를 커밋하고 `origin/main`에 푸시한다.
- [x] 깨끗한 소스 커밋에서 Universal Preview ZIP·SHA-256·manifest를 생성한다.
- [x] `macos-v1.7.0-preview.1` GitHub Pre-release를 게시한다.
- [x] 원격 태그 대상과 세 자산의 크기·digest를 재검증한다.
- [x] 배포·다운로드 인계와 플랫폼 현황에 최종 결과를 기록하고 푸시한다.

### Windows

- [x] 확정된 enum·마이그레이션·런타임·WinUI 동작을 Windows 인계서에 기록한다.
- [x] C# Domain에 저장 문자열과 분리된 `FreeRoamingDwellMode`를 추가한다.
- [x] 기존 JSON DOM mapper 구조를 유지해 schema-v15→v16 이관과 공통 fixture 검증을 추가한다.
- [x] 권장 프로필 v1~v11 읽기를 유지하고 v12 내보내기·왕복을 추가한다.
- [x] 행동 scheduler의 평상시 한 회차 generation과 이동 runtime의 event 대기 상태를 연결한다.
- [x] 규칙·재우기·잠금·절전·설정·펫 문맥 변경의 늦은 event 무시와 500ms fallback을 검증한다.
- [x] WinUI에 `고정`·`랜덤`·`행동 완료 후`를 같은 정보 순서로 제공하고 숨은 시간 값을 보존한다.
- [x] Windows 자동 테스트와 Debug·Release 빌드 및 unpackaged publish를 완료한다.
- [x] 실제 Windows QA를 완료한다.

### Windows 배포

- [x] 사용자 승인에 따라 마케팅 버전 `1.7.0`, 파일·패키지 버전 `1.7.0.19`로 올린다.
- [x] Debug·Release 각 332개 테스트와 두 구성 빌드를 통과한다.
- [x] 기존 설치 위 업데이트에서 사용자 데이터와 설치 DLL 일치를 확인한다.
- [x] 소스 커밋과 `origin/main` 푸시를 완료한다.
- [x] `windows-v1.7.0-preview.1` GitHub Pre-release와 원격 자산을 검증한다.

### 웹 서버

- [x] 업로드 검증기가 제작자 설정 v12를 허용·검증하도록 서버 전달 문서를 갱신한다.
- [ ] 서버 환경에서 v11·v12 정상 패키지와 미래·손상 설정 정책을 검증한다.

### 플랫폼 동등성

- [ ] macOS↔Windows 제작자 설정 v12 교차 왕복과 세 시간 방식 독립성을 확인한다.
- [ ] 서버 업로드·다운로드 뒤 원본 패키지 digest와 v12 설정 보존을 확인한다.

## 검증 방법

- 고정·랜덤 기존 시간 방식의 저장·런타임 회귀
- 자유 이동에서 fixed 평상시 행동의 현재 회차 완료 후 이동
- 자유 이동에서 random 평상시 행동 한 번 완료 후 이동
- 도망가기 idle free roaming 대기 중 포인터 접근 시 즉시 도망가기
- 조건 규칙이 이동보다 높은 경우 이동 차단, 낮은 경우 기존 이동 우선 유지
- schema-v15→v16 및 제작자 설정 v1~v12 decode·encode·왕복
- 패키지 내보내기·가져오기와 두 이동 방식의 독립 설정 보존
- 전체 `MonglePetTests`, Debug 빌드와 `git diff --check`

## 진행 로그

- 2026-09-05: 작업 트리가 깨끗하고 로컬 `main`이 원격보다 2개 뒤인 것을 확인해 `a03d7d8`까지 fast-forward했다.
- 2026-09-05: 현재 이동 컨트롤러는 목표 도착 후 고정 또는 추첨한 timer가 끝나면 행동 상태와 무관하게 다음 목표를 만든다. 행동 runtime과 이동 runtime 사이에는 한 회차 완료 신호가 없어 event 기반 조정이 필요함을 확인했다.
- 2026-09-05: macOS 로컬 설정 schema-v16과 제작자 설정 v12를 구현하고, v15/v11의 기존 불리언 시간 방식을 고정·랜덤 enum으로 이관했다.
- 2026-09-05: 행동 한 회차 완료 신호와 이동 대기 상태를 연결했다. 마우스 도망가기의 포인터 감지는 대기·fallback 중에도 100ms 간격으로 유지한다.
- 2026-09-05: 전체 단위 테스트 548개 중 547개 통과·1개 fixture 미설정으로 건너뜀·실패 0개를 확인했고 Debug 빌드와 `git diff --check`가 통과했다.
- 2026-09-05: 사용자가 실제 앱 동작을 확인하고 Preview 배포를 승인했다. 새 기능선은 `1.7.0 (15)`와 `macos-v1.7.0-preview.1`로 구분한다.
- 2026-09-05: 기능·명세·버전과 Windows·서버 인계 커밋 `daa59dcdb7d9ce54f18014e14776069ef772054b`를 `origin/main`에 푸시했다.
- 2026-09-05: 같은 깨끗한 커밋에서 11,005,258 bytes Universal ZIP을 생성했다. SHA-256은 `bfbcffa0290dd298df5d58f4f5efaaabe20b92f86f7e2059a276404cdceef40d`이며 압축 해제본의 `1.7.0 (15)`·Bundle ID·arm64/x86_64·앱 아이콘과 격리된 3초 실행을 확인했다.
- 2026-09-05: 태그 `macos-v1.7.0-preview.1`의 GitHub Pre-release에 ZIP·SHA-256·manifest를 게시했다. 원격 태그 대상과 다시 내려받은 세 자산의 바이트 단위 일치·digest를 검증했다.
- 2026-09-05: Windows에서 최신 `main`을 `633dc5c`까지 fast-forward하고 현재 C# 구현이 schema-v15·권장 프로필 v11·`randomizesDwell` timer 대기에 머물러 있음을 확인했다. schema별 Swift DTO를 복사하지 않고 기존 `JsonObject` migrator·mapper 구조에 v16 계약을 추가하며, 행동 완료를 60Hz 이동 tick에서 polling하지 않고 runtime event로 연결한다.
- 2026-09-05: Windows Domain·schema-v16·권장 프로필 v12·WinUI와 event 기반 runtime을 구현했다. 애니메이션이 없는 펫도 완료 뒤 멈추지 않도록 물리 이동 activity를 행동 ID와 분리했고, timer·행동 완료·500ms fallback 및 늦은 event 무시 상태를 Core에서 단위 테스트한다. Debug·Release 각 332개 테스트와 경고·오류 없는 전체 빌드, x64 unpackaged publish를 통과했다. macOS 교차 왕복은 남겨 둔다.
- 2026-09-05: 사용자가 Windows `1.7.0` Preview 배포를 승인해 파일·패키지 버전을 `1.7.0.19`로 올렸다. 65,284,301 bytes 미서명 x64 설치기 후보의 SHA-256은 `16D8682EC425385FC686FFF26C06035A7663A05EDDFBF1E3A1ECAE3E4BDA7F45`다. 기존 설치 위 업데이트 종료 코드 0, 사용자 데이터 84개·8,453,674 bytes와 inventory digest `ED26BE94D844DA1FA0A709061366DEE4A186A8CABCCC3274136B8DE949D16061` 보존, 설치 DLL·publish DLL 일치, 설치본 응답과 Application 오류 0건을 확인했다.
- 2026-09-05: 소스 커밋 `ae2b1850218d2b1e9303a6d8c09bb5f2bf6d0fa9`를 `origin/main`에 푸시하고 annotated tag `windows-v1.7.0-preview.1`의 GitHub Pre-release를 게시했다. 원격 설치기와 107 bytes `SHA256SUMS.txt`를 다시 내려받아 크기·digest·체크섬 내용과 태그 대상을 검증했다.
- 2026-09-05: 사용자가 설치된 Windows `1.7.0.19`의 실제 기능 QA 완료를 확인했다. Windows 단계는 완료하며 macOS↔Windows 교차 왕복과 서버 검증은 각 후속 환경에서 계속한다.

## 완료 결과

- macOS 구현·실제 확인·자동 검증·Preview 1 배포, 공통 명세 및 Windows·서버 인계 문서 작성은 완료했다.
- Windows 구현·실제 QA와 Preview 1 배포 검증은 완료했다. 서버 검증과 macOS↔Windows 교차 왕복이 남아 있어 전체 상태는 진행 중으로 유지한다.

## 남은 위험 / 후속 작업

- 매우 긴 단계 반복 횟수는 의도대로 다음 이동까지 오래 기다리므로 UI 안내와 실제 QA가 필요하다.
- Windows와 서버 저장소 반영 전에는 v12 플랫폼·서비스 동등 완료로 표시하지 않는다.
