# MonglePet 설정 스키마 초안

## 목적

MonglePet의 사용자 설정은 SwiftData나 Core Data가 아닌 버전이 지정된 JSON 파일로 저장한다. Domain 모델과 저장 DTO를 분리하고, 향후 Windows 구현에서도 읽을 수 있는 명시적인 필드와 enum 문자열을 사용한다.

구현 시점은 로드맵의 사용자 설정 및 복원 단계다. 1단계 오버레이 셸은 실행 중 메모리 상태만 사용한다.

## 저장 위치

```text
~/Library/Application Support/MonglePet/settings.json
```

- 임시 파일에 전체 내용을 작성하고 동기화한 뒤 기존 파일과 원자적으로 교체한다.
- 앱 실행 중 일부 필드만 파일에 직접 덧쓰지 않는다.
- 디코딩에 실패한 파일은 덮어쓰지 않고 진단 가능한 이름으로 격리한 뒤 안전한 기본값을 사용한다.

## 최상위 구조

```json
{
  "schemaVersion": 1,
  "selectedPetInstallationID": null,
  "lastUserPresentation": "awake",
  "behaviorMode": "automatic",
  "overlay": {
    "screenIdentifier": null,
    "originX": 0,
    "originY": 0,
    "width": 192,
    "clickThrough": false
  },
  "manualSequenceID": null,
  "sequences": [],
  "automaticRules": []
}
```

이 예시는 필드 책임을 정의하기 위한 초안이며 실제 기본 좌표는 첫 실행 시 현재 주 디스플레이의 visible frame으로 계산한다.

## 필드 규칙

- `schemaVersion`: 설정 파일 스키마 버전이며 MVP의 첫 버전은 `1`이다.
- `selectedPetInstallationID`: PetLibrary가 생성한 설치 UUID 문자열 또는 `null`이다.
- `lastUserPresentation`: 사용자가 마지막으로 선택한 `awake` 또는 `tuckedAway`만 저장한다. 시스템에 의한 `suspended`는 저장하지 않는다.
- `behaviorMode`: `automatic` 또는 `manual`이다.
- `overlay.screenIdentifier`: 마지막으로 표시한 디스플레이의 안정적인 식별자이며 찾을 수 없으면 주 디스플레이를 사용한다.
- `originX`, `originY`: macOS 전역 화면 좌표다. 복원할 때 현재 디스플레이의 visible frame 안으로 보정한다.
- `width`: 펫 표시 너비다. 높이는 펫 프레임 종횡비로 계산한다.
- `clickThrough`: 펫 창의 마우스 입력 통과 여부다. 메뉴 막대 복구 경로는 항상 유지한다.
- `sequences`: `BEHAVIOR_MODEL.md`의 저장 DTO 배열이다.
- `automaticRules`: 명시적인 조건 discriminator를 사용하는 자동 규칙 DTO 배열이다.

## Domain 변환

- JSON DTO의 정수 밀리초는 Domain의 Swift `Duration`으로 변환한다.
- 저장 enum 문자열을 Swift enum 자동 합성 결과에 의존하지 않는다.
- 알 수 없는 선택 필드는 무시할 수 있지만 알 수 없는 필수 enum 값은 해당 설정 항목만 기본값으로 복구한다.
- 유효하지 않은 펫 설치 ID나 행동 목록 ID는 기본 펫과 기본 행동으로 대체한다.
- 기본값 적용과 복구는 로그에 남기되 사용자 활동 내용은 기록하지 않는다.

## 마이그레이션

1. 파일의 `schemaVersion`을 먼저 읽는다.
2. 현재보다 오래된 버전은 단계별 마이그레이션을 순서대로 적용한다.
3. 현재 앱보다 새로운 버전은 원본을 보존하고 쓰기를 중단한 뒤 안전한 기본 설정으로 실행한다.
4. 마이그레이션이 완료된 설정은 검증 후 원자적으로 저장한다.
5. 각 버전 변환과 손상 복구를 fixture 기반 단위 테스트로 검증한다.

## 열린 항목

- 펫 크기의 최소·최대 너비
- 재생 속도의 허용 범위
- 로그인 시 자동 실행 설정을 이 파일에 둘지 시스템 서비스 상태에서 조회할지 여부
- 앱별 자동 규칙의 최대 개수와 동일 priority 정규화 정책

---

문서 상태: draft
스키마 버전: 1
마지막 갱신: 2026-07-21
