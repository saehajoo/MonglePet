# MonglePet 행동 모델

## 1. 입력과 출력

행동 엔진은 운영체제 API를 직접 호출하지 않는다.

```text
BehaviorConfiguration + ActivitySnapshot + 현재 Runtime 상태
                              ↓
                      BehaviorResolver
                              ↓
                    선택된 BehaviorSequence
                              ↓
                       MotionScheduler
                              ↓
                         현재 Motion
```

## 2. ActivitySnapshot

```swift
struct ActivitySnapshot: Equatable, Sendable {
    let capturedAt: ContinuousClock.Instant
    let idleDuration: Duration
    let frontmostApplicationID: String?
    let isScreenLocked: Bool
    let isSystemSleeping: Bool
}
```

실제 구현에서는 테스트 가능한 시계 추상화를 주입한다. wall-clock 시간 변경이 행동 목록 재생 시간을 흔들지 않도록 경과 시간에는 monotonic clock을 사용한다.

## 3. 핵심 타입

```swift
enum PetPresentation: String, Codable, Sendable {
    case awake
    case tuckedAway
    case suspended
}

enum BehaviorMode: String, Codable, Sendable {
    case automatic
    case manual
}

struct BehaviorStep: Equatable, Sendable {
    let motionID: String
    let repeatCount: Int
}

struct BehaviorSequence: Equatable, Sendable {
    let id: String
    let steps: [BehaviorStep]
    let repeats: Bool
}
```

Domain 모델은 저장 형식에 직접 `Codable`로 연결하지 않는다. 애니메이션 한 사이클은 `PetMotion.frames`의 `duration` 합계이며 행동 단계는 이를 `repeatCount`회 재생한다.

코드의 `LegacyBehaviorStepTiming`은 schema-v1 마이그레이션 입력을 해석하기 위한 호환 경계다. 정상 로드가 끝난 활성 설정과 schema-v2 파일에는 남지 않으며, 새 행동 단계는 항상 `repeatCount` 기반으로 실행한다.

### 저장 DTO

```swift
struct StoredBehaviorStepV2: Codable, Equatable, Sendable {
    let motionID: String
    let repeatCount: Int
}

struct StoredBehaviorSequenceV2: Codable, Equatable, Sendable {
    let id: String
    let steps: [StoredBehaviorStepV2]
    let repeats: Bool
}
```

- 저장 DTO와 Domain 모델 사이의 변환은 저장 계층에서만 수행한다.
- `repeatCount`는 1 이상의 정수여야 한다.
- schema-v1의 `durationMilliseconds`와 `playbackSpeed`는 마이그레이션 입력으로만 읽고 schema-v2에는 기록하지 않는다.
- JSON 필드명과 enum 문자열은 Windows 구현과 공유할 공개 스키마이므로 Swift의 자동 합성 표현에 의존하지 않는다.

## 4. 자동 규칙

```swift
enum RuleCondition: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
    case unsupported(type: String)
}

struct AutomaticRule: Equatable, Sendable {
    let id: UUID
    let isEnabled: Bool
    let priority: Int
    let condition: RuleCondition
    let sequenceID: String
}
```

앱 규칙끼리 겹치지 않지만 향후 조건을 조합할 수 있으므로 명시적인 우선순위를 저장한다.

저장 시 associated-value enum의 자동 `Codable` 표현을 사용하지 않는다. 조건 DTO는 다음처럼 명시적인 discriminator를 사용한다.

```json
{
  "type": "application",
  "bundleIdentifier": "com.example.Editor"
}
```

```json
{
  "type": "idleAtLeast",
  "milliseconds": 120000
}
```

- `priority`가 같으면 설정 파일의 배열 순서를 우선한다.
- `priority` 숫자가 클수록 먼저 평가한다.
- 저장 시 배열 순서를 보존하며 UI에서 순서를 바꾸면 `priority`를 다시 정규화한다.
- 알 수 없는 조건 `type`은 `.unsupported(type:)`로 문자열을 보존하고 규칙 단위로 비활성화하며 설정 복구 결과에 남긴다.
- 행동 결정기는 `.unsupported` 조건을 항상 무시한다.
- 앱 규칙 UI는 실행 중인 일반 앱이나 사용자가 선택한 `.app`에서 bundle identifier를 채울 수 있다. 선택한 앱의 이름·아이콘·경로는 영구 저장하지 않으며 직접 입력은 고급 경로로 유지한다.
- `.idleAtLeast` 도메인 타입과 `idleAtLeast` 저장 discriminator는 호환성을 위해 유지하되 사용자 화면에는 `입력 없음 규칙`으로 표시한다.

## 5. 결정 우선순위

1. `tuckedAway`: 창을 숨기고 스케줄러 정지
2. 화면 잠금 또는 절전: `suspended`, 스케줄러 정지
3. 사용자 상호작용: 일회성 모션 재생 후 이전 위치로 복귀
4. 수동 모드: 수동 행동 목록 유지
5. 활성화된 자동 규칙 중 큰 `priority`
6. 같은 `priority`이면 설정 배열의 앞선 규칙
7. 기본 행동 루틴

- 자동 규칙은 앱·유휴 등 조건 종류에 따른 시스템 고정 우선순위를 두지 않는다.
- 사용자가 지정한 `priority`가 전체 규칙의 평가 순서를 결정한다.

수동 모드는 유휴 시간과 앱 변경을 무시하지만 화면 잠금과 절전 중에는 성능과 개인정보 보호를 위해 렌더링을 중지한다.

## 6. 전환 규칙

- 같은 행동 목록이 다시 선택되면 현재 단계, 완료한 반복 횟수와 현재 사이클의 남은 시간을 유지한다.
- 다른 일반 목록으로 전환할 때 현재 프레임을 즉시 버리지 않고 현재 애니메이션의 한 사이클이 끝나는 경계에서 바꾼다.
- 각 단계는 애니메이션 전체 사이클을 `repeatCount`회 재생하며, 일회성 상호작용만 사이클 경계를 기다리지 않고 즉시 시작한다.
- 일회성 상호작용이 끝나면 중단한 행동 목록의 단계와 남은 시간으로 돌아간다.
- 단계가 예약된 `현재 펫의 기본 애니메이션`을 참조하면 선택 펫 manifest의 기본 애니메이션을 사용한다.
- 패키지에 요청된 애니메이션이 없으면 현재 선택 펫의 기본 애니메이션을 사용한다.
- 선택 펫 자체가 누락되거나 손상된 경우에만 펫 라이브러리 경계에서 내장 몽글이로 복구한다.
- 규칙 경계에서 반복 전환되지 않도록 진입 임계값과 이탈 임계값을 분리한다.

유휴 규칙의 입력 재개 히스테리시스는 3초이며 사용자가 유휴 규칙을 추가한 경우에만 적용한다.

### 이동 방향 표시 계층

자동 이동은 행동 결정을 바꾸지 않고 화면에 표시할 애니메이션만 잠시 덮어쓴다.

- 마우스 따라가기, 자유 이동과 마우스 도망가기는 각각 독립된 공통 fallback과 방향별 애니메이션 설정을 갖는다. 도망가기의 평상시 자유 이동 구간은 자유 이동 애니메이션을 재사용하고 포인터를 피해 움직이는 구간만 도망 애니메이션을 사용한다.
- 목표 좌표가 아니라 실제 적용된 패널 좌표의 `새 원점 - 이전 원점`으로 방향을 분류한다. 화면 전환이나 이동 범위 보정으로 요청 좌표와 결과가 달라도 실제 움직임과 표시가 일치해야 한다.
- 기본 방향별 모드는 좌·우·상·하 4방향이며 사용자가 대각선을 켜면 8방향으로 분류한다.
- 방향 경계에는 초기 8도 히스테리시스를 적용한다. 같은 해석 모션 ID가 유지되면 분류 방향이 바뀌어도 프레임 재생을 다시 시작하지 않는다.
- 선택 순서는 정확한 방향, 실제 이동과 같은 쪽을 향하는 사용 가능 방향 중 각도가 가장 가까운 애니메이션, 모드 공통 fallback이다. 정규화한 방향 일치도가 5% 이하인 미세 축과 실제 이동의 어느 축이라도 반대로 향하는 후보는 자동 선택에서 제외한다. 동률이면 저장 구조의 안정된 순서에 따라 좌·우 기본 방향을 우선한다.
- 해석된 애니메이션이 없거나 현재 펫에 존재하지 않으면 이동 좌표는 계속 갱신하고 현재 행동 표시를 유지한다.
- 화면 표시 우선순위는 일회성 상호작용, 이동 애니메이션, 행동 애니메이션 순이다. 쓰다듬기가 끝났을 때 아직 이동 중이면 최신 이동 애니메이션으로, 도착했다면 중단한 행동 단계의 남은 위치로 복귀한다.
- 이미지 자동 반전, 방향 모션 자동 생성과 펫 manifest 변경은 하지 않는다.

## 7. 상호작용

쓰다듬기는 영구 상태가 아니라 일회성 이벤트다.

- 쓰다듬기 애니메이션은 특정 예약 이름을 사용하지 않고 현재 펫의 애니메이션 중 사용자가 프로필별로 선택한다.
- 선택이 없거나 현재 펫에서 애니메이션을 찾을 수 없으면 행동을 중단하지 않고 입력을 무시한다.
- 현재 프레임의 실제 표시 픽셀에 포인터가 진입해 300ms 이상 머무르면 쓰다듬기 입력을 한 번 만든다.
- 같은 호버 중에는 반복하지 않으며 포인터가 펫 패널 밖으로 이탈한 뒤 다시 진입해야 다음 입력을 받을 수 있다.
- 클릭 통과 여부와 무관하게 동작하며 클릭 자체는 쓰다듬기 입력으로 사용하지 않는다.
- 자동 이동 중에도 포인터가 직접 표시 픽셀에 진입하면 동작한다. 펫 이동이나 애니메이션 프레임 변화로 펫이 정지한 포인터 아래에 들어온 경우와 사용자 드래그 중에는 입력을 만들지 않는다.
- 마우스 도망가기 모드에서는 포인터 접근 자체가 이동 입력이므로 쓰다듬기 감지와 실행을 모두 차단한다. 저장된 쓰다듬기 선택은 보존하며 다른 이동 모드로 돌아가면 다시 사용한다.

```text
현재 focus 목록 4분 20초 지점
→ petting 1회
→ focus 목록 4분 20초 지점부터 계속
```

쓰다듬기 이벤트가 무한히 쌓이지 않도록 재생 중에는 추가 입력을 합치고 짧은 cooldown을 둔다.

초기 cooldown은 500ms이며 설정 UI에 노출하지 않는다.

## 8. 시간 진행 경계

- `ActivitySnapshot.capturedAt`에는 monotonic `ContinuousClock.Instant`를 사용한다.
- `MotionScheduler`는 wall clock을 직접 읽지 않고 상위 runtime이 monotonic clock으로 계산한 경과 `Duration`을 받는다.
- 숨김·잠금·절전 중에는 스케줄러를 pause해 행동 단계, 상호작용과 cooldown 시간이 진행되지 않게 한다.
- 같은 목록 ID를 다시 요청하면 현재 단계와 남은 시간을 보존한다.
- 다른 목록 요청이 여러 번 들어오면 아직 적용되지 않은 대기 목록을 가장 최근 결정으로 교체한다.
- 실제 앱 runtime은 현재 사이클의 남은 시간에 맞춘 일회성 timer만 예약하고 사이클 경계에서 다음 timer를 다시 계산한다.
- 프레임별 `duration`이 재생 속도의 단일 원본이며 새 행동 단계에는 별도 배속이 없다.

### 시스템 기본 행동 루틴

- 첫 실행에는 `기본` 행동 루틴 하나만 제공한다.
- schema-v2 기본 루틴은 `현재 펫의 기본 애니메이션` 1회 단계로 구성하고 루틴 자체를 반복한다.
- 기본 루틴은 최소 실행 상태이므로 삭제할 수 없지만 단계, 반복 횟수와 루틴 반복은 편집할 수 있다.
- 새 사용자 루틴의 첫 단계도 현재 펫 기본 애니메이션 참조로 시작한다.
- 기본 자동 규칙은 만들지 않는다. 앱과 유휴 규칙은 사용자가 명시적으로 추가한다.
- 설정이 비었거나 시스템 기본 루틴이 없으면 실행 중 안전하게 보충하며 다음 설정 변경 시 저장한다.

## 9. Phase 7 목표 모델: 애니메이션 사이클과 펫별 프로필

schema-v1의 `BehaviorStep.duration`과 `playbackSpeed`를 대체하는 사이클 기반 타입은 3단계에서 런타임에 도입했다. 펫별 프로필까지 포함한 최종 타입은 다음과 같다.

```swift
struct BehaviorStep: Equatable, Sendable {
    let motionID: String
    let repeatCount: Int
}

struct BehaviorProfile: Equatable, Sendable {
    let petKey: PetBehaviorKey
    let mode: BehaviorMode
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
}
```

- 프레임별 재생 시간은 펫 패키지의 `MotionFrame.duration`만 원본으로 사용한다.
- 한 행동 단계는 선택한 애니메이션의 전체 프레임을 `repeatCount`회 재생한 뒤 다음 단계로 이동한다.
- `repeatCount` 기본값은 1이며 초 단위 유지 시간과 단계별 재생 속도는 노출하지 않는다.
- 패키지의 기존 `Motion.loop`는 직접 미리보기와 호환 가져오기의 기본 반복 힌트로 보존하되, 행동 루틴 안에서는 단계의 `repeatCount`와 루틴의 `repeats`가 반복을 결정한다.
- 한 단계 루틴을 계속 재생하려면 `BehaviorSequence.repeats`가 전체 루틴을 반복한다.
- 일반 행동 변경은 현재 애니메이션 사이클 경계에서 적용하고, 일회성 상호작용만 즉시 시작한다.
- 애니메이션 수정 화면에서 프레임별 시간을 변경하면 해당 애니메이션을 참조하는 모든 행동 루틴에 다음 재생부터 반영한다.
- 행동 프로필은 내장 펫 예약 키 또는 설치 UUID에 연결한다. 패키지 ID가 같더라도 별도 설치 사본은 다른 프로필이다.
- 선택 펫을 바꾸면 해당 프로필의 모드, 수동 선택, 루틴과 자동 규칙을 함께 활성화한다.
- 기본 공유 패키지는 로컬 행동 프로필을 포함하지 않는다. 사용자가 권장 설정 포함을 명시하면 행동·이동·말풍선 값을 별도 `recommended-profile.json` preset으로 공유할 수 있다.

### 말풍선

- 말풍선 설정은 `BehaviorProfile`에 속하며 내장 펫 예약 키 또는 설치 UUID별로 독립된다.
- 기본값은 사용 안 함과 빈 대사 목록이다. 시스템 고정 대사를 자동 생성하지 않는다.
- 대사 조건은 일정 간격의 `periodic`과 존재하는 행동 루틴 ID를 참조하는 `sequence` 두 종류다.
- 주기 대사는 설정된 간격마다 일회성 timer 하나로 선택하며 가능한 경우 직전 대사의 연속 선택을 피한다.
- 행동 대사는 실제 기본 행동 루틴 ID가 달라졌을 때만 한 번 표시한다. 단계 변경, 이동 애니메이션과 쓰다듬기 상호작용은 조건을 다시 발생시키지 않는다.
- 재우기·잠금·절전 중에는 주기 timer와 현재 말풍선을 즉시 숨기고 표시하지 않는다.
- 행동 루틴을 삭제하면 그 루틴을 참조하는 말풍선 대사도 함께 제거한다.
- 초기 말풍선은 시스템 색상 기반 고정 테마이며 표시용 child panel은 입력을 받지 않는다. 테마 커스텀은 별도 후속 규격에서 다룬다.

schema-v1의 시간 기반 단계는 이전 설정 파일을 읽는 마이그레이션 경계에서만 유지하며 schema-v2에는 저장하지 않는다.

## 10. 테스트 사례

- 수동 모드에서 전면 앱이 바뀌어도 행동 유지
- 화면 잠금은 수동 모드보다 우선해 렌더링 중지
- 등록 앱 진입 시 연결된 행동 목록 선택
- 등록 앱 종료 시 기본 행동 복귀
- 사용자 지정 유휴 시간 경계값
- 입력 재개 시 히스테리시스 적용
- 동일 규칙 스냅샷 반복 시 재생 위치 보존
- 여러 프레임 시간 합계와 `repeatCount`에 따른 단계 이동
- 일반 행동 변경이 현재 사이클 끝에서 적용되는지 확인
- 쓰다듬기 후 이전 단계와 남은 시간 복구
- 표시 픽셀 진입 후 300ms 호버, 동일 호버 1회, 패널 이탈 뒤 재활성화
- 클릭 통과·자동 이동 중 호버 동작과 정지 포인터·드래그 오입력 억제
- 마우스 도망가기 중 쓰다듬기 차단과 다른 이동 모드 복귀 시 설정 보존
- 실제 적용 이동량의 4·8방향 분류, 경계 히스테리시스와 방향→기본 축→공통 fallback
- 방향별 이동 중 쓰다듬기 우선 표시와 완료 후 최신 이동 또는 행동 복귀
- 현재 펫 기본 참조와 없는 애니메이션을 펫 기본 애니메이션으로 대체
- 숨긴 펫은 활동 이벤트에도 깨어나지 않음
- 주기 말풍선의 일회성 timer 재예약, 같은 행동 루틴 중복 억제와 재우기·잠금·절전 중 숨김

---

문서 상태: active
마지막 갱신: 2026-07-30
