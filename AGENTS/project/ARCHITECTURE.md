# MonglePet 아키텍처

## 목표

MonglePet은 상시 실행되는 macOS 앱이므로 제품 규칙, 시스템 감지, 애니메이션 재생, 창 표시와 저장을 분리한다. 핵심 도메인 로직은 운영체제 API 없이 테스트할 수 있어야 한다.

## 기본 구조

```text
MonglePetApp
├── AppCoordinator
├── Domain
│   ├── PetDefinition / Motion
│   ├── BehaviorMode / BehaviorSequence
│   ├── ActivitySnapshot
│   └── BehaviorResolver
├── Activity
│   ├── FrontmostApplicationMonitor
│   ├── IdleTimeMonitor
│   └── SystemSessionMonitor
├── PetLibrary
│   ├── PackageImporter
│   ├── PackageValidator
│   ├── PackageEditor / PackageExporter
│   └── PetLibraryStore
├── Runtime
│   ├── PetRuntime
│   ├── MotionScheduler
│   └── FramePlayer
├── Overlay
│   ├── PetWindowController
│   ├── PetMovementController
│   ├── PetMovementLifecycle
│   ├── PetWindow
│   └── PetView
├── Settings
│   ├── AppSettings / StoredAppSettings
│   ├── AppSettingsMapper
│   ├── AppSettingsStore
│   └── SwiftUI Views
└── MenuBar
    └── MenuBarController
```

실제 소스 디렉터리는 기능 구현이 시작될 때 이 책임 구분을 기준으로 만들며, 내용이 거의 없는 디렉터리를 미리 대량으로 생성하지 않는다.

## 계층 책임

### AppCoordinator

- 앱 시작과 종료 순서를 관리한다.
- 메뉴 막대, 설정 창, 펫 런타임과 시스템 감지기의 생명주기를 연결한다.
- 제품 규칙을 직접 구현하지 않는다.
- 기본 SwiftUI `WindowGroup`에 앱 생명주기를 의존하지 않는다.
- 앱 시작 시 `NSStatusItem`과 펫 오버레이를 구성하고 설정창은 사용자 요청이 있을 때만 연다.

### Domain

- AppKit, SwiftUI, 파일 시스템과 시스템 이벤트 API를 참조하지 않는 순수 Swift 코드다.
- 펫, 모션, 행동 목록, 자동 규칙과 활동 스냅샷을 정의한다.
- `BehaviorResolver`는 현재 모드, 설정과 `ActivitySnapshot`으로 실행할 행동 목록을 결정한다.
- 상세 규칙은 `../specifications/BEHAVIOR_MODEL.md`를 따른다.

### Activity

- 전면 앱, 유휴 시간, 화면 잠금과 절전 상태를 감지한다.
- 전면 앱은 `NSWorkspace` 활성화 알림에서 bundle identifier만 읽고, 유휴 시간은 `CGEventSource`의 모든 입력 이후 경과 시간만 1초 간격으로 확인한다.
- 사용자 세션 비활성화와 화면 수면을 화면 사용 불가 상태로 합쳐 `ActivitySnapshot.isScreenLocked`에 전달한다.
- 화면 사용 불가 또는 시스템 절전 중에는 유휴 polling을 중단하고 복귀 시 즉시 새 snapshot을 만든다.
- 시스템 정보를 `ActivitySnapshot`으로 변환할 뿐 행동을 직접 선택하지 않는다.
- 실제 키 입력이나 화면 내용을 수집하지 않는다.
- snapshot은 메모리에만 유지하고 활동 기록이나 통계를 저장하지 않는다.

### PetLibrary

- 외부 파일 가져오기, 검증, 설치와 제거를 담당한다.
- Codex, GIF/APNG와 PNG 시퀀스 adapter는 호환 입력을 스키마 버전 1 `.monglepet` 디렉터리로 변환하고 기존 로더로 다시 검증한다.
- 호환 adapter가 만든 PNG atlas와 manifest도 일반 패키지와 동일한 설치 경계를 사용하며 런타임에 별도 형식을 노출하지 않는다.
- 패키지는 임시 위치에서 전체 검증한 뒤 앱 라이브러리에 원자적으로 설치한다.
- 사용자 선택 파일의 security-scoped 접근은 검사와 추출 동안만 유지하고 bookmark를 저장하지 않는다.
- App Sandbox의 사용자 선택 파일 권한은 가져오기와 내보내기를 모두 지원하도록 read/write로 제한하며, 선택하지 않은 임의 파일이나 폴더 접근 권한은 추가하지 않는다.
- ZIP 엔트리를 사전 검증한 뒤 개별 추출하며 심볼릭 링크와 경로 충돌을 허용하지 않는다.
- 라이브러리와 같은 볼륨의 staging에서 다시 검증한 뒤 UUID 최종 경로로 rename 또는 replace한다.
- 사용자 펫 편집은 설치 디렉터리에 직접 쓰지 않고 임시 사본을 수정·재검증한 뒤 같은 설치 UUID로 원자적 교체한다.
- 가져온 패키지는 읽기 전용으로 유지하고 사용자가 요청할 때 새 패키지 ID의 편집 가능한 사본을 만든다.
- 공유 내보내기는 편집 marker와 설치 식별자를 제외한 표준 `.monglepet` 아카이브를 생성한다. 사용자가 선택하면 펫 데이터와 분리된 버전 지정 `recommended-profile.json`에 공유 가능한 행동·이동 권장 설정을 추가한다.
- 상세 형식과 보안 제한은 `../specifications/PET_PACKAGE.md`를 따른다.

### Runtime

- `PetBehaviorRuntime`은 `BehaviorResolver`의 결정과 `MotionScheduler` 상태를 실제 `FramePlayer` 재생으로 연결한다.
- `MotionScheduler`는 선택된 행동 목록을 시간에 따라 진행한다.
- 행동 단계는 선택 애니메이션의 전체 사이클을 `repeatCount`회 재생하고 일반 행동 변경은 현재 사이클 경계에서 적용한다.
- 상호작용은 즉시 시작해 기존 행동 단계의 남은 시간을 보존하고, 완료 후 같은 위치로 복귀한다.
- 자동 이동 컨트롤러가 `moving`을 보고하면 모드별 선택 이동 애니메이션을 행동 위에 일시적으로 표시한다. 일회성 상호작용이 이동 표시보다 우선하고, 도착하면 기존 행동 단계의 진행 위치로 복귀한다.
- 스케줄러는 wall clock을 직접 읽지 않고 monotonic clock에서 계산된 경과 `Duration`만 입력받는다.
- `FramePlayer`는 모션 프레임만 렌더링하며 자동·수동 모드 같은 제품 규칙을 알지 못한다.
- 행동 단계 진행은 지속 polling하지 않고 현재 사이클의 남은 시간에 맞춘 일회성 main run loop timer를 사용한다.
- 프레임별 `duration`이 재생 속도의 단일 원본이며 행동 단계에는 별도 배속을 저장하지 않는다.
- 같은 행동이 유지될 때 불필요하게 재시작하지 않는다.

### Overlay

- 투명하고 테두리가 없는 non-activating `NSPanel`을 사용한다.
- 창 활성화 없이 펫을 표시하고 다른 앱의 키 윈도우 상태를 빼앗지 않는다.
- 일반 앱 위에 표시하되 화면 보호기와 화면 잠금보다 높은 창 레벨은 사용하지 않는다.
- `.canJoinAllSpaces`와 `.fullScreenAuxiliary`에 해당하는 동작을 지원한다.
- 위치, 크기, 창 레벨, Space 동작과 클릭 통과를 관리한다.
- SwiftUI 설정 화면과 펫 렌더링 창의 책임을 분리한다.
- 화면 구성 변경 시 패널 전체가 모든 디스플레이 밖으로 벗어나지 않도록 위치를 보정한다.
- `PetMovementController`는 위치 고정, 마우스 따라가기와 자유 이동 상태를 관리하며 행동 결정과 애니메이션 선택을 직접 소유하지 않는다.
- `PetMovementController`는 비고정 모드이면서 이동 허용 상태일 때만 일회성 main run loop timer를 예약한다. 이동 중에는 약 33ms, 정지한 커서 감시는 100ms, 입력 환경을 얻지 못한 재시도는 1초 간격을 사용하고 자유 이동 도착 후에는 고빈도 tick 대신 설정된 대기 timer 하나만 유지한다.
- 좌표가 실제 변한 tick만 `PetMovementActivity.isMoving`을 보고하고 150ms 정지 히스테리시스 뒤 정지로 전환한다. 활동에는 모드별 선택 애니메이션 ID를 함께 전달하되 미지정이면 `nil`로 보고해 기존 행동 표시를 유지할 수 있게 한다.
- `PetMovementGeometry`는 AppKit과 화면 API를 참조하지 않는 `Double` 기반 좌표·크기·화면·창 모델로 안전한 원점 범위, 커서 목표, 자유 이동 목표와 속도 보간을 계산한다. 내부 좌표는 좌하단 원점을 사용하며 Core Graphics 창 좌표 변환은 시스템 provider 경계에서 한 번만 수행한다.
- 마우스 따라가기는 현재 포인터 위치를 메모리에서만 읽고, 자유 이동은 안전한 화면 영역 안에서 목표를 만들며 선택적으로 전면 앱의 대표 창 주변을 선호한다.
- 전면 앱 창 탐색은 `NSWorkspace`의 PID와 `CGWindowListCopyWindowInfo`의 소유 PID·layer·alpha·bounds만 사용한다. 창 제목과 내용은 읽지 않으며 같은 PID 조회는 기본 1초 동안 캐시한다.
- 대표 창은 화면에 보이는 일반 layer 창 중 가시 면적이 가장 큰 창으로 고르고, 전체 화면에 가까운 창·유효한 창 없음·조회 실패는 현재 화면의 `visibleFrame` 목표로 복구한다. 정확한 접근성 창 추적은 초기 범위에 포함하지 않는다.
- `PetWindowController`는 현재 패널 원점·크기와 자동 이동 원점 적용 adapter만 제공한다. 자동 이동으로 바뀐 원점은 사용자 드래그 완료 callback을 발생시키지 않는다.
- `PetMovementLifecycle`은 깨움, 잠금·절전, 사용자 드래그와 macOS 동작 줄이기 상태를 하나의 이동 허용 값으로 합친다. 이 조건이 꺼지면 예약 timer와 이동 상태를 즉시 중지한다.
- 디스플레이 구성이나 펫 크기가 바뀌면 대표 창 캐시와 자유 이동 목표를 무효화하고 현재 화면 환경에서 다시 계산한다.

### Settings

- `AppSettings` Domain 모델과 현재 schema-v3 `StoredAppSettingsV3`, 마이그레이션 전용 schema-v1·v2 DTO를 분리한다.
- `AppSettingsV3Mapper`가 명시적 행동·이동 enum 문자열, 펫 키 discriminator와 반복 횟수를 변환하고 프로필·항목 단위 복구 결과를 만든다.
- v1 마이그레이터는 선택 펫의 실제 프레임 사이클을 사용해 유지 시간을 반복 횟수로 변환하고, v2 마이그레이터는 각 펫 프로필에 기본 위치 고정 이동 설정을 추가한다. 전체 순차 변환이 성공한 v3 결과만 원자적으로 기록한다.
- `AppSettingsStore`는 5MiB 상한, 같은 디렉터리 임시 파일과 원자적 교체를 책임진다.
- `AppSettingsSession`은 저장소의 로드·복구·쓰기 상태를 SwiftUI와 `AppCoordinator`에 전달하고 유효한 Domain 설정 변경만 저장한다.
- 손상 파일은 격리하고 기본값으로 복구하며, 미래 스키마 파일은 원본을 보존하고 쓰기를 차단한다.
- 설정 UI는 파일 시스템이나 저장 DTO에 직접 결합하지 않고 Domain 설정을 통해 저장소와 연결한다.
- 펫별 이동 설정은 일반·행동 설정과 분리된 `이동` 탭에서 편집한다. 모드 변경과 토글은 즉시 저장하고 연속 슬라이더는 런타임에 즉시 반영하되 조작이 끝날 때 한 번만 저장한다.
- 위치 고정 모드에서는 overlay 적용 후 실제 보정된 좌표와 디스플레이 UUID를 설정 세션에 동기화하고 드래그 완료·디스플레이 구성 변경 시 저장한다. 비고정 모드에서는 최초 기준 위치와 사용자 드래그 위치만 저장하고 자동 이동·화면 보정 좌표는 저장하지 않는다.
- 행동 모드, 수동 선택, 행동 루틴과 자동 규칙을 내장 펫 예약 키 또는 설치 UUID별 `BehaviorProfile`로 저장한다.
- 이동 모드, 속도·거리·반경과 마우스 따라가기·자유 이동 중 선택 애니메이션 같은 공유 가능한 이동 설정도 펫별 프로필로 저장한다. 사용자가 드래그한 고정 위치는 앱 오버레이 설정으로 유지하고 자동 이동 중 좌표는 저장하지 않는다.
- 펫 패키지 교체는 같은 설치 UUID의 행동 프로필을 유지하고, 별도 사본 설치는 새 기본 프로필을 만든다.
- 펫 삭제 시 해당 설치 UUID의 행동 프로필도 사용자 확인 후 제거한다.
- 설치 폴더 누락이나 손상으로 펫을 찾지 못한 경우에는 내장 몽글이로 안전하게 전환하되 연결이 끊긴 행동 설정을 보존한다. 프로필 정리는 앱의 명시적 삭제 이벤트에서만 수행한다.
- 로컬 공유 내보내기는 설치 폴더를 직접 압축하지 않는다. 원본을 다시 검증한 뒤 현재 schema의 `pet.json`과 manifest가 참조하는 미리보기·atlas만 별도 작업 공간에 구성하고 재검증·ZIP 왕복 검증 후 목적지에 원자적으로 기록한다.
- 공유 서비스는 내보내기 작성기 앞에서 현재 설치 패키지를 다시 읽고 제작자·버전·라이선스 검토 결과를 만든다. 명백히 공유 불가한 라이선스를 차단하고, 검토 후 메타데이터가 바뀌면 사용자 확인을 무효화한다.
- 일반 설정은 내장 펫을 내보내기 대상에서 제외하고, 설치 펫의 공유 검토를 통과한 뒤 검증된 아카이브를 메모리 `FileDocument`로 전환해 SwiftUI `fileExporter`에 전달한다. 명령형 AppKit 저장 패널을 직접 생성하지 않는다.
- 공유 권장 프로필은 로컬 `BehaviorProfile`을 그대로 복사하지 않는다. 설치 UUID, 화면 좌표와 현재 상태를 제거하고 패키지 모션 참조를 다시 검증한 별도 DTO를 사용한다.
- 가져오기에서는 펫 설치와 권장 프로필 적용을 분리한다. 새 설치는 사용자가 적용을 선택할 때 편집 가능한 로컬 프로필 사본을 만들고, 기존 설치 교체는 기본적으로 현재 로컬 프로필을 유지한다.

### MenuBar

- AppKit `NSStatusItem`을 사용해 깨우기, 재우기, 설정 열기와 앱 종료를 제공한다.
- 펫 창이 숨겨지거나 클릭 통과 상태여도 복구 경로를 유지한다.
- Dock 아이콘을 표시하지 않는 agent-style 앱 구성을 사용한다.

## 1단계 경계

1단계에서는 오버레이 아키텍처만 검증한다.

- 교체 가능한 투명 PNG 한 장을 표시한다.
- 깨우기, 재우기와 드래그 상태는 실행 중 메모리에서 관리한다.
- 정식 프레임 스케줄러, WebP 아틀라스, 펫 패키지 로더는 2단계에서 추가한다.
- 클릭 통과와 사용자 설정 영구 저장은 설정 UI 단계에서 추가한다.

## 핵심 모델 분리

- `PetDefinition`: 설치된 캐릭터와 사용 가능한 모션 데이터
- `PetInstance`: 화면 위치, 크기와 현재 선택 펫
- `BehaviorProfile`: 특정 내장 펫 또는 설치 UUID에 연결된 모드, 행동 루틴과 자동 규칙
- `PetPresentation`: 화면 표시, 사용자에 의한 숨김, 시스템에 의한 일시 중지
- `BehaviorMode`: 자동 또는 수동 행동 결정 방식
- `BehaviorSequence`: 시간에 따라 재생할 모션 목록
- `ActivitySnapshot`: 자동 행동 판단에 필요한 최소 시스템 상태

MVP에서는 여러 펫 정의를 설치할 수 있지만 화면에는 한 개의 `PetInstance`만 표시한다.

## 의존성 규칙

```text
SwiftUI / AppKit / File System / macOS APIs
                    ↓
         Adapter와 저장소 구현
                    ↓
             Domain 모델
```

- Domain에서 상위 프레임워크 방향으로 의존하지 않는다.
- 시스템 감지기는 런타임이나 UI를 직접 변경하지 않는다.
- UI는 파일 시스템에 직접 쓰지 않고 저장소 인터페이스를 사용한다.
- 설정 스키마와 펫 패키지 스키마에는 각각 독립적인 버전 번호를 둔다.
- 시간 기반 로직에는 주입 가능한 monotonic clock을 사용한다.

## 저장 구조

SwiftData나 Core Data를 사용하지 않고 JSON 설정과 파일 기반 펫 라이브러리로 시작한다.

```text
~/Library/Application Support/MonglePet/
├── Library/
│   └── <installation-uuid>/
│       ├── pet.json
│       ├── preview.png
│       └── assets/
└── settings.json
```

- 설정 저장은 임시 파일 작성 후 교체하는 원자적 방식을 사용한다.
- `settings.json`에는 명시적인 `schemaVersion`을 둔다.
- 손상된 설정은 `settings.corrupt-<UUID>.json`으로 격리하고 안전한 기본값으로 복구한다.
- 현재 앱보다 새로운 설정 스키마는 원본 보존을 위해 해당 실행의 저장을 차단한다.
- 패키지 원본이 아니라 검증 후 앱 라이브러리로 복사한 파일을 재생한다.

---

문서 상태: draft
마지막 갱신: 2026-07-23
