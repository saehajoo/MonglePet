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
- `playbackSpeed`의 허용 범위는 설정 명세를 확정할 때 명시한다.
- JSON 필드명과 enum 문자열은 Windows 구현과 공유할 공개 스키마이므로 Swift의 자동 합성 표현에 의존하지 않는다.

## 4. 자동 규칙

```swift
enum RuleCondition: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
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
- 저장 시 배열 순서를 보존하며 UI에서 순서를 바꾸면 `priority`를 다시 정규화한다.
- 알 수 없는 조건 `type`은 규칙 단위로 비활성화하고 설정 복구 로그에 남긴다.

## 5. 결정 우선순위

1. `tuckedAway`: 창을 숨기고 스케줄러 정지
2. 화면 잠금 또는 절전: `suspended`, 스케줄러 정지
3. 사용자 상호작용: 일회성 모션 재생 후 이전 위치로 복귀
4. 수동 모드: 수동 행동 목록 유지
5. 자동 장시간 유휴 규칙
6. 자동 앱별 규칙
7. 자동 짧은 유휴 규칙
8. 기본 행동 목록

수동 모드는 유휴 시간과 앱 변경을 무시하지만 화면 잠금과 절전 중에는 성능과 개인정보 보호를 위해 렌더링을 중지한다.

## 6. 전환 규칙

- 같은 행동 목록이 다시 선택되면 현재 단계와 남은 시간을 유지한다.
- 다른 목록으로 전환할 때 현재 프레임을 즉시 버리지 않고 설정된 전환 지점에서 바꾼다.
- 일회성 상호작용이 끝나면 중단한 행동 목록의 단계와 남은 시간으로 돌아간다.
- 패키지에 요청된 모션이 없으면 `idle`을 사용한다.
- `idle`도 없으면 펫 패키지를 실행 불가 상태로 표시한다.
- 규칙 경계에서 반복 전환되지 않도록 진입 임계값과 이탈 임계값을 분리한다.

초기 유휴 기준:

```text
rest 진입: 2분
rest 이탈: 입력 재개 후 3초
sleep 진입: 10분
sleep 이탈: 입력 재개 후 3초
```

## 7. 상호작용

쓰다듬기는 영구 상태가 아니라 일회성 이벤트다.

```text
현재 focus 목록 4분 20초 지점
→ petting 1회
→ focus 목록 4분 20초 지점부터 계속
```

연속 클릭으로 이벤트가 무한히 쌓이지 않도록 재생 중에는 추가 입력을 합치고 짧은 cooldown을 둔다.

## 8. 테스트 사례

- 수동 모드에서 전면 앱이 바뀌어도 행동 유지
- 화면 잠금은 수동 모드보다 우선해 렌더링 중지
- 등록 앱 진입 시 연결된 행동 목록 선택
- 등록 앱 종료 시 기본 행동 복귀
- 2분과 10분 경계값
- 입력 재개 시 히스테리시스 적용
- 동일 규칙 스냅샷 반복 시 재생 위치 보존
- 쓰다듬기 후 이전 단계와 남은 시간 복구
- 없는 모션을 `idle`로 대체
- 숨긴 펫은 활동 이벤트에도 깨어나지 않음

---

문서 상태: 초안
