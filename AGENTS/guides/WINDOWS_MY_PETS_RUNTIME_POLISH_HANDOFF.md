# Windows 단일 내 펫·행동 1회 재생·말풍선 보정 인계

## 목적

macOS에서 확정한 D-111~D-113의 최종 사용자 결과를 Windows WinUI 3·Win32 overlay 구조에 맞게 구현한다. 이 문서는 작업 중간의 분리형 화면과 보관 상태를 폐기하고 최종 구현 기준만 설명한다. SwiftUI/AppKit 코드를 번역하지 말고 공통 데이터 계약, 확정된 동작과 fixture를 기준으로 한다.

## 기준 문서

- `../project/DECISIONS.md`: D-076, D-106, D-107, D-110, D-111, D-112, D-113
- `../specifications/BEHAVIOR_MODEL.md`
- `../specifications/PET_PACKAGE.md`
- `../specifications/SETTINGS_SCHEMA.md`
- `../project/ARCHITECTURE.md`
- `../project/PLATFORM_PARITY.md`
- `../work_plans/tasks/2026-09-01-my-pets-one-shot-behavior-speech.md`
- `../../apps/windows/AGENTS.md`

## 변경하지 않는 계약

- `.monglepet` formatVersion을 올리지 않는다.
- 권장 프로필은 v11, Windows 로컬 settings는 현재 schema-v15를 유지한다.
- `installationID`, active `instanceID`, `behaviorProfileID`를 합치지 않는다.
- 같은 installation의 이미지·정의는 공유할 수 있지만 overlay, 위치, 표시 상태, 행동·이동·말풍선 설정과 runtime cursor는 instance마다 독립이다.
- Windows의 top-level/child HWND 클릭 통과 복구, Composition frame player와 WinUI 리소스 체계는 유지한다.
- PFN, exe 이름, HWND, DPI, 로컬 경로를 공통 패키지나 권장 프로필에 추가하지 않는다.

## 1. 행동 전체 반복 제거

### 사용자 화면

- 행동 편집의 `마지막 단계 후 처음부터 반복` ToggleSwitch를 제거한다.
- 새 행동 만들기 dialog에서도 같은 토글을 제거한다.
- 행동 단계마다 애니메이션과 `repeatCount`만 편집한다.
- 안내 문구는 “각 단계의 반복 횟수로 행동 길이를 조절합니다. 행동이 끝나면 마지막 프레임을 유지합니다.” 정도로 표시한다.

### Domain·저장 호환

- `BehaviorSequence.repeats`와 저장 JSON의 `repeats` 필드를 삭제하거나 이름을 바꾸지 않는다.
- schema-v1~v15, 권장 프로필 v1~v11과 macOS 내보내기 왕복을 위해 기존 값을 읽고 다시 기록한다.
- 새 행동을 만들 때 저장 기본값은 `false`로 쓴다.
- 기존 `true`를 로드할 때 마이그레이션으로 파일을 즉시 다시 쓰지 않는다.
- 패키지 manifest의 모션 `loop`는 이미지 미리보기 힌트이므로 행동 1회 재생 정책과 분리한다.

### Runtime 결과

- 고정 평상시 행동: 단계 목록을 한 번 통과하고 마지막 단계의 마지막 프레임 유지.
- 앱·입력 없음 규칙 행동: 같은 결과. 동일 규칙 snapshot이 다시 들어와도 재시작 금지.
- 랜덤 평상시 행동: 한 행동을 한 번 통과하면 shuffle bag 다음 행동을 선택하고 첫 단계·첫 cycle·첫 프레임부터 시작.
- 선택 항목이 하나뿐인 랜덤도 완료 뒤 같은 행동을 새 cursor로 첫 프레임부터 시작.
- 쓰다듬기: 한 번 통과하고 기존 중단·복원 의미 유지.
- 이동 행동: 실제 좌표 이동이 유지되는 동안에만 별도 movement scheduler에서 반복. 정지하면 즉시 중단.
- 같은 완료 sequence가 activity polling이나 UI 설정 알림으로 다시 resolve되어도 scheduler의 `Request`가 cursor를 다시 만들면 안 된다.
- 같은 ID라도 단계·반복 횟수·애니메이션이 편집되어 값이 달라졌다면 첫 프레임부터 새로 시작한다.
- D-106의 랜덤 이동 중단 의미와 D-107의 규칙 fallback 의미를 유지한다.

## 2. 단일 `내 펫` 정보 구조

### NavigationView

- 기존 `데스크톱 펫`과 `설치한 펫` 두 navigation item을 사용자 화면의 `내 펫` 하나로 합친다.
- 페이지 내부의 tab 또는 segmented 전환은 두지 않는다.
- 모든 installation은 독립 instance·profile을 가진 하나의 `내 펫`으로 표시한다. `사용 중`, `보관 중` 구역이나 상태를 두지 않는다.
- 페이지 상단에는 `펫 만들기`, `펫 가져오기`를 둔다. 로컬 파일과 웹 URL 가져오기는 같은 가져오기 dialog 안에서 제공한다.
- 각 card에는 선택, 깨우기·재우기, 이름, 앞뒤 순서, 일시정지, `펫 사본 만들기`, `패키지로 내보내기`, `완전히 삭제`를 제공한다.
- 재우기는 instance·profile·installation과 모든 개인 설정을 보존하고 overlay만 숨긴다.
- 완전 삭제는 instance와 전용 profile을 제거한다. 같은 installation을 참조하는 다른 instance가 없으면 installation 파일도 같은 사용자 작업에서 제거한다.
- 내장 펫은 최소 한 instance를 유지하되 중복 내장 instance는 삭제할 수 있다.
- 선택한 active pet의 메타데이터와 애니메이션 추가·수정·복제·삭제는 별도 NavigationView 항목인 `선택한 펫 > 펫 정보·애니메이션`에서 수행한다.
- 사용자가 내부 용어인 installation/profile을 이해해야만 작업할 수 있게 만들지 않는다. 오류 상세 로그가 아닌 일반 안내에는 `콘텐츠`, `독립 설정`, `내 펫`을 사용한다.

### active card와 제거

- 각 card는 instance UUID가 아니라 별칭 또는 펫 표시 이름을 우선 표시한다.
- 같은 콘텐츠의 여러 인스턴스도 별도 card로 표시하고 각각 독립 설정 페이지로 이동할 수 있어야 한다.
- 제거 확인은 크기, 위치, 행동, 이동, 쓰다듬기와 말풍선 설정이 삭제되고 복원되지 않음을 명시한다.
- 삭제 확인은 이미지·애니메이션과 크기·행동·이동·쓰다듬기·말풍선 설정이 복원되지 않음을 명시하고, 나중에 필요하면 먼저 패키지로 내보내도록 안내한다.
- 마지막 card와 마지막 내장 펫 instance 삭제는 비활성화하고 이유를 help/설명에 표시한다.

### 가져오기 결과

- 로컬 파일과 웹 URL은 같은 application service를 사용한다.
- 같은 package ID·slug·이름·버전이어도 항상 새 installation UUID를 만든다.
- 가져오기 검토에서 `기본 설정으로 추가`와 권장 프로필이 유효할 때 `권장 설정으로 추가`를 제공한다.
- 성공하면 새 installation UUID, 새 instance UUID, 새 profile UUID를 만들고 active 목록에 추가한 뒤 선택한다.
- 기존 인스턴스·프로필·선택되지 않은 설치는 변경하지 않는다.
- 권장 설정은 새 profile과 새 instance overlay에만 적용하며 화면 절대 좌표·display ID·Windows 앱 규칙은 휴대하지 않는다.

### 모든 펫 편집과 자동 copy-on-write

- 사용자 화면에서 `읽기 전용`, `편집 가능한 사본` 상태를 표시하거나 편집 버튼을 숨기지 않는다.
- 모든 선택 펫에 같은 메타데이터·애니메이션 편집 UI를 제공한다.
- 가져온 installation을 active instance 하나만 참조하면 최초 실제 저장 직전에 editor marker를 넣은 staging을 검증한 뒤 같은 installation UUID를 원자적으로 교체한다.
- 내장 펫 또는 둘 이상의 active instance가 같은 installation을 참조하면 최초 실제 저장 직전에 새 editable installation을 만들고 선택한 instance의 `petKey`만 새 installation로 바꾼다.
- copy-on-write는 선택한 instance UUID와 profile UUID를 새로 만들지 않는다. 행동, 이동, 쓰다듬기, 말풍선, overlay와 표시 상태도 그대로 유지한다.
- 편집 dialog를 열거나 취소한 것만으로 installation, instance 또는 profile을 만들지 않는다.
- `펫 사본 만들기`는 자동 copy-on-write와 다른 명시적 작업이다. 새 installation UUID, 새 instance UUID와 새 profile UUID를 만들고 원본의 모든 휴대 설정을 독립 복사한 뒤 새 사본을 선택한다.
- 내보내기에는 로컬 editor marker를 포함하지 않는다. 내보낸 패키지를 다시 가져오면 일반 가져오기처럼 새 installation·instance·profile을 만든다.

### 기존 보관 데이터 복구

- 앱 시작 시 installation 목록과 active instance의 `petKey`를 비교한다.
- 참조 instance가 없는 installation마다 새 instance를 하나 만들되, 같은 `petKey`의 미참조 기존 profile이 있으면 새 기본 profile보다 우선 연결한다.
- 복구 instance는 갑자기 데스크톱에 나타나지 않도록 `tuckedAway`로 시작하고 현재 선택은 유지한다.
- 복구 결과는 전체 settings 한 번의 원자적 저장으로 기록한다. 다음 시작에서 같은 installation을 중복 복구하면 안 된다.
- 이 복구는 schema migration이 아니며 schema-v15를 올리지 않는다.

## 3. 원자성·롤백

권장 순서는 다음과 같다.

1. 원본 해시와 패키지 검토 결과를 확정한다.
2. 임시 staging에 추출하고 전체 검증한다.
3. 새 installation UUID 경로로 원자적 publish한다.
4. 메모리의 settings 사본에 새 instance/profile/overlay를 만든다.
5. settings 전체를 임시 파일 flush 후 원자적 replace로 저장한다.
6. 성공한 뒤에만 UI 목록과 runtime manager에 알린다.

4~5가 실패하면 다음을 모두 수행한다.

- 새 installation 폴더 제거
- 메모리 settings와 selected instance 복원
- 생성 예정이던 instance/profile 참조 폐기
- staging·settings 임시 파일 정리
- 기존 overlay HWND와 runtime은 변경하지 않음

installation 제거도 실패하면 조용히 성공 처리하지 말고 `펫 추가를 완료하지 못했고 설치 정리도 필요합니다`라는 사용자 오류와 로그용 installation UUID를 분리해 남긴다. 다음 시작에서 orphan installation을 감지할 수는 있지만 자동 삭제하지 않는다.

편집 준비도 같은 transaction 원칙을 따른다.

- 단독 installation의 in-place 전환은 검증된 staging을 기존 installation과 원자적으로 교체한다.
- 내장·공유 installation의 copy-on-write는 새 installation publish와 선택 instance의 `petKey` 저장을 하나의 사용자 작업으로 취급한다.
- settings 저장 실패 시 새 installation을 제거하고 기존 `petKey`, 선택, profile과 runtime을 유지한다.
- 메타데이터·애니메이션 저장 자체가 실패하면 기존 installation을 유지하며 dialog에 사용자가 이해할 수 있는 오류를 표시한다.

완전 삭제 transaction은 다음 결과를 보장한다.

- settings 저장에 실패하면 installation 파일을 삭제하지 않는다.
- 마지막 installation 파일 삭제가 실패하면 이전 settings를 다시 저장하고 instance·profile과 runtime을 복원한다.
- 같은 installation을 다른 instance가 참조하면 installation 파일을 삭제하지 않는다.
- 성공한 뒤에만 제거된 runtime HWND와 shared asset cache 참조를 정리한다.

## 4. 말풍선 배치

### anchor

- overlay HWND 전체 사각형이 아니라 현재 프레임의 표시 픽셀(alpha > 0) 경계 사각형을 anchor로 사용한다.
- 기존 알파 마스크 캐시를 재사용하고 매 movement tick마다 원본 이미지를 다시 스캔하지 않는다.
- 알파 경계를 얻지 못하면 overlay content rect, 그것도 없으면 HWND rect 순서로 fallback한다.
- aspect-fit 여백, frame crop, 좌우·상하 반전과 content scale이 적용된 최종 표시 좌표로 변환한다.
- DIP/physical pixel 변환은 대상 pet HWND의 DPI에서 한 번만 수행하고 혼합 DPI 화면 이동 시 다시 계산한다.

### 위·아래 안정성

- `automatic`은 말풍선을 표시할 때 가능한 위/아래 한쪽을 선택한 뒤 표시 중에는 그 방향을 잠근다.
- 잠긴 쪽이 작업 영역 경계 때문에 더 이상 들어가지 않을 때만 반대쪽으로 전환하고 새 방향을 다시 잠근다.
- 매 movement tick의 작은 좌표 차이로 위·아래가 교대로 바뀌면 안 된다.
- preferred `above`/`below`도 불가능할 때만 반대쪽 또는 clamp fallback을 사용한다.
- horizontal clamp 뒤 tail anchor는 현재 불투명 anchor 중심을 계속 가리켜야 한다.

### 창 추적

- pet HWND 이동과 bubble HWND 이동의 단일 좌표 권한을 정한다. child/owned window 자동 추적과 수동 `SetWindowPos`를 동시에 중복 적용하지 않는다.
- text/theme 변경은 content 재측정을 허용하지만 단순 pet 이동은 XAML tree를 재생성하지 않는다.
- 말풍선 HWND는 non-activating·click-through 상태와 z-order를 유지한다.

## 5. 구현 단계

1. 관련 작업 계획을 만들고 현재 branch/status를 기록한다.
2. Domain scheduler 테스트부터 새 1회 재생 의미로 바꾼다.
3. 저장 mapper는 `repeats` 왕복을 유지하고 새 편집 기본값만 false로 바꾼다.
4. movement scheduler와 interaction 회귀를 통과시킨다.
5. 가져오기 application service에 installation+instance+profile transaction을 추가한다.
6. 기존 importer 두 경로가 새 service만 호출하게 한다.
7. WinUI 단일 `내 펫` 대시보드와 `선택한 펫 > 펫 정보·애니메이션`을 구현한다.
8. 보편 편집 service와 in-place 전환·copy-on-write·명시적 사본 transaction을 구현한다.
9. 보관 UI를 제거하고 재우기·완전 삭제 transaction·legacy orphan 복구를 구현한다.
10. 알파 anchor resolver와 stable-side speech placement를 순수 Core 코드로 추가한다.
11. overlay runtime에 캐시된 anchor와 bubble position update를 연결한다.
12. Debug·Release 테스트, 실제 packaged Release QA와 교차 왕복을 수행한다.
13. 완료한 항목만 `PLATFORM_PARITY.md`에 반영한다.

## 6. 필수 자동 테스트

### 행동

1. `repeats=true` 고정 행동이 한 번 재생 후 마지막 프레임 유지
2. 같은 완료 행동 resolve 반복이 재시작하지 않음
3. 편집된 같은 ID 행동은 즉시 첫 프레임 재시작
4. 규칙 행동 완료 뒤 같은 규칙 snapshot에서 유지
5. 랜덤 1개가 완료마다 첫 프레임 재시작
6. 랜덤 N개가 shuffle bag 중복 없이 한 번씩 실행
7. 이동 시작 시 랜덤 cursor 폐기, 종료 뒤 다음 행동 첫 프레임
8. 이동 scheduler는 이동 동안 반복하고 정지 후 timer 없음
9. 쓰다듬기 한 번 재생과 기존 계층 복원

### 저장·패키지

10. schema-v1~v15 `repeats` true/false 왕복 보존
11. 권장 프로필 v1~v11 왕복 보존
12. 새 행동 저장값 false
13. 패키지 모션 `loop`와 행동 1회 실행의 독립성
14. macOS fixture 가져오기와 다시 내보내기의 데이터 손실 없음

### 내 펫·가져오기

15. 가져오기 성공 시 서로 다른 installation/instance/profile UUID
16. 기존 active instances와 선택되지 않은 profiles 보존
17. 권장 profile/overlay가 새 instance에만 적용
18. 같은 패키지 두 번 가져오기 결과 독립
19. settings 저장 실패 시 새 installation 제거와 선택 복원
20. installation 제거 실패 시 명시적 recovery issue
21. 앱 재시작 뒤 모든 독립 설정 유지
22. 재우기·재실행 후 instance/profile/installation과 모든 설정 유지
23. 단독 가져온 펫의 첫 저장이 installation UUID를 유지하며 편집 가능 상태로 전환
24. 내장·공유 펫의 첫 저장이 선택 instance만 새 installation에 연결하고 instance/profile/settings를 보존
25. 편집 dialog 취소 시 installation·instance·profile 무변경
26. copy-on-write settings 저장 실패 시 새 installation 제거와 기존 연결 복원
27. 명시적 사본이 새 installation/instance/profile과 독립 설정을 생성
28. 다른 참조가 없는 펫 완전 삭제 시 instance/profile/installation 모두 제거
29. 공유 installation의 한 instance 삭제 시 다른 instance와 installation 유지
30. installation 삭제 실패 시 이전 settings와 runtime 복원
31. legacy orphan installation이 기존 미참조 profile을 연결한 잠든 instance로 한 번만 복구

### 말풍선

32. 투명 여백이 있는 마스크의 표시 경계 계산
33. aspect-fit·crop·flip·scale 좌표 변환
34. 위쪽 여유가 있는 자동 배치의 위 고정
35. 상단 경계 도달 때 아래 전환 후 다시 여유가 생겨도 표시 중 아래 유지
36. 음수 좌표 화면과 혼합 DPI clamp
37. horizontal clamp의 tail anchor 보정
38. 연속 이동 동안 XAML content 재생성 없음

## 7. 실제 Windows QA

- 행동 편집에서 전체 반복 토글이 사라지고 단계 반복만 편집 가능한지 확인
- 고정 행동과 앱·입력 없음 규칙을 짧게 만든 뒤 마지막 프레임 유지 확인
- 랜덤 1개·여러 개에서 완료 시 중간 프레임 없이 첫 프레임 시작 확인
- 세 이동 방식에서 이동 모션 연속성과 정지 후 평상시 결과 확인
- 단일 `내 펫`에 보관 구분 없이 생성·가져오기·사본·내보내기 동선이 있는지 확인
- 여러 active card의 선택·이름·깨우기·순서·독립 설정과 재실행 확인
- 같은 파일과 URL을 각각 두 번 가져와 기존 펫이 바뀌지 않고 새 펫 네 개가 생기는지 확인
- 권장 설정/기본 설정 추가 결과를 비교하고 제거·재추가 확인
- 가져온 단독 펫을 편집하고 내장·공유 펫 중 한 instance만 편집해 원본·다른 instance가 바뀌지 않는지 확인
- 펫 정보·애니메이션 편집을 취소했을 때 내 펫 목록과 현재 instance 연결이 바뀌지 않는지 확인
- 재운 펫의 모든 설정이 재실행 뒤 유지되고 완전 삭제한 펫은 다시 나타나지 않는지 확인
- 구버전 비활성 installation fixture가 잠든 펫으로 한 번만 복구되는지 확인
- 가져오기 도중 settings 저장 실패를 주입해 orphan folder, 반쪽 profile, runtime overlay가 남지 않는지 확인
- 투명 여백이 큰 펫, 위아래 크기가 다른 프레임, 긴 문장과 짧은 문장에서 말풍선 거리 확인
- 펫을 화면 위·아래·좌우와 음수 좌표 보조 화면으로 이동해 방향 안정성·tail·clamp 확인
- 100%/125%/150%/200% DPI, 다크·라이트, 키보드, Narrator 확인
- packaged Debug와 Release 모두 확인하고 최근 AppCrash 이벤트와 settings 임시 파일을 점검

## 8. 성능 기준

- 알파 경계는 frame/atlas/flip/scale 키 캐시를 사용한다.
- 33ms movement tick마다 이미지 decode, 전체 alpha scan, XAML tree 생성, speech timer 재생성을 금지한다.
- 말풍선 위치만 바뀌면 Composition 또는 `SetWindowPos`의 최소 갱신만 사용한다.
- 고정 펫·말풍선 숨김, 고정 펫·말풍선 표시, 이동 펫·말풍선 표시 workload를 각각 30초 측정한다.
- 기존 CPU·private memory 기준보다 유의미한 회귀가 있으면 완료 처리하지 않는다.

## 완료 보고 형식

- 변경한 Core scheduler와 저장 호환 경계
- 제거한 WinUI 반복 UI와 새 안내
- 가져오기 transaction과 rollback 결과
- 보관 상태 없는 단일 `내 펫`과 `펫 정보·애니메이션` 구조
- 재우기·완전 삭제 transaction과 legacy orphan 복구 결과
- 보편 편집의 in-place 전환·copy-on-write·명시적 사본 결과
- 말풍선 alpha anchor·방향 잠금·DPI 처리
- 자동 테스트 수와 Debug·Release 빌드
- 실제 packaged QA와 성능 수치
- macOS 패키지 교차 왕복
- 남은 위험
- 수정 문서
- git status, 커밋·푸시·Release 상태

사용자 확인 전에는 Windows 버전·빌드 번호를 올리거나 Release를 게시하지 않는다.
