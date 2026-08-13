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

## 현재 schema-v10 최상위 구조

```json
{
  "schemaVersion": 10,
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
    "pixelArtRendering": false,
    "movementBoundary": {
      "mode": "allDisplays",
      "screenIdentifier": null,
      "normalizedRect": null
    }
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
      "speech": {
        "isEnabled": false,
        "periodicIsEnabled": false,
        "periodicIntervalMilliseconds": 60000,
        "periodicOrder": "random",
        "behaviorChangePolicy": "dismiss",
        "phrases": [],
        "theme": {
          "colorStyle": "system",
          "customBackgroundColor": { "red": 1, "green": 1, "blue": 1 },
          "customTextColor": { "red": 0, "green": 0, "blue": 0 },
          "backgroundOpacity": 0.96,
          "fontSize": 14,
          "contentPadding": 12,
          "cornerRadius": 14,
          "showsTail": false,
          "tailAlignment": "center"
        },
        "placement": {
          "preferredPosition": "automatic",
          "horizontalOffset": 0,
          "gap": 8
        }
      },
      "movement": {
        "mode": "fixed",
        "speed": 160,
        "cursorDistance": 96,
        "stopRadius": 16,
        "freeRoamingDwellMilliseconds": 6000,
        "prefersFrontmostWindow": true,
        "cursorAvoidingIdleBehavior": "stationary",
        "cursorAvoidingDetectionDistance": 160,
        "cursorAvoidingSpeed": 320,
        "cursorFollowingAnimation": {
          "fallbackMotionID": null,
          "usesDirectionalMotions": false,
          "usesDiagonalMotions": false,
          "directionMotionIDs": {
            "left": null,
            "right": null,
            "up": null,
            "down": null,
            "upLeft": null,
            "upRight": null,
            "downLeft": null,
            "downRight": null
          }
        },
        "freeRoamingAnimation": {
          "fallbackMotionID": null,
          "usesDirectionalMotions": false,
          "usesDiagonalMotions": false,
          "directionMotionIDs": {
            "left": null,
            "right": null,
            "up": null,
            "down": null,
            "upLeft": null,
            "upRight": null,
            "downLeft": null,
            "downRight": null
          }
        },
        "cursorAvoidingAnimation": {
          "fallbackMotionID": null,
          "usesDirectionalMotions": false,
          "usesDiagonalMotions": false,
          "directionMotionIDs": {
            "left": null,
            "right": null,
            "up": null,
            "down": null,
            "upLeft": null,
            "upRight": null,
            "downLeft": null,
            "downRight": null
          }
        }
      }
    }
  ]
}
```

기본 좌표는 첫 실행 시 현재 주 디스플레이의 visible frame으로 계산한다. 저장 계층의 기본 좌표 `0, 0`은 런타임 위치 보정 전의 안전한 초기값이다.

## 필드 규칙

- `schemaVersion`: 현재 설정 파일 스키마 버전은 `10`이다.
- `selectedPetInstallationID`: PetLibrary가 생성한 설치 UUID 문자열 또는 `null`이다.
- `lastUserPresentation`: 사용자가 마지막으로 선택한 `awake` 또는 `tuckedAway`만 저장한다. 시스템에 의한 `suspended`는 저장하지 않는다.
- `overlay.screenIdentifier`: `CGDisplayCreateUUIDFromDisplayID`로 얻은 디스플레이 UUID 기반 식별자다. 저장된 화면을 찾을 수 없으면 현재 화면 중 가장 적합한 화면을 사용한다.
- `originX`, `originY`: 유한한 macOS 전역 화면 좌표다. 복원할 때 현재 디스플레이의 visible frame 안으로 보정한다.
- `width`: 96–384pt, 기본값 192pt다. 높이는 펫 프레임 종횡비로 계산한다.
- `clickThrough`: 펫 창의 마우스 입력 통과 여부다. 메뉴 막대 복구 경로는 항상 유지한다.
- `opacity`: 평상시 패널 투명도이며 0.10–1.00, 기본값 1.00이다.
- `pointerOverlapFadeEnabled`: 클릭 통과 중 마우스가 실제 표시 픽셀과 겹칠 때 투명도를 바꿀지 나타내며 기본값은 `false`다.
- `pointerOverlapOpacity`: 마우스 겹침 상태 투명도이며 0.05–1.00, 기본값 0.20이다.
- `pixelArtRendering`: 확대·축소 필터를 픽셀 아트에 맞는 nearest 방식으로 표시할지 나타내며 기본값은 `false`다.
- `movementBoundary`: 모든 화면, 선택 모니터 또는 선택 모니터의 정규화 사용자 영역으로 자동 이동 목표를 제한한다.
- `behaviorProfiles`: 내장 펫 예약 키 또는 설치 UUID별 행동 설정이며 최대 1,000개다. 같은 키는 한 번만 저장한다.
- `behaviorProfiles[].mode`: `automatic` 또는 `manual`이다.
- `behaviorProfiles[].manualSequenceID`: 같은 프로필에 존재하는 행동 목록 ID 또는 `null`이다.
- `behaviorProfiles[].sequences`: 최대 100개이며 목록별 단계는 최대 100개다.
- `behaviorProfiles[].automaticRules`: 최대 100개이며 명시적인 조건 discriminator를 사용한다.
- `behaviorProfiles[].pettingMotionID`: 펫의 실제 표시 영역에 마우스를 잠시 올렸을 때 한 번 재생할 현재 펫 애니메이션 ID 또는 `null`이다.
- `behaviorProfiles[].movement.mode`: `fixed`, `cursorFollowing`, `freeRoaming`, `cursorAvoiding` 중 하나이며 기본값은 `fixed`다.
- `behaviorProfiles[].movement.speed`: 초당 이동 거리이며 20–1,000pt/s, 기본값 160pt/s다.
- `behaviorProfiles[].movement.cursorDistance`: 마우스 따라가기 목표 거리이며 0–512pt, 기본값 96pt다.
- `behaviorProfiles[].movement.stopRadius`: 목표 도착으로 판단하는 반경이며 0–128pt, 기본값 16pt다.
- `behaviorProfiles[].movement.freeRoamingDwellMilliseconds`: 자유 이동 목표에서 머무는 시간이며 500–300,000ms, 기본값 6,000ms다.
- `behaviorProfiles[].movement.prefersFrontmostWindow`: 자유 이동 목표를 만들 때 현재 전면 앱의 대표 창 주변을 우선할지 나타내며 기본값은 `true`다.
- `behaviorProfiles[].movement.cursorAvoidingIdleBehavior`: 마우스가 감지 거리 밖일 때 `stationary` 또는 `freeRoaming`으로 동작하며 기본값은 `stationary`다.
- `behaviorProfiles[].movement.cursorAvoidingDetectionDistance`: 펫 표시 사각형 가장자리에서 포인터까지의 감지 거리이며 32–1,024pt, 기본값 160pt다.
- `behaviorProfiles[].movement.cursorAvoidingSpeed`: 포인터를 피해 움직이는 초당 이동 거리이며 20–1,000pt/s, 기본값 320pt/s다.
- `behaviorProfiles[].movement.cursorFollowingAnimation`: 마우스 따라가기에서 사용할 공통·방향별 이동 애니메이션 설정이다.
- `behaviorProfiles[].movement.freeRoamingAnimation`: 자유 이동에서 사용할 공통·방향별 이동 애니메이션 설정이다.
- `behaviorProfiles[].movement.cursorAvoidingAnimation`: 포인터를 피해 이동할 때 사용할 공통·방향별 이동 애니메이션 설정이다. 평상시 자유 이동은 `freeRoamingAnimation`을 사용한다.
- 각 `*Animation.fallbackMotionID`: 방향 기능을 사용하지 않을 때의 단일 이동 애니메이션이자 방향 참조가 없을 때의 최종 fallback이다.
- 각 `*Animation.usesDirectionalMotions`: `true`이면 실제 이동 방향에 맞는 참조를 우선한다.
- 각 `*Animation.usesDiagonalMotions`: 방향 기능이 켜진 상태에서만 `true`일 수 있으며 4방향 대신 8방향을 분류한다.
- 각 `*Animation.directionMotionIDs`: `left`, `right`, `up`, `down`, `upLeft`, `upRight`, `downLeft`, `downRight`의 명시적인 애니메이션 ID 또는 `null`이다.

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

schema-v2는 schema-v1의 최상위 전역 행동 필드를 펫별 `behaviorProfiles`로 이동했다. schema-v3는 같은 프로필에 `movement`와 선택적 `pettingMotionID`를 추가해 행동 모드, 이동 모드와 쓰다듬기 반응을 독립적으로 저장한다. 초기 schema-v3 파일에 `pettingMotionID`가 없으면 `null`과 동일하게 읽는다.

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

## schema-v4 로컬 표시 환경

schema-v4는 전역 overlay에 이동 범위, 투명도와 선택형 픽셀 아트 표시 설정을 둔다. 이동 범위는 설정 UI와 자동 이동에 적용하고, 표시 설정은 일반 설정 UI와 펫 패널 런타임에 즉시 적용한다.

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
    "pixelArtRendering": false,
    "movementBoundary": {
      "mode": "allDisplays",
      "screenIdentifier": null,
      "normalizedRect": null
    }
  },
  "behaviorProfiles": []
}
```

필드 규칙:

- `overlay.opacity`: 평상시 패널 투명도이며 `0.10...1.00`, 기본값 `1.00`이다.
- `overlay.pointerOverlapFadeEnabled`: 클릭 통과 중 마우스가 실제 표시 픽셀과 겹칠 때 투명도를 바꿀지 나타내며 기본값은 `false`다.
- `overlay.pointerOverlapOpacity`: 겹침 상태 투명도이며 `0.05...1.00`, 기본값 `0.20`이다. 실제 적용 값은 `opacity`보다 커지지 않는다.
- `overlay.pixelArtRendering`: `true`이면 nearest 보간으로 픽셀 경계를 선명하게 표시하고, `false`이면 일반 일러스트에 적합한 linear 보간을 사용한다. 기본값과 이전 schema-v4 파일에서 필드가 없을 때의 값은 `false`다.
- 마우스 겹침 투명화는 클릭 통과, 펫 awake, 화면 사용 가능과 macOS 동작 줄이기 꺼짐 조건을 모두 만족할 때만 포인터를 확인한다. 나머지 상태에서는 감지 timer를 해제하고 기본 투명도를 적용한다.
- 겹침 판정은 패널 전체가 아니라 현재 애니메이션 프레임의 실제 알파 표시 영역과 종횡비 여백을 기준으로 한다.
- `overlay.movementBoundary.mode`: `allDisplays`, `selectedDisplay`, `customArea` 중 하나이며 기본값은 `allDisplays`다.
- `selectedDisplay`와 `customArea`에는 디스플레이 UUID 기반 `screenIdentifier`가 필요하다.
- `customArea.normalizedRect`는 선택한 화면의 현재 visible frame을 기준으로 한 `x`, `y`, `width`, `height`의 `0...1` 정규화 사각형이다.
- 사용자 지정 영역은 펫 전체가 들어갈 수 있는 실제 원점 범위로 축소해 사용한다. 너무 작은 영역은 중앙의 한 원점으로 안전하게 축소한다.
- 저장된 화면을 찾지 못하면 실행 중에는 모든 사용 가능 화면으로 폴백하되 저장된 화면과 영역 선택을 자동 삭제하지 않는다.
- 위치 고정에는 `movementBoundary`를 적용하지 않는다. 마우스 따라가기와 자유 이동의 목표 좌표에만 적용한다.
- 이동 범위, 투명도와 픽셀 아트 표시는 기기별 전역 표시 환경이며 `BehaviorProfile`, `.monglepet`과 `recommended-profile.json`에 포함하지 않는다.

schema-v3에서 v4로 마이그레이션할 때 기존 overlay 값과 모든 펫 프로필을 그대로 유지하고 위 필드의 기본값만 추가한다. 기존 schema-v4의 선택 필드 `pixelArtRendering`이 없으면 `false`로 읽고 다음 저장부터 명시한다. 변환과 원자적 저장이 모두 성공한 경우에만 v4 파일로 교체한다.

## schema-v5 방향별 이동 애니메이션

schema-v5는 schema-v4의 `cursorFollowingMotionID`와 `freeRoamingMotionID`를 각각 `cursorFollowingAnimation.fallbackMotionID`와 `freeRoamingAnimation.fallbackMotionID`로 옮기고, 마우스 따라가기와 자유 이동에 독립된 방향별 참조를 추가한다.

- 새 설정과 마이그레이션된 설정의 기본값은 `usesDirectionalMotions: false`, `usesDiagonalMotions: false`다.
- 방향별 기능을 켜면 상·하·좌·우를 사용하고, `usesDiagonalMotions`를 켠 경우에만 네 대각선을 추가한다.
- 방향 참조가 `null`이면 해당 방향 picker의 `자동 선택`으로 해석한다. 별도의 사용 여부 필드는 두지 않는다.
- 자동 선택은 실제 이동과 같은 쪽을 향하는 사용 가능 방향 중 각도가 가장 가까운 애니메이션을 사용한다. 반대 축을 포함한 방향과 정규화한 일치도가 5% 이하인 미세 축은 제외한다.
- 적합한 사용 방향이 없으면 `fallbackMotionID`, 이것도 없거나 현재 펫에서 찾을 수 없으면 기존 행동 애니메이션을 유지한다.
- 방향 모션 ID는 각각 독립적으로 복구한다. 한 방향의 잘못된 문자열 때문에 같은 모드의 다른 참조나 전체 프로필을 버리지 않는다.
- 애니메이션 이름을 바꾸면 마우스 따라가기와 자유 이동의 fallback·방향 참조를 함께 바꾸고, 삭제하면 일치하는 참조만 `null`로 해제한다. schema-v6에서는 같은 규칙을 도망가기 애니메이션까지 확장한다.

schema-v4에서 v5로 마이그레이션할 때 overlay, 행동 루틴, 자동 규칙과 이동 수치는 그대로 유지한다. 기존 두 단일 이동 모션은 각 모드의 fallback으로 보존하고 방향별 기능은 끈다. 변환과 원자적 저장이 모두 성공한 경우에만 v5 파일로 교체한다.

## schema-v6 마우스 도망가기

schema-v6는 `cursorAvoiding` 이동 모드와 평상시 행동, 감지 거리, 도망 속도 및 독립 방향 애니메이션을 추가한다.

- 포인터 거리는 패널 전체가 아니라 펫 표시 사각형까지의 최단 거리로 계산한다.
- 감지 거리 안에서는 포인터 반대 방향을 우선해 이동하고, 설정 범위에 막히면 허용 후보 중 포인터에서 가장 먼 원점을 선택한다.
- 해제 거리는 감지 거리보다 크게 런타임에서 계산하며 별도 저장하지 않는다.
- 평상시 `stationary`는 포인터가 멀면 현재 위치를 유지한다. `freeRoaming`은 기존 자유 이동 속도·정지 반경·대기 시간·창 선호와 `freeRoamingAnimation`을 재사용한다.
- 도망 중에는 `cursorAvoidingAnimation`을 사용하며 도착·해제 뒤 선택한 평상시 행동으로 돌아간다.
- 도망가기 모드에서 쓰다듬기 설정값은 삭제하지 않지만 감지 및 실행하지 않는다. 클릭 통과와 겹침 투명화는 전역 표시 설정으로 계속 적용한다.
- 애니메이션 이름 변경·삭제는 세 이동 애니메이션의 fallback과 모든 방향 참조를 함께 갱신한다.

schema-v5에서 v6로 마이그레이션할 때 기존 overlay, 프로필, 행동, 자동 규칙과 모든 이동 설정을 유지한다. 도망가기에는 `stationary`, 160pt, 320pt/s와 비어 있는 방향 애니메이션을 추가한다. 변환과 원자적 저장이 모두 성공한 경우에만 v6 파일로 교체한다.

## schema-v7 펫별 말풍선

schema-v7은 각 `behaviorProfiles[]`에 `speech`를 추가한다.

- `isEnabled`는 해당 펫의 말풍선 사용 여부다.
- `periodicIntervalMilliseconds`는 5,000~3,600,000ms이며 기본값은 60,000ms다.
- `phrases`는 최대 100개다. 각 대사는 고유 UUID, 앞뒤 공백을 제거한 1~120자 텍스트, 1,000~30,000ms 표시 시간과 조건을 가진다.
- 조건 `periodic`은 `sequenceID`가 없고, 조건 `sequence`는 같은 프로필에 존재하는 행동 루틴 ID를 참조해야 한다.
- 잘못된 간격은 기본값으로 복구하고 잘못된 UUID·텍스트·표시 시간·조건·루틴 참조는 해당 대사만 제외한다.
- 행동 루틴 삭제 시 그 ID를 참조하는 대사도 함께 제거한다.

schema-v6에서 v7로 마이그레이션할 때 기존 필드를 모두 유지하고 각 프로필에 `isEnabled: false`, 60초와 빈 대사 목록을 추가한다. 전체 변환과 원자적 저장이 성공한 경우에만 v7 파일로 교체한다.

## schema-v8 펫별 말풍선 테마

schema-v8은 각 `speech`에 데이터 전용 `theme`을 추가한다.

- `colorStyle`은 `system`, `cream`, `midnight`, `mint`, `peach`, `custom` 중 하나다.
- 사용자 지정 배경·글자 색상은 각각 0~1 범위의 유한한 sRGB `red`, `green`, `blue` 값으로 저장한다.
- `custom` 색상은 일반 텍스트 기준 4.5:1 이상의 대비를 만족해야 한다. 읽을 수 없는 저장값은 배경에 더 적합한 검정 또는 흰색 글자로 복구한다.
- `backgroundOpacity`는 0.65~1.0, 기본값 0.96이다.
- `fontSize`는 11~24pt, 기본값 14pt다.
- `contentPadding`은 6~24pt, 기본값 12pt다.
- `cornerRadius`는 0~28pt, 기본값 14pt다.
- `showsTail`은 말풍선 꼬리 표시 여부이며, `tailAlignment`는 `leading`, `center`, `trailing` 중 하나다.
- 화면 위쪽 공간에 따라 실제 말풍선이 펫 위 또는 아래로 이동하면 꼬리도 펫을 향하는 위·아래 변으로 자동 전환한다.

schema-v7에서 v8로 마이그레이션할 때 기존 표시와 가까운 시스템 색상, 14pt, 기본 여백·모서리와 꼬리 없음으로 이관한다. 기존 대사와 다른 펫별 설정은 모두 유지한다.

## schema-v9 행동 대사 우선순위와 독립 주기 대사

schema-v9는 기존 `speech`에 주기 대사의 독립 사용 여부와 순서, 행동 전환 정책 및 대사별 표시 방식을 추가한다.

- `periodicIsEnabled`는 전체 말풍선과 별개인 주기 대사 사용 여부다.
- `periodicOrder`는 `random` 또는 `sequential`이다.
- `behaviorChangePolicy`는 새 행동에 연결된 대사가 없을 때 현재 말풍선을 닫는 `dismiss` 또는 유지하는 `keep`이다.
- 각 대사의 `displayMode`는 설정 시간 뒤 숨기는 `timed` 또는 다음 대사까지 유지하는 `untilNextPhrase`다. 호환 검증을 위해 유지형 대사도 유효한 표시 시간을 보존한다.
- 실제 행동 루틴 진입 대사가 주기 대사보다 항상 우선한다. 같은 행동이 유지되거나 이동·쓰다듬기 애니메이션만 바뀐 경우에는 다시 표시하지 않는다.
- 시간 지정 주기 대사는 숨은 시점부터 전체 간격을 다시 기다리고, 유지형 주기 대사는 표시된 시점부터 간격을 계산해 다음 대사로 교체한다.

schema-v8에서 v9로 마이그레이션할 때 주기 조건 대사가 하나 이상 있으면 `periodicIsEnabled: true`로 설정한다. 기존 대사는 모두 `timed`, 주기 순서는 `random`, 행동 전환 정책은 `dismiss`로 이관하며 나머지 설정과 테마를 유지한다.

## schema-v10 펫별 말풍선 상대 배치

schema-v10은 기존 `speech`에 시각 테마와 분리된 `placement`를 추가한다.

- `preferredPosition`은 화면 여유에 따라 위·아래를 고르는 `automatic`, 위를 우선하는 `above`, 아래를 우선하는 `below` 중 하나다. 선택한 쪽의 공간이 부족하면 반대쪽 또는 visible frame 안의 안전한 위치로 복구한다.
- `horizontalOffset`은 펫 중심을 기준으로 한 좌우 이동값이며 -160~160pt, 기본값 0pt다.
- `gap`은 펫과 말풍선 몸체 사이 간격이며 0~64pt, 기본값 8pt다. 꼬리를 표시하면 기본 꼬리 길이에 이 값을 더해 꼬리 끝을 펫에 연결하고, 꼬리를 숨기면 같은 값만큼 빈 공간을 둔다.
- 위치는 화면 절대 좌표가 아니라 펫 기준 상대값으로 저장하므로 펫이 이동하거나 다른 화면으로 넘어가도 함께 이동한다.
- 좌우 이동이나 화면 경계 보정이 발생하면 실제 말풍선 위치에서 펫을 향하도록 꼬리 기준점을 보정한다. 보정이 필요하지 않으면 사용자가 선택한 꼬리 정렬을 유지한다.

schema-v9에서 v10으로 마이그레이션할 때 `automatic`, 좌우 0pt, 간격 8pt를 추가하며 기존 말풍선 대사·정책·테마와 다른 펫별 설정을 유지한다.

## schema-v11 멀티펫 저장 계약

schema-v11은 설치된 펫 콘텐츠와 화면에 표시되는 활성 펫을 분리한다. macOS 저장소와 Domain은 schema-v11을 현재 형식으로 사용하며 schema-v1~v10 파일을 읽으면 v11로 원자적으로 마이그레이션한다. 아래 JSON은 기존 v10 행동 프로필의 세부 필드를 생략한 식별자·인스턴스 구조 예시다.

```json
{
  "schemaVersion": 11,
  "selectedPetInstanceID": "22222222-2222-2222-2222-222222222222",
  "activePetInstances": [
    {
      "instanceID": "22222222-2222-2222-2222-222222222222",
      "petKey": {
        "type": "installed",
        "installationID": "11111111-1111-1111-1111-111111111111"
      },
      "nickname": "몽글이 2",
      "presentation": "awake",
      "overlay": {
        "screenIdentifier": null,
        "originX": 0,
        "originY": 0,
        "width": 192,
        "clickThrough": false,
        "opacity": 1.0,
        "pointerOverlapFadeEnabled": false,
        "pointerOverlapOpacity": 0.2,
        "pixelArtRendering": false,
        "movementBoundary": {
          "mode": "allDisplays",
          "screenIdentifier": null,
          "normalizedRect": null
        }
      },
      "behaviorProfileID": "33333333-3333-3333-3333-333333333333",
      "displayOrder": 0
    }
  ],
  "behaviorProfiles": [
    {
      "profileID": "33333333-3333-3333-3333-333333333333",
      "petKey": {
        "type": "installed",
        "installationID": "11111111-1111-1111-1111-111111111111"
      }
    }
  ]
}
```

- `instanceID`는 화면에 표시되는 펫 하나의 안정적인 UUID다. 같은 설치 펫을 여러 번 추가해도 항상 새 값을 사용한다.
- `selectedPetInstanceID`는 설정에서 편집하는 대상을 가리키며 유일한 실행 펫을 뜻하지 않는다.
- `petKey`는 내장 펫 또는 로컬 `installationID`를 가리킨다. 패키지 ID나 웹 게시물 ID를 실행 인스턴스 식별자로 사용하지 않는다.
- `nickname`은 선택적인 사용자 구분 이름이다. 값이 없으면 펫 원본 이름을 표시하며 원본 metadata는 변경하지 않는다.
- `presentation`, `overlay`, 이동·행동·말풍선을 담은 행동 프로필은 인스턴스마다 독립적이다.
- `behaviorProfileID`는 같은 문서의 행동 프로필 UUID를 참조한다. 행동 프로필은 기존 `petKey`도 유지해 활성화되지 않은 v10 프로필을 새 인스턴스의 설정 템플릿으로 다시 사용할 수 있게 한다.
- `displayOrder`는 사용자가 정하는 앞뒤 순서다. 마지막 클릭·쓰다듬기·드래그로 자동 변경하지 않는다.
- UUID 중복, 존재하지 않는 프로필 참조와 잘못된 선택 참조는 항목 단위 복구 대상으로 다루며 손상 배열로 창을 만들기 전에 검증한다.
- 같은 행동 프로필을 둘 이상의 활성 인스턴스가 참조하면 두 번째 인스턴스부터 독립 프로필 사본을 만들어 설정 변경 전파를 막는다.
- `nickname`은 앞뒤 공백이 없는 1~80자이며 잘못된 값은 원본 펫 이름을 사용하는 `null` 또는 안전한 길이로 복구한다.
- `displayOrder`는 파일에 적힌 순서와 값을 안정적으로 정렬한 뒤 중복·간격을 0부터 연속된 값으로 복구한다.
- 제품 UI에는 활성 펫 마릿수 상한을 두지 않는다. 파일 크기 5MiB와 인스턴스·프로필 각각 10,000개 검증은 손상되거나 조작된 설정 파일이 창을 무제한 생성하지 못하게 하는 기술적 방어 경계다.

schema-v10에서 v11으로 마이그레이션할 때 현재 선택 펫을 새 `instanceID`의 첫 활성 인스턴스로 만들고 기존 표시 상태와 overlay를 그대로 옮긴다. 선택 펫의 기존 프로필에는 새 `profileID`를 부여해 연결한다. 선택 펫 프로필이 없으면 시스템 `기본` 루틴을 가진 새 프로필을 만들며, 선택되지 않았던 나머지 펫 프로필도 각각 새 UUID를 부여해 삭제하지 않고 보존한다.

비정상 종료 복구 marker는 자주 바뀌는 실행 journal이므로 `settings.json`과 분리한다. journal에는 현재 복원 중인 `instanceID`와 정상 종료 여부만 기록하며 행동·대사·사용자 활동 내용은 기록하지 않는다. 구체적인 파일명과 원자적 갱신 방식은 안전 시작 구현 단계에서 확정한다.

## 자동 규칙 조건

앱 조건:

```json
{
  "type": "application",
  "bundleIdentifier": "com.example.Editor"
}
```

`bundleIdentifier`는 schema 호환을 위해 유지하는 앱 조건 문자열 필드다. macOS 로컬 설정은 bundle identifier를 사용하고 Windows 로컬 설정은 packaged 앱의 소문자 `pfn:<package-family-name>` 또는 일반 Win32 앱의 소문자 `exe:<file-name>`을 사용한다. 플랫폼 전용 앱 조건은 다른 플랫폼의 설정이나 권장 프로필로 내보내지 않는다.

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
- 잘못된 이동 enum이나 범위 밖 값은 해당 필드만 기본값으로 복구하고 `SettingsRecoveryIssue.invalidField`를 반환한다.
- 이동 fallback·8방향 참조와 쓰다듬기 애니메이션 ID는 앞뒤 공백이 없는 비어 있지 않은 문자열 또는 `null`이다. 이름 변경 시 같은 펫 프로필의 세 이동 애니메이션 참조를 함께 바꾸고 삭제 시 일치하는 참조를 `null`로 해제한다.
- 말풍선 주기 사용 여부·순서·행동 전환 정책·간격과 대사별 UUID·텍스트·시간·조건·표시 방식, 테마 및 상대 배치 값을 독립적으로 검증하며 하나의 잘못된 값 때문에 같은 펫의 나머지 설정을 버리지 않는다.
- schema-v11은 인스턴스·프로필 UUID, 선택 참조, 프로필 소유권, 펫 키 일치, 별명, 표시 순서, 표시 상태와 overlay를 항목별로 검증한다. 복구할 수 없는 개별 인스턴스만 제외하고 나머지 인스턴스는 유지하며, 모두 제외된 경우 내장 펫 한 마리를 안전 기본값으로 만든다.
- 저장 enum 문자열을 Swift enum 자동 합성 결과에 의존하지 않는다.
- 잘못된 최상위 enum과 overlay 필드는 해당 필드만 기본값 또는 허용 범위로 복구한다.
- 잘못된 행동 단계는 그 단계만 제거하고, 남은 단계가 없는 행동 목록은 제거한다.
- 잘못된 수동 행동 목록 참조는 `null`로 복구한다.
- 컬렉션 상한을 넘는 항목은 저장 순서를 유지한 채 잘라낸다.
- 복구 결과는 `SettingsRecoveryIssue`로 반환하되 사용자 활동 내용은 기록하지 않는다.
- Domain 값을 저장할 때는 자동 복구하지 않고 전체 유효성을 검사해 잘못된 상태의 기록을 거부한다.

## 버전 처리

1. 파일 크기를 확인한 뒤 `schemaVersion`만 먼저 읽는다.
2. macOS 현재 버전 `11`은 인스턴스·프로필 UUID와 참조를 먼저 검증한 뒤 각 overlay, 행동·이동·말풍선 필드를 항목 단위로 복구한다.
3. 버전 `10`은 기존 단일 선택·표시 설정을 첫 활성 인스턴스로 옮기고 모든 행동 프로필을 보존해 v11로 원자적 교체한다.
4. 버전 `9`는 기존 필드를 유지하고 상대 배치 기본값을 추가한 뒤 v10과 v11 변환을 순서대로 적용한다.
5. 버전 `8`은 기존 대사와 테마를 유지하고 주기·전환·표시 정책의 호환 기본값을 추가한 뒤 현재 v11까지 순차 변환한다.
6. 버전 `7`과 `6`은 각 말풍선 호환 기본값을 추가한 뒤 현재 v11까지 순차 변환한다.
7. 버전 `5`부터 `2`까지는 각 버전별 변환을 거쳐 현재 v11까지 순차 변환한다.
8. 버전 `1`은 당시 선택된 펫 정의로 v2 행동 프로필을 만든 뒤 현재 v11까지 순차 변환한다. 전체 변환과 저장이 성공한 경우에만 v11로 교체하며, 필요한 펫 정의를 얻지 못하거나 저장에 실패하면 v1 원본과 쓰기 차단 상태를 유지한다.
9. 현재 앱보다 새로운 버전은 원본을 이동하거나 덮어쓰지 않고 기본값으로 실행하며 저장을 거부한다.
10. 향후 마이그레이션은 버전별 순차 변환과 fixture 기반 단위 테스트를 함께 추가한다.

Windows 구현도 v1부터 v9까지 위 순서의 구조 변환과 원자적 v10 교체를 지원한다. v1의 모션 사이클은 선택 설치 또는 내장 펫 manifest에서 계산하고 선택 펫 정의 자체를 찾을 수 없으면 원본과 쓰기 차단 상태를 유지한다. schema-v10 로더는 overlay, 행동 프로필·루틴·규칙, 이동·방향 모션, 쓰다듬기와 말풍선 정책·대사·테마·배치를 Domain 모델로 변환하고 위 항목 단위 복구 규칙을 적용한다. 전체 Domain 저장은 자동 복구 없이 검증하며 구조 보존 JSON mapper가 살아남은 항목의 알 수 없는 확장 필드를 유지한다. Windows 전용 UI와 런타임 적용은 플랫폼 동등성 후속 범위다.

---

문서 상태: active
스키마 버전: 11
마지막 갱신: 2026-08-13
