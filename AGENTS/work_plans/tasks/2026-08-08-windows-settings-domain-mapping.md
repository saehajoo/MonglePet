# Windows schema-v10 Domain 매핑과 항목 복구

## 상태

- 상태: completed
- 생성일: 2026-08-08
- 마지막 갱신: 2026-08-08

## 목표

- Windows가 schema-v10 전체 설정을 타입이 지정된 Domain 모델로 읽는다.
- 잘못된 필드·행동 단계·규칙·프로필·말풍선 항목만 독립적으로 복구하고 나머지 사용자 설정을 유지한다.
- 유효한 Domain 설정 전체 저장과 기존 선택 UUID 전용 저장을 모두 원자적으로 지원한다.

## 범위

- overlay, 행동 프로필, 이동·방향 애니메이션, 쓰다듬기와 말풍선 schema-v10 Domain 모델
- macOS와 같은 상한·범위·식별자·참조·대비 검증
- 구조 보존 JSON mapper와 타입이 지정된 복구 issue
- `AppSettingsStore`의 typed load result 및 전체 설정 저장 API
- 유효 설정 왕복, 부분 손상 복구, 컬렉션 상한과 저장 거부 xUnit 테스트
- Debug·Release 빌드·테스트와 문서 갱신

## 제외 범위

- WinUI 설정 편집 화면
- 설정을 오버레이·행동 scheduler·이동·말풍선 런타임에 적용
- Windows 전면 앱 식별자 선택 UI와 기존 macOS bundle identifier 변환 정책
- schema-v11 또는 공통 설정 형식 변경

## 열린 질문

- 없음

## 결정사항

- Domain 모델은 파일 시스템과 WinUI에 의존하지 않는 `MonglePet.Settings` 관리형 계층에 둔다.
- mapper는 입력 JSON을 복제해 알려진 필드만 정규화하므로 같은 schema의 알 수 없는 확장 필드를 보존한다.
- 로드는 복구된 Domain 값을 반환하지만 현재 schema-v10 파일을 즉시 덮어쓰지 않는다. 다음 명시적 저장에서 정규화된 현재 값을 기록한다.
- 전체 설정 저장은 자동 복구하지 않고 모든 참조와 범위를 검증해 잘못된 Domain 상태를 거부한다.

## 작업 순서

- [x] 1단계: schema-v10 Domain 모델과 복구 issue 정의
- [x] 2단계: JSON→Domain 항목 단위 mapper 구현
- [x] 3단계: Domain→JSON 검증·구조 보존 mapper와 Store API 연결
- [x] 4단계: 전체·손상·상한·저장 거부 테스트
- [x] 5단계: Debug·Release 검증과 문서 갱신

## 검증 방법

- 완전한 schema-v10의 모든 필드 Domain 왕복
- 잘못된 최상위 enum·overlay·이동 값은 해당 필드만 기본값 복구
- 잘못된 단계는 제거하고 빈 행동 목록은 제거, 잘못된 규칙은 보존 가능한 경우 비활성화
- 중복·잘못된 펫 키와 대사 UUID는 해당 항목만 제외
- 방향 모션, 말풍선 정책·테마·대비·배치의 독립 복구
- 컬렉션 상한 절단과 issue 경로 확인
- 선택 UUID 전용 저장 시 알 수 없는 필드 보존
- 유효하지 않은 Domain 전체 저장 거부와 기존 파일 불변성

## 진행 로그

- 2026-08-08: `SETTINGS_SCHEMA.md`, macOS `AppSettingsV2Mapper`~`V10Mapper`와 Windows 기존 선택 UUID 저장소를 대조했다. Windows는 JSON 구조 보존 mapper로 같은 복구 계약을 구현한다.
- 2026-08-08: overlay, 행동 프로필, 이동·방향 모션, 말풍선 전체를 나타내는 관리형 Domain 모델과 타입이 지정된 복구 issue를 추가했다.
- 2026-08-08: 현재 schema JSON을 필드·항목 단위로 읽어 잘못된 단계·규칙·대사·프로필을 독립 복구하고 로드만으로 파일을 다시 쓰지 않는 mapper를 연결했다.
- 2026-08-08: 유효한 Domain 전체 저장을 추가했다. 저장 전에 범위·상한·참조·대비를 검증하며, 기존 JSON에서 살아남은 상위·중첩 항목의 알 수 없는 확장 필드를 보존한다.
- 2026-08-08: Settings 테스트를 23개로 확장하고 전체 xUnit 58개가 Debug·Release에서 통과했다. 두 구성의 전체 빌드는 경고·오류 0개이며 C# whitespace 검증도 통과했다.
- 2026-08-08: typed 로더가 포함된 Release loose AppX를 깨끗한 LocalState에 개발 등록해 정상 응답을 확인하고 프로세스·개발 패키지·QA 데이터를 제거했다.

## 완료 결과

- schema-v10 전체 설정을 타입이 지정된 Domain 모델로 읽고 항목 단위 복구 issue와 함께 반환한다.
- 유효한 전체 설정을 원자적으로 저장하며 잘못된 Domain 상태는 기존 파일을 변경하지 않고 거부한다.
- 선택 UUID 전용 저장과 미래 schema 원본 보호, v1~v9 마이그레이션 계약을 유지한다.

## 남은 위험 / 후속 작업

- Domain 설정을 실제 WinUI 편집기와 오버레이·행동·이동·말풍선 런타임에 연결하는 작업이 남는다.
