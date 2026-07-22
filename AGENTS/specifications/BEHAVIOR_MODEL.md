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
    let duration: Duration
    let playbackSpeed: Double
}

struct BehaviorSequence: Equatable, Sendable {
    let id: String
    let steps: [BehaviorStep]
    let repeats: Bool
}
```

Domain 모델은 저장 형식에 직접 `Codable`로 연결하지 않는다. Swift의 `Duration`을 JSON에 직접 저장하지 않고 저장 계층의 DTO에서 정수 밀리초로 변환한다.

### 저장 DTO

```swift
struct StoredBehaviorStep: Codable, Equatable, Sendable {
    let motionID: String
    let durationMilliseconds: Int64
    let playbackSpeed: Double
}

struct StoredBehaviorSequence: Codable, Equatable, Sendable {
    let id: String
    let steps: [StoredBehaviorStep]
    let repeats: Bool
}
```

- 저장 DTO와 Domain 모델 사이의 변환은 저장 계층에서만 수행한다.
- `durationMilliseconds`는 1 이상의 정수여야 한다.
- `durationMilliseconds`는 최대 86,400,000(24시간)이다.
- `playbackSpeed`의 허용 범위는 0.25–4.0이다.
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

- 같은 행동 목록이 다시 선택되면 현재 단계와 남은 시간을 유지한다.
- 다른 일반 목록으로 전환할 때 현재 프레임을 즉시 버리지 않고 현재 `BehaviorStep`의 `duration`이 끝나는 단계 경계에서 바꾼다.
- 각 단계의 `duration`은 해당 행동을 유지하는 최소 구간이며, 일회성 상호작용만 단계 경계를 기다리지 않고 즉시 시작한다.
- 일회성 상호작용이 끝나면 중단한 행동 목록의 단계와 남은 시간으로 돌아간다.
- 단계가 예약된 `현재 펫의 기본 애니메이션`을 참조하면 선택 펫 manifest의 기본 애니메이션을 사용한다.
- 패키지에 요청된 애니메이션이 없으면 현재 선택 펫의 기본 애니메이션을 사용한다.
- 선택 펫 자체가 누락되거나 손상된 경우에만 펫 라이브러리 경계에서 내장 몽글이로 복구한다.
- 규칙 경계에서 반복 전환되지 않도록 진입 임계값과 이탈 임계값을 분리한다.

유휴 규칙의 입력 재개 히스테리시스는 3초이며 사용자가 유휴 규칙을 추가한 경우에만 적용한다.

## 7. 상호작용

쓰다듬기는 영구 상태가 아니라 일회성 이벤트다.

```text
현재 focus 목록 4분 20초 지점
→ petting 1회
→ focus 목록 4분 20초 지점부터 계속
```

연속 클릭으로 이벤트가 무한히 쌓이지 않도록 재생 중에는 추가 입력을 합치고 짧은 cooldown을 둔다.

초기 cooldown은 500ms이며 설정 UI에 노출하지 않는다.

## 8. 시간 진행 경계

- `ActivitySnapshot.capturedAt`에는 monotonic `ContinuousClock.Instant`를 사용한다.
- `MotionScheduler`는 wall clock을 직접 읽지 않고 상위 runtime이 monotonic clock으로 계산한 경과 `Duration`을 받는다.
- 숨김·잠금·절전 중에는 스케줄러를 pause해 행동 단계, 상호작용과 cooldown 시간이 진행되지 않게 한다.
- 같은 목록 ID를 다시 요청하면 현재 단계와 남은 시간을 보존한다.
- 다른 목록 요청이 여러 번 들어오면 아직 적용되지 않은 대기 목록을 가장 최근 결정으로 교체한다.
- 실제 앱 runtime은 현재 단계의 남은 시간에 맞춘 일회성 timer만 예약하고 단계 경계에서 다음 timer를 다시 계산한다.
- `playbackSpeed`는 프레임 delay를 나누는 값이며 행동 단계의 `duration` 자체는 바꾸지 않는다.

### 시스템 기본 행동 루틴

- 첫 실행에는 `기본` 행동 루틴 하나만 제공한다.
- 기본 루틴은 `현재 펫의 기본 애니메이션` 한 단계로 구성하고 3초 단위로 반복한다.
- 기본 루틴은 최소 실행 상태이므로 삭제할 수 없지만 단계, 시간, 속도와 반복은 편집할 수 있다.
- 새 사용자 루틴의 첫 단계도 현재 펫 기본 애니메이션 참조로 시작한다.
- 기본 자동 규칙은 만들지 않는다. 앱과 유휴 규칙은 사용자가 명시적으로 추가한다.
- 설정이 비었거나 시스템 기본 루틴이 없으면 실행 중 안전하게 보충하며 다음 설정 변경 시 저장한다.

## 9. Phase 7 목표 모델: 애니메이션 사이클과 펫별 프로필

현재 schema-v1의 `BehaviorStep.duration`과 `playbackSpeed`는 Phase 7에서 제거한다. 목표 타입은 다음과 같다.

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
- 공유 패키지는 행동 프로필을 포함하지 않는다.

현재 런타임과 schema-v1의 시간 기반 모델은 Phase 7 구현과 마이그레이션이 완료될 때까지 호환 기준으로 유지한다.

## 10. 테스트 사례

- 수동 모드에서 전면 앱이 바뀌어도 행동 유지
- 화면 잠금은 수동 모드보다 우선해 렌더링 중지
- 등록 앱 진입 시 연결된 행동 목록 선택
- 등록 앱 종료 시 기본 행동 복귀
- 사용자 지정 유휴 시간 경계값
- 입력 재개 시 히스테리시스 적용
- 동일 규칙 스냅샷 반복 시 재생 위치 보존
- 쓰다듬기 후 이전 단계와 남은 시간 복구
- 현재 펫 기본 참조와 없는 애니메이션을 펫 기본 애니메이션으로 대체
- 숨긴 펫은 활동 이벤트에도 깨어나지 않음

---

문서 상태: active
마지막 갱신: 2026-07-22
