# MonglePet 설정 스키마

## 목적

MonglePet의 사용자 설정은 SwiftData나 Core Data가 아닌 버전이 지정된 JSON 파일로 저장한다. Domain 모델과 저장 DTO를 분리하고, 향후 Windows 구현에서도 읽을 수 있는 명시적인 필드와 enum 문자열을 사용한다.

## 저장 위치

```text
~/Library/Application Support/MonglePet/settings.json
```

- 설정 파일의 최대 크기는 5MiB다.
- 같은 디렉터리의 `.settings-<UUID>.tmp`에 전체 내용을 작성하고 동기화한 뒤 기존 파일과 원자적으로 교체한다.
- 저장 성공·실패 후 임시 파일을 남기지 않는다.
- 디코딩할 수 없거나 지원 버전보다 오래된 파일은 `settings.corrupt-<UUID>.json`으로 격리한 뒤 안전한 기본값을 사용한다.
- 현재 앱보다 새로운 스키마는 원본을 그대로 보존하고 해당 실행의 설정 쓰기를 차단한다.

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

기본 좌표는 첫 실행 시 현재 주 디스플레이의 visible frame으로 계산한다. 저장 계층의 기본 좌표 `0, 0`은 런타임 위치 보정 전의 안전한 초기값이다.

## 필드 규칙

- `schemaVersion`: 설정 파일 스키마 버전이며 첫 버전은 `1`이다.
- `selectedPetInstallationID`: PetLibrary가 생성한 설치 UUID 문자열 또는 `null`이다.
- `lastUserPresentation`: 사용자가 마지막으로 선택한 `awake` 또는 `tuckedAway`만 저장한다. 시스템에 의한 `suspended`는 저장하지 않는다.
- `behaviorMode`: `automatic` 또는 `manual`이다.
- `overlay.screenIdentifier`: `CGDisplayCreateUUIDFromDisplayID`로 얻은 디스플레이 UUID 기반 식별자다. 저장된 화면을 찾을 수 없으면 현재 화면 중 가장 적합한 화면을 사용한다.
- `originX`, `originY`: 유한한 macOS 전역 화면 좌표다. 복원할 때 현재 디스플레이의 visible frame 안으로 보정한다.
- `width`: 96–384pt, 기본값 192pt다. 높이는 펫 프레임 종횡비로 계산한다.
- `clickThrough`: 펫 창의 마우스 입력 통과 여부다. 메뉴 막대 복구 경로는 항상 유지한다.
- `manualSequenceID`: 존재하는 행동 목록 ID 또는 `null`이다.
- `sequences`: 최대 100개이며 목록별 단계는 최대 100개다.
- `automaticRules`: 최대 100개이며 명시적인 조건 discriminator를 사용한다.

행동 단계 규칙:

- `durationMilliseconds`: 1–86,400,000ms의 정수다.
- `playbackSpeed`: 0.25–4.0의 유한한 실수다.
- 행동 목록 ID와 모션 ID는 앞뒤 공백을 제외한 비어 있지 않은 문자열이어야 한다.

로그인 시 실행 여부는 JSON에 저장하지 않는다. 향후 `SMAppService`의 실제 등록 상태를 단일 원본으로 사용한다.

## 앱 적용 규칙

- 설정 파일이 없거나 손상 파일을 격리한 첫 실행은 저장 DTO의 `0, 0` 좌표 대신 주 화면 우하단 기본 위치를 사용한다.
- 정상 파일과 항목 단위 복구 파일은 저장된 크기를 먼저 적용한 뒤 현재 visible frame 안으로 위치를 보정한다.
- 실제 적용 후 보정된 좌표와 디스플레이 UUID를 메모리 설정에 동기화한다.
- 드래그 완료와 디스플레이 구성 변경 후 현재 좌표를 저장한다.
- 크기 슬라이더는 조작 중 화면에 즉시 적용하고 조작이 끝날 때 한 번 저장한다.
- 미래 스키마에서는 영구 설정 UI를 비활성화하지만 원본을 건드리지 않는 실행 중 깨우기·재우기는 허용한다.

## 자동 규칙 조건

앱 조건:

```json
{
  "type": "application",
  "bundleIdentifier": "com.example.Editor"
}
```

유휴 조건:

```json
{
  "type": "idleAtLeast",
  "milliseconds": 120000
}
```

- `idleAtLeast.milliseconds`는 1–86,400,000ms다.
- 알 수 없는 `type`은 문자열을 보존하되 해당 규칙을 비활성화한다.
- 존재하지 않는 행동 목록을 가리키거나 유효하지 않은 조건을 가진 규칙도 제거하지 않고 가능한 경우 비활성화한다.
- 규칙 ID가 UUID가 아니거나 필수 문자열을 복구할 수 없으면 그 규칙만 제거한다.

## Domain 변환과 복구

- JSON DTO의 정수 밀리초는 Domain의 Swift `Duration`으로 변환한다.
- 저장 enum 문자열을 Swift enum 자동 합성 결과에 의존하지 않는다.
- 잘못된 최상위 enum과 overlay 필드는 해당 필드만 기본값 또는 허용 범위로 복구한다.
- 잘못된 행동 단계는 그 단계만 제거하고, 남은 단계가 없는 행동 목록은 제거한다.
- 잘못된 수동 행동 목록 참조는 `null`로 복구한다.
- 컬렉션 상한을 넘는 항목은 저장 순서를 유지한 채 잘라낸다.
- 복구 결과는 `SettingsRecoveryIssue`로 반환하되 사용자 활동 내용은 기록하지 않는다.
- Domain 값을 저장할 때는 자동 복구하지 않고 전체 유효성을 검사해 잘못된 상태의 기록을 거부한다.

## 버전 처리

1. 파일 크기를 확인한 뒤 `schemaVersion`만 먼저 읽는다.
2. 현재 버전 `1`은 전체 DTO를 디코딩하고 항목 단위로 검증·복구한다.
3. 첫 스키마이므로 이전 버전 마이그레이션은 아직 없다. 지원하지 않는 이전 버전은 손상 파일과 같은 방식으로 격리한다.
4. 현재 앱보다 새로운 버전은 원본을 이동하거나 덮어쓰지 않고 기본값으로 실행하며 저장을 거부한다.
5. 향후 마이그레이션은 버전별 순차 변환과 fixture 기반 단위 테스트를 함께 추가한다.

---

문서 상태: active
스키마 버전: 1
마지막 갱신: 2026-07-22
