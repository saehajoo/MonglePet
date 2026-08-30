# Settings Fixtures

macOS와 Windows가 같은 설정 스키마 변환 결과를 만드는지 검증한다.

- `schema-v10-single-pet.json`: 한 설치 펫과 프로필을 가진 기존 입력
- `schema-v11-single-instance.expected.json`: 고정 instance/profile UUID를 사용한 v11 기대 결과
- `schema-v11-behavior-references.json`: 이동·쓰다듬기가 애니메이션을 직접 참조하는 v11 입력
- `schema-v12-behavior-references.expected.json`: 동일 애니메이션을 하나의 행동으로 승격하고 참조를 재사용하는 v12 기대 결과
- `schema-v13-random-behaviors.json`: 복수 랜덤 행동과 자유 이동 랜덤 머무르기 범위를 가진 v13 교차 플랫폼 왕복 기준
- `schema-v14-stationary-rules.json`: 종전 automatic·manual·random 선택과 활성 규칙을 함께 가진 v14 입력
- `schema-v15-stationary-rules.expected.json`: 평상시 fixed·random 선택과 독립 규칙으로 분리한 v15 기대 결과

v10→v11 UUID 생성 순서는 첫 활성 인스턴스, 저장된 행동 프로필 순서다. fixture의 UUID는 테스트 전용이며 실제 사용자 설정에 재사용하지 않는다.

v11→v12는 UUID를 새로 만들지 않는다. 자동 생성 행동 ID는 애니메이션 ID의 UTF-8 base64url 표현을 `__monglepet_motion_behavior__` 뒤에 붙이며 충돌 시 안정적인 숫자 suffix를 사용한다.

v12→v13은 기존 모드를 유지하며 `randomSequenceIDs: []`, `randomizesFreeRoamingDwell: false`를 추가한다. v13 fixture의 랜덤 행동은 shuffle bag으로 각 항목을 한 번씩 쓰며 머무르기 시간은 목표 도착 때 `minimum...maximum`에서 한 번만 선택한다.

v14→v15는 automatic을 `fixed + null`로 옮겨 규칙 사용 상태를 유지한다. manual은 `fixed + manualSequenceID`, random은 기존 선택 목록으로 옮기며 두 모드에서 휴면 상태였던 규칙은 조건·대상·ID·순서를 보존한 채 비활성화한다. 알 수 없는 확장 필드도 그대로 보존한다.
