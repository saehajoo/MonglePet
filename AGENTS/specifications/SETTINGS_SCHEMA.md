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
- 디코딩할 수 없는 파일은 `settings.corrupt-<UUID>.json`으로 격리한 뒤 안전한 기본값을 사용한다.
- 지원하는 이전 버전은 선택 펫 정의를 먼저 읽어 순차 마이그레이션하고, 성공한 결과만 원자적으로 현재 버전 파일로 교체한다.
- 현재 앱보다 새로운 스키마는 원본을 그대로 보존하고 해당 실행의 설정 쓰기를 차단한다.

## 현재 schema-v3 최상위 구조

```json
{
  "schemaVersion": 3,
  "selectedPetInstallationID": null,
  "lastUserPresentation": "awake",
  "overlay": {
    "screenIdentifier": null,
    "originX": 0,
    "originY": 0,
    "width": 192,
    "clickThrough": false
  },
  "behaviorProfiles": [
    {
      "petKey": { "type": "builtIn" },
      "mode": "automatic",
      "manualSequenceID": "__monglepet_default_behavior__",
      "sequences": [
        {
          "id": "__monglepet_default_behavior__",
          "steps": [
            {
              "motionID": "__monglepet_current_pet_default__",
              "repeatCount": 1
            }
          ],
          "repeats": true
        }
      ],
      "automaticRules": [],
      "pettingMotionID": null,
      "movement": {
        "mode": "fixed",
        "speed": 160,
        "cursorDistance": 96,
        "stopRadius": 16,
        "freeRoamingDwellMilliseconds": 6000,
        "prefersFrontmostWindow": true,
        "cursorFollowingMotionID": null,
        "freeRoamingMotionID": null
      }
    }
  ]
}
```

기본 좌표는 첫 실행 시 현재 주 디스플레이의 visible frame으로 계산한다. 저장 계층의 기본 좌표 `0, 0`은 런타임 위치 보정 전의 안전한 초기값이다.

## 필드 규칙

- `schemaVersion`: 현재 설정 파일 스키마 버전은 `3`이다.
- `selectedPetInstallationID`: PetLibrary가 생성한 설치 UUID 문자열 또는 `null`이다.
- `lastUserPresentation`: 사용자가 마지막으로 선택한 `awake` 또는 `tuckedAway`만 저장한다. 시스템에 의한 `suspended`는 저장하지 않는다.
- `overlay.screenIdentifier`: `CGDisplayCreateUUIDFromDisplayID`로 얻은 디스플레이 UUID 기반 식별자다. 저장된 화면을 찾을 수 없으면 현재 화면 중 가장 적합한 화면을 사용한다.
- `originX`, `originY`: 유한한 macOS 전역 화면 좌표다. 복원할 때 현재 디스플레이의 visible frame 안으로 보정한다.
- `width`: 96–384pt, 기본값 192pt다. 높이는 펫 프레임 종횡비로 계산한다.
- `clickThrough`: 펫 창의 마우스 입력 통과 여부다. 메뉴 막대 복구 경로는 항상 유지한다.
- `behaviorProfiles`: 내장 펫 예약 키 또는 설치 UUID별 행동 설정이며 최대 1,000개다. 같은 키는 한 번만 저장한다.
- `behaviorProfiles[].mode`: `automatic` 또는 `manual`이다.
- `behaviorProfiles[].manualSequenceID`: 같은 프로필에 존재하는 행동 목록 ID 또는 `null`이다.
- `behaviorProfiles[].sequences`: 최대 100개이며 목록별 단계는 최대 100개다.
- `behaviorProfiles[].automaticRules`: 최대 100개이며 명시적인 조건 discriminator를 사용한다.
- `behaviorProfiles[].pettingMotionID`: 펫을 클릭했을 때 한 번 재생할 현재 펫 애니메이션 ID 또는 `null`이다.
- `behaviorProfiles[].movement.mode`: `fixed`, `cursorFollowing`, `freeRoaming` 중 하나이며 기본값은 `fixed`다.
- `behaviorProfiles[].movement.speed`: 초당 이동 거리이며 20–1,000pt/s, 기본값 160pt/s다.
- `behaviorProfiles[].movement.cursorDistance`: 마우스 따라가기 목표 거리이며 0–512pt, 기본값 96pt다.
- `behaviorProfiles[].movement.stopRadius`: 목표 도착으로 판단하는 반경이며 0–128pt, 기본값 16pt다.
- `behaviorProfiles[].movement.freeRoamingDwellMilliseconds`: 자유 이동 목표에서 머무는 시간이며 500–300,000ms, 기본값 6,000ms다.
- `behaviorProfiles[].movement.prefersFrontmostWindow`: 자유 이동 목표를 만들 때 현재 전면 앱의 대표 창 주변을 우선할지 나타내며 기본값은 `true`다.
- `behaviorProfiles[].movement.cursorFollowingMotionID`: 마우스 따라가기로 실제 이동 중 재생할 펫 애니메이션 ID 또는 `null`이다.
- `behaviorProfiles[].movement.freeRoamingMotionID`: 자유 이동으로 실제 이동 중 재생할 펫 애니메이션 ID 또는 `null`이다.

행동 단계 규칙:

- `motionID`: 현재 펫에 존재하는 애니메이션 ID 또는 현재 펫 기본 애니메이션 예약 참조다.
- `repeatCount`: 1–100,000의 정수다.
- 행동 목록 ID와 모션 ID는 앞뒤 공백을 제외한 비어 있지 않은 문자열이어야 한다.

로그인 시 실행 여부는 JSON에 저장하지 않는다. 향후 `SMAppService`의 실제 등록 상태를 단일 원본으로 사용한다.

## 앱 적용 규칙

- 설정 파일이 없거나 손상 파일을 격리한 첫 실행은 저장 DTO의 `0, 0` 좌표 대신 주 화면 우하단 기본 위치를 사용한다.
- 정상 파일과 항목 단위 복구 파일은 저장된 크기를 먼저 적용한 뒤 현재 visible frame 안으로 위치를 보정한다.
- 실제 적용 후 보정된 좌표와 디스플레이 UUID를 메모리 설정에 동기화한다.
- 드래그 완료와 디스플레이 구성 변경 후 현재 좌표를 저장한다.
- 크기 슬라이더는 조작 중 화면에 즉시 적용하고 조작이 끝날 때 한 번 저장한다.
- 미래 스키마에서는 영구 설정 UI를 비활성화하지만 원본을 건드리지 않는 실행 중 깨우기·재우기는 허용한다.
- 선택 펫 프로필의 `sequences`가 비어 있으면 현재 펫의 기본 애니메이션을 참조하는 시스템 `기본` 루틴 하나를 실행 중 주입하며, 사용자가 다음 설정을 변경할 때 함께 저장한다. 기본 자동 규칙은 만들지 않는다.

## schema-v3 펫별 행동·이동 프로필

schema-v2는 schema-v1의 최상위 전역 행동 필드를 펫별 `behaviorProfiles`로 이동했다. schema-v3는 같은 프로필에 `movement`와 선택적 `pettingMotionID`를 추가해 행동 모드, 이동 모드와 클릭 반응을 독립적으로 저장한다. 초기 schema-v3 파일에 `pettingMotionID`가 없으면 `null`과 동일하게 읽는다.

```json
{
  "schemaVersion": 3,
  "selectedPetInstallationID": null,
  "lastUserPresentation": "awake",
  "overlay": {
    "screenIdentifier": null,
    "originX": 0,
    "originY": 0,
    "width": 192,
    "clickThrough": false
  },
  "behaviorProfiles": [
    {
      "petKey": { "type": "builtIn" },
      "mode": "automatic",
      "manualSequenceID": null,
      "sequences": [],
      "automaticRules": [],
      "pettingMotionID": null,
      "movement": {
        "mode": "fixed",
        "speed": 160,
        "cursorDistance": 96,
        "stopRadius": 16,
        "freeRoamingDwellMilliseconds": 6000,
        "prefersFrontmostWindow": true,
        "cursorFollowingMotionID": null,
        "freeRoamingMotionID": null
      }
    },
    {
      "petKey": {
        "type": "installed",
        "installationID": "11111111-1111-1111-1111-111111111111"
      },
      "mode": "manual",
      "manualSequenceID": null,
      "sequences": [],
      "automaticRules": [],
      "pettingMotionID": "happy",
      "movement": {
        "mode": "freeRoaming",
        "speed": 240,
        "cursorDistance": 120,
        "stopRadius": 20,
        "freeRoamingDwellMilliseconds": 9000,
        "prefersFrontmostWindow": true,
        "cursorFollowingMotionID": null,
        "freeRoamingMotionID": "run"
      }
    }
  ]
}
```

- 내장 몽글이는 UUID 대신 `builtIn` 예약 키를 사용한다.
- 설치 펫은 패키지 ID가 아닌 PetLibrary 설치 UUID를 키로 사용한다. 같은 패키지의 별도 사본은 서로 다른 행동 설정을 가질 수 있다.
- 행동의 `mode`, `manualSequenceID`, `sequences`, `automaticRules`, 쓰다듬기 애니메이션과 이동의 `movement` 전체가 프로필에 속한다.
- 선택한 펫의 프로필이 없으면 시스템 `기본` 루틴 하나와 자동 규칙 0개로 생성한다.
- 같은 설치 UUID를 업데이트하거나 편집해도 프로필을 유지한다.
- 가져오기 교체에서 사용자가 권장 설정 전체 적용을 명시적으로 선택한 경우에만 해당 설치 UUID의 프로필을 교체한다. 다른 펫 프로필과 overlay·표시 상태는 유지한다.
- 별도 사본 설치와 새 사용자 펫은 독립 프로필을 만든다.
- 앱에서 설치 펫 삭제를 확인하면 해당 설치 UUID의 행동 프로필을 함께 제거하고 내장 몽글이를 선택한다.
- 앱 시작 시 설치 폴더 누락·손상 등으로 선택 펫을 찾지 못하면 내장 몽글이를 선택하되, 연결이 끊긴 행동 설정은 자동 삭제하지 않는다. 사용자가 앱에서 명시적으로 삭제한 경우에만 제거한다.
- `.monglepet` 공유 권장 프로필은 로컬 프로필 전체를 복사하지 않고 화면 좌표와 설치 식별자를 제외한 별도 DTO를 사용한다. 새 설치에서 사용자가 적용을 선택하면 설치 UUID를 키로 하는 로컬 `BehaviorProfile`로 변환해 저장한다.

schema-v3의 행동 단계는 schema-v2와 동일하게 `motionID`와 `repeatCount`를 저장한다. schema-v1의 `durationMilliseconds`, `playbackSpeed`는 기록하지 않는다. v1 마이그레이션은 선택 펫 패키지에 저장된 프레임 시간으로 애니메이션 한 사이클을 계산하고, 기존 유지 시간에 가장 가까운 반복 횟수를 사용한다. 단계별 `playbackSpeed`는 패키지 프레임 시간을 단일 속도 원본으로 삼기 위해 변환에 반영하지 않는다. 참조 애니메이션을 찾지 못하면 현재 펫 기본 애니메이션과 반복 1회로 복구한다.

## Phase 9B 계획: schema-v4 로컬 표시 환경

현재 구현과 저장 파일의 스키마는 v3다. Phase 9B에서 전역 overlay에 이동 범위와 투명도 설정을 추가할 때 schema-v4로 순차 마이그레이션한다.

```json
{
  "schemaVersion": 4,
  "selectedPetInstallationID": null,
  "lastUserPresentation": "awake",
  "overlay": {
    "screenIdentifier": null,
    "originX": 0,
    "originY": 0,
    "width": 192,
    "clickThrough": false,
    "opacity": 1.0,
    "pointerOverlapFadeEnabled": false,
    "pointerOverlapOpacity": 0.2,
    "movementBoundary": {
      "mode": "allDisplays",
      "screenIdentifier": null,
      "normalizedRect": null
    }
  },
  "behaviorProfiles": []
}
```

계획 필드 규칙:

- `overlay.opacity`: 평상시 패널 투명도이며 `0.10...1.00`, 기본값 `1.00`이다.
- `overlay.pointerOverlapFadeEnabled`: 클릭 통과 중 마우스가 실제 표시 픽셀과 겹칠 때 투명도를 바꿀지 나타내며 기본값은 `false`다.
- `overlay.pointerOverlapOpacity`: 겹침 상태 투명도이며 `0.05...1.00`, 기본값 `0.20`이다. 실제 적용 값은 `opacity`보다 커지지 않는다.
- `overlay.movementBoundary.mode`: `allDisplays`, `selectedDisplay`, `customArea` 중 하나이며 기본값은 `allDisplays`다.
- `selectedDisplay`와 `customArea`에는 디스플레이 UUID 기반 `screenIdentifier`가 필요하다.
- `customArea.normalizedRect`는 선택한 화면의 현재 visible frame을 기준으로 한 `x`, `y`, `width`, `height`의 `0...1` 정규화 사각형이다.
- 사용자 지정 영역은 펫 전체가 들어갈 수 있는 실제 원점 범위로 축소해 사용한다. 너무 작은 영역은 중앙의 한 원점으로 안전하게 축소한다.
- 저장된 화면을 찾지 못하면 실행 중에는 모든 사용 가능 화면으로 폴백하되 저장된 화면과 영역 선택을 자동 삭제하지 않는다.
- 위치 고정에는 `movementBoundary`를 적용하지 않는다. 마우스 따라가기와 자유 이동의 목표 좌표에만 적용한다.
- 이동 범위와 투명도는 기기별 전역 표시 환경이며 `BehaviorProfile`, `.monglepet`과 `recommended-profile.json`에 포함하지 않는다.

schema-v3에서 v4로 마이그레이션할 때 기존 overlay 값과 모든 펫 프로필을 그대로 유지하고 위 계획 필드의 기본값만 추가한다. 변환과 원자적 저장이 모두 성공한 경우에만 v4 파일로 교체한다.

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

- schema-v3의 반복 횟수는 Domain의 `BehaviorStep.repeatCount`로 변환한다. v1의 정수 밀리초는 마이그레이션 과정에서만 Swift `Duration` 호환 정보로 읽는다.
- 잘못된 이동 enum이나 범위 밖 값은 해당 필드만 schema-v3 기본값으로 복구하고 `SettingsRecoveryIssue.invalidField`를 반환한다.
- 이동·쓰다듬기 애니메이션 ID는 앞뒤 공백이 없는 비어 있지 않은 문자열 또는 `null`이다. 이름 변경 시 같은 펫 프로필의 참조를 함께 바꾸고 삭제 시 `null`로 해제한다.
- 저장 enum 문자열을 Swift enum 자동 합성 결과에 의존하지 않는다.
- 잘못된 최상위 enum과 overlay 필드는 해당 필드만 기본값 또는 허용 범위로 복구한다.
- 잘못된 행동 단계는 그 단계만 제거하고, 남은 단계가 없는 행동 목록은 제거한다.
- 잘못된 수동 행동 목록 참조는 `null`로 복구한다.
- 컬렉션 상한을 넘는 항목은 저장 순서를 유지한 채 잘라낸다.
- 복구 결과는 `SettingsRecoveryIssue`로 반환하되 사용자 활동 내용은 기록하지 않는다.
- Domain 값을 저장할 때는 자동 복구하지 않고 전체 유효성을 검사해 잘못된 상태의 기록을 거부한다.

## 버전 처리

1. 파일 크기를 확인한 뒤 `schemaVersion`만 먼저 읽는다.
2. 현재 버전 `3`은 전체 DTO를 디코딩하고 프로필·항목 단위로 검증·복구한다.
3. 버전 `2`는 모든 펫 프로필에 기본 `fixed` 이동 설정을 추가하고 같은 디렉터리의 임시 파일을 거쳐 v3로 원자적 교체한다.
4. 버전 `1`은 당시 선택된 펫의 정의를 먼저 불러와 v2 행동 프로필로 변환한 뒤 v3 기본 이동 설정을 추가한다. 전체 변환과 저장이 성공한 경우에만 v3로 원자적 교체하며, 필요한 펫 정의를 얻지 못하거나 저장에 실패하면 v1 원본과 쓰기 차단 상태를 유지한다.
5. 현재 앱보다 새로운 버전은 원본을 이동하거나 덮어쓰지 않고 기본값으로 실행하며 저장을 거부한다.
6. 향후 마이그레이션은 버전별 순차 변환과 fixture 기반 단위 테스트를 함께 추가한다.

Phase 9B 구현이 완료되면 현재 버전을 `4`로 올리고 위 목록에 v3 → v4 순차 변환을 추가한다. 계획 단계에서는 v3 로더와 저장 동작을 변경하지 않는다.

---

문서 상태: active
스키마 버전: 3
마지막 갱신: 2026-07-23
