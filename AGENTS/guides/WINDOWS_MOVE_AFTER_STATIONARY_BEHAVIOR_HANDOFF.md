# Windows 평상시 행동 완료 후 이동 인계

## 목적

macOS에서 확정한 자유 이동 시간 방식 `행동 완료 후`를 Windows 네이티브 Domain·저장·WinUI·런타임에 같은 사용자 결과로 구현한다. Windows C# 구현은 Windows 환경에서 진행하며 Swift 구조를 직역하지 않는다.

기준 결정은 `AGENTS/project/DECISIONS.md`의 D-120, 공통 동작은 `AGENTS/specifications/BEHAVIOR_MODEL.md`, 저장 계약은 `AGENTS/specifications/SETTINGS_SCHEMA.md`와 `AGENTS/specifications/PET_PACKAGE.md`를 따른다.

## 확정된 사용자 결과

- 자유 이동과 `마우스 도망가기 > 평상시 행동: 자유 이동`의 시간 방식에 `고정`, `랜덤`, `행동 완료 후`를 표시한다.
- 두 이동 방식은 각자의 시간 방식을 독립 저장한다.
- `행동 완료 후`를 선택하면 목표에 도착한 뒤 현재 평상시 행동의 진행 중인 한 회차가 끝나자마자 다음 목표로 이동한다.
- 고정 평상시 행동은 현재 회차의 남은 단계와 단계별 반복을 완료한다.
- 랜덤 평상시 행동은 현재 shuffle bag 항목 한 번을 완료하며 행동 내부 단계 순서를 섞지 않는다.
- 다음 이동이 시작될 때 D-106의 랜덤 전환 규칙을 그대로 적용한다. 현재 랜덤 cursor를 폐기하고 다음 bag 항목을 첫 단계·첫 cycle로 준비한다.
- 마우스 도망가기에서 포인터가 감지 범위에 들어오면 행동 완료 대기를 취소하고 즉시 도망간다.
- 재생 가능한 평상시 행동이 없거나 완료 신호를 받을 수 없으면 500ms 뒤 다음 이동을 시작한다. 빠른 무한 재시도는 만들지 않는다.
- 조건 규칙과 이동의 사용자 우선순위, 실제 이동 중 이동 행동 반복, 쓰다듬기 우선순위는 변경하지 않는다.

## 공통 저장 계약

### 로컬 설정 schema-v16

`freeRoaming`과 `cursorAvoiding.idleFreeRoaming`에 다음 필드를 각각 저장한다.

```json
{
  "dwellMode": "fixed | random | behaviorCompletion",
  "dwellMilliseconds": 8000,
  "dwellMinimumMilliseconds": 2000
}
```

- v15 `randomizesDwell: false` → `dwellMode: fixed`
- v15 `randomizesDwell: true` → `dwellMode: random`
- 시간 값과 다른 이동·행동·표시 설정은 그대로 보존한다.
- 새 저장에는 `randomizesDwell`을 쓰지 않는다.
- v17 이상은 기존 미래 schema 보호 정책으로 원본을 보존하고 쓰기를 막는다.

### 제작자 설정 schema-v12

- `recommended-profile.json`의 같은 두 위치에 `dwellMode`를 기록한다.
- v1~v11 읽기를 유지한다. v11의 `randomizesDwell`은 위와 같이 변환한다.
- v12 내보내기·가져오기는 자유 이동과 도망가기 평상시 자유 이동의 서로 다른 값을 보존한다.
- 미래·손상 제작자 설정은 D-118대로 안전한 최소 프로필 fallback을 사용하고 안전한 펫 자산 설치는 계속한다.
- `.monglepet`의 `pet.json.formatVersion`은 변경하지 않는다.

## Windows 구현 경계

1. Domain에 문자열 저장값과 분리된 `Fixed`, `Random`, `BehaviorCompletion` enum을 둔다.
2. v15 DTO는 그대로 두고 v16 DTO·mapper와 v15→v16 migrator를 추가한다.
3. 제작자 설정 v11 DTO는 그대로 두고 v12 codec을 추가한다.
4. 이동 runtime은 목표 도착 시 timer 또는 행동 완료 event 중 하나를 기다리는 명시적 상태를 사용한다.
5. 행동 runtime은 현재 평상시 행동 한 회차의 완료 횟수나 generation을 노출한다. 33ms 이동 tick에서 행동 상태를 polling하지 않는다.
6. 이동 대기를 요청한 뒤 조건 규칙·재우기·잠금·절전·설정 변경·펫 교체로 문맥이 바뀌면 이전 완료 event를 취소하거나 generation으로 무시한다.
7. 도망가기 포인터 감지는 대기 중에도 기존 저빈도 주기로 계속하며 감지 시 대기를 취소한다.
8. WinUI는 macOS와 같은 정보 순서와 문구를 사용하되 Windows 네이티브 `RadioButtons` 또는 충분한 너비의 선택 UI를 사용한다.
9. `행동 완료 후` 선택 시 숨은 고정·랜덤 시간 값은 지우지 않는다. 다른 방식으로 돌아오면 기존 값을 복원한다.
10. 설정 요약·내보내기 검토·가져오기 검토에는 `현재 평상시 행동 완료 후`처럼 사용자 문구로 표시하고 내부 enum 값을 노출하지 않는다.

## 자동 테스트

- v15 false/true → v16 fixed/random 마이그레이션
- v16 두 이동 설정의 서로 다른 dwell mode 왕복
- v11 제작자 설정 읽기와 v12 세 enum 왕복
- 알 수 없는 enum의 항목 복구 및 미래 schema 보호
- 고정 행동 중간에서 대기 요청 후 전체 회차 경계에 한 번만 이동 시작
- 랜덤 행동 완료 시 자동 다음 행동 표시 전에 이동 시작, 이동 종료 후 다음 bag 항목 첫 프레임
- 재생 불가 행동 500ms fallback
- 도망가기 대기 중 포인터 접근의 즉시 취소·도망
- 규칙 우선순위가 이동보다 높을 때 좌표 정지, 낮을 때 기존 이동 유지
- 설정 변경·재우기·잠금·절전 뒤 늦은 완료 event 무시
- 로컬·웹 가져오기, 사본, 내보내기에서 두 dwell mode 독립성
- Debug·Release 전체 테스트와 두 구성 빌드

## 실제 QA

- 길이가 다른 고정·랜덤 행동에서 목표 도착 후 현재 행동이 잘리지 않고 다음 이동이 시작되는지 확인한다.
- 행동 단계 반복 횟수를 늘렸을 때 그 한 회차만큼 기다리는지 확인한다.
- 도망가기 평상시 대기 중 포인터를 가까이 가져가 즉시 도망가는지 확인한다.
- 일반 자유 이동과 도망가기 평상시 자유 이동의 시간 방식을 다르게 저장하고 재실행해 독립성을 확인한다.
- macOS v12 패키지를 Windows에서 가져오고 Windows v12 패키지를 macOS에서 가져와 세 방식과 다른 휴대 설정을 비교한다.

## 완료 보고

- Windows 소스 커밋과 적용한 계약 커밋
- v16/v12 mapper·migration 구조
- 행동 완료 event와 늦은 event 무시 방식
- 자동 테스트 개수와 Debug·Release 빌드 결과
- 실제 QA 및 macOS 교차 왕복 결과
- 남은 위험과 `AGENTS/project/PLATFORM_PARITY.md` 갱신 상태

실제 Windows 구현·자동 테스트·QA가 끝나기 전에는 플랫폼 동등 완료로 표시하지 않는다.
