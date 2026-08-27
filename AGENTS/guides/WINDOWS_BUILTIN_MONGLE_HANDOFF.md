# Windows 내장 몽글이 교체 인계

## 목적과 현재 상태

macOS 최신 작업 트리에 확정한 내장 기본 펫 몽글이 `1.0.3`의 자산, 메타데이터와
권장 프로필을 Windows 네이티브 앱에 동등하게 반영하기 위한 인계 문서다.
Windows 소스 변경, 빌드와 실제 QA는 Windows 작업 공간에서 수행한다.

- macOS: 구현 및 자동 검증 중, 실제 앱 QA 대상
- Windows: 종전 기준에서 1.0.3 재적용 필요
- 공통 `.monglepet` schema 변경: 없음
- 기준 사용자 파일: `최종.monglepet`, 원본 펫 버전 `1.0.2`
- 기준 패키지: 1,313,804 bytes
- 기준 패키지 SHA-256: `d33c6265475969278012b96d4906311d73891c68b1b13c8e0464ac0bbaf47f9b`
- 내장 콘텐츠 버전: `1.0.3`

## Windows 작업 전 필수 확인

Windows 작업 공간에서는 다음 순서로 문서를 읽고 별도 작업 계획을 만든다.

1. `AGENTS.md`
2. `apps/windows/AGENTS.md`
3. 이 문서
4. `AGENTS/specifications/PET_PACKAGE.md`
5. `AGENTS/project/DECISIONS.md`의 D-022·D-086~D-088·D-100~D-102
6. `AGENTS/project/PLATFORM_PARITY.md`
7. `apps/windows/README.md`

작업 시작 전 macOS 구현 커밋이 원격에 올라갔고 Windows 작업 공간이 이를
`pull --ff-only`로 받은 상태인지 확인한다. Windows 소스를 수정하기 전에
`AGENTS/guides/DEVELOPMENT_WORKFLOW.md`에 따라 별도 Windows 작업 계획을 만들고
`공통 계약 → Windows 구현 → packaged/unpackaged 검증 → 플랫폼 동등성` 단계를
분리한다. macOS Swift·AppKit 소스는 수정하거나 C#으로 번역하지 않는다.

## 확정 메타데이터

| 항목 | 값 |
| --- | --- |
| 내부 예약 ID | 플랫폼의 기존 built-in key 유지 |
| 표시 이름 | `몽글이` |
| 펫 버전 | `1.0.3` |
| 제작자 | `운영자` |
| 설명 | `MonglePet에서 기본으로 제공되는 몽글펫입니다.` |
| 기본 모션 | `기본` |

웹 패키지의 사용자 펫 ID를 내장 예약 ID로 저장하지 않는다. 기존 built-in key를
유지해야 저장된 활성 인스턴스와 프로필 참조가 끊기지 않는다.

## 자산과 모션 계약

Windows 작업은 아래 버전 관리 PNG를 원본으로 사용한다. 파란·청록 입자와
외곽선은 의도한 표현이므로 제거하거나 다시 보정하지 않는다. 모든 프레임은
`150×150px`, y=0이고 각 atlas를 왼쪽에서 오른쪽으로 150px씩 읽는다.

| 모션 | macOS 원본 PNG | atlas 크기 | 프레임/간격 | SHA-256 |
| --- | --- | ---: | --- | --- |
| 기본 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleDefault.imageset/builtin-mongle-default.png` | 900×150 | 6×450ms | `22a13a0a95f7f1ab84c5748ab48ec98b85f4cb18da584f25a89a37e4bbc8f3fe` |
| 왼쪽 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleLeft.imageset/builtin-mongle-left.png` | 900×150 | 6×450ms | `911d722b564838190f28edea2eaf6ce12f8eb88b63800e35c9fe28d1da839af8` |
| 오른쪽 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleRight.imageset/builtin-mongle-right.png` | 900×150 | 6×450ms | `2caa10b6f62506db9ffb69acb88953e1cc3d3066650d7ec4646b821028725b26` |
| 위 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleUp.imageset/builtin-mongle-up.png` | 600×150 | 4×450ms | `51008c3a86befc763e1d4234c9a202dc20e6aea4b44be31451cc44d743f6bf8b` |
| 일하는 중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleWorking.imageset/builtin-mongle-working.png` | 1050×150 | 7×450ms | `4876a5a78aa444fbcf5e18cfdfd84dbae4b90d0249f8381152533ecdcbd4c32e` |
| 정면 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleFront.imageset/builtin-mongle-front.png` | 900×150 | 6×450ms | `5c0ea20c8ca838a5929e633d91a0777ba16c17c9ead9f36a6824fc056db0ca37` |
| 아래 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleDown.imageset/builtin-mongle-down.png` | 600×150 | 4×450ms | `367663b1f186c20526de49b56c360db2560840b7ee8d4362da93baeda5c1acf5` |
| 자는 중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSleeping.imageset/builtin-mongle-sleeping.png` | 300×150 | 450ms, 3000ms | `fc4389614036dbf6f7a3dbc880ee6189bf77e2912d085031d62f7caea970deec` |
| 물 뿜기 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSpouting.imageset/builtin-mongle-spouting.png` | 300×150 | 2×450ms | `0802d8501bf1cf9cd2166d4670162054adbf1178342de2090324204daa870d9f` |
| 찾는 중 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleSearching.imageset/builtin-mongle-searching.png` | 300×150 | 2×450ms | `12d2516d2d3956fb502e41d4a3ef67cfc18923bdc14d51f78e06ac9d1c7e3445` |
| 행복 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleHappy.imageset/builtin-mongle-happy.png` | 300×150 | 2×450ms | `b515de9a2f43941cc683c957c29b1057733e3f51fb3d56287e92957c5482f620` |
| 왼쪽 보글보글 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleBubbles.imageset/builtin-mongle-bubbles.png` | 450×150 | 3×450ms | `6814ed312b3b87e4729da656cb6f7ca2f9e93b3a1123a80515118dddedb99440` |
| 오른쪽 보글보글 | `apps/macos/MonglePet/Assets.xcassets/BuiltInMongleRightBubbles.imageset/builtin-mongle-right-bubbles.png` | 450×150 | 3×450ms | `04f00bdca5af83f29c3df29a3f03c0ae7fcbba65c7530232b4243d726834fb20` |

총 13개 모션, 53프레임이며 모두 반복 재생한다.

## 기본 프로필 계약

새 built-in 프로필과 종전의 수정되지 않은 built-in 기본 프로필에만 다음 값을
적용한다. 사용자가 수정한 기존 built-in 프로필과 설치 펫의 일반 기본값은
덮어쓰지 않는다.

- 모드: 자동, 직접 선택 행동 `기본`
- 행동: `기본=현재 펫 기본 애니메이션`과 패키지에 저장된 한 단계 행동 11개, 모두 반복
- 입력 없음 60초: `수면 중` 행동(`자는 중`), 활성화, priority 1
- 앱 규칙: 기본 등록 없음
- 자동 우선순위: `입력 없음 규칙 → 앱 사용 규칙 → 표시 및 이동`
- 이동: 마우스 도망가기
- 일반 속도 160, 포인터 거리 256, 정지 반경 16
- 자유 이동 대기 2~6초 랜덤, 전면 창 선호 비활성화
- 도망 감지 거리 160, 도망 속도 320, 정지 시 자유 이동
- 자유 이동·따라가기·도망가기 모두 방향 행동 사용: 왼쪽 `왼쪽 보글보글`, 오른쪽 `오른쪽 보글보글`, 위 `위`, 아래 `아래`
- 방향 fallback 없음, 대각선 방향 행동 비활성화
- 쓰다듬기 행동: 표시 이름 `행복`, 모션 `행복`
- 말풍선: 기본값이며 비활성화
- 권장 표시: 50%, 클릭 통과·포인터 겹침 투명화 켬, 픽셀 표시 끔, 불투명도 100%, 겹침 불투명도 45%
- 세 이동 방식의 수치·행동과 도망가기 평상시 자유 이동 설정은 권장 프로필 v10의 각 중첩 항목을 독립적으로 적용

행동 ID·규칙 ID와 방향 행동 연결의 정확한 값은
`shared/BuiltInPets/Mongle.monglepet/recommended-profile.json`을 단일 원본으로
사용한다. 플랫폼 전용 앱 규칙을 임의로 추가하지 않는다. 사용자가 만든 앱 규칙은
업데이트 시 그대로 보존한다.

## Windows 구현 위치

현재 Windows built-in은 다음 세 지점에서 테스트용 패키지와 결합되어 있다.

- `App.xaml.cs`: `LoadBundledSample()`, `BundledSamplePath`,
  `ResolvePackage(PetBehaviorKey.BuiltIn)`, `ResolveLegacyMotionCycleMilliseconds()`
- `MonglePet.Windows.csproj`: `shared/Samples/ReadOnlySample.monglepet`을 앱 출력과
  publish에 `Samples/ReadOnlySample.monglepet`으로 복사
- `DefaultAppSettingsDocument.cs`와 `BehaviorProfileDefaults.cs`: 모든 펫에 공통인
  중립 기본 프로필 생성

다음 경계로 변경한다.

1. `shared/Samples/ReadOnlySample.monglepet`은 패키지 로더·가져오기 테스트
   fixture로 그대로 유지한다. 파일 내용이나 테스트 의미를 새 몽글이로 바꾸지 않는다.
2. 저장소에 확정된 `shared/BuiltInPets/Mongle.monglepet/` 플랫폼 공통 데이터
   기준본을 그대로 사용한다. 새 디렉터리를 다시 만들거나 외부 패키지로 덮어쓰지
   않는다. schema-v10 `recommended-profile.json`은 독립 이동과 휴대 표시 전체를
   포함하며 플랫폼 전용 앱 규칙만 의도적으로 제외한다.
3. 위 표의 macOS PNG 경로는 원본 대조용일 뿐 Windows runtime이
   `apps/macos`를 직접 참조하지 않게 한다. 공통 built-in 디렉터리의 SHA-256과
   크기를 검증하고 그것만 Windows 앱 content로 포함한다.
4. `MonglePet.Windows.csproj`는 공통 built-in 디렉터리를
   `BuiltInPets/Mongle.monglepet`으로 output과 publish에 복사한다. Debug·Release,
   packaged loose AppX와 unpackaged self-contained publish 네 경로에서 파일 누락이
   없어야 한다.
5. `App.xaml.cs`의 `LoadBundledSample()`과 `BundledSamplePath`를 의미가 분명한
   `LoadBuiltInMongle()`과 `BuiltInMonglePath`로 교체한다. built-in runtime,
   legacy 모션 cycle resolver, 활성 펫 카드와 보관함 미리보기가 모두 같은
   `LoadedPetPackage`를 사용한다.
6. `BehaviorProfileDefaults.Create()`의 설치 펫 중립 기본값은 유지하고 built-in
   전용 생성기를 별도로 둔다. `DefaultAppSettingsDocument.CreateV10()`의 최초
   built-in 프로필과 schema-v11 누락 built-in 프로필 복구만 전용 기본값을 쓴다.
7. 종전 1.0.1 또는 1.0.2 내장 기본 프로필과 정확히 같은 경우에만 새 권장 기본값으로
   전환한다. 사용자가 바꾼 프로필은 행동 ID·mode·sequence·rule·priority·movement·
   petting·speech를 보존하고, 제거된 모션 ID `위로`·`자는중`·`물뿜기`·`해피`·
   `보글보글` 참조만 `위`·`자는 중`·`물 뿜기`·`행복`·`왼쪽 보글보글`로 바꾼다.
   설치 펫과 다른 활성 인스턴스의 프로필은 변경하지 않는다.
8. 보관함과 활성 펫 카드에는 위 메타데이터, 13개 모션과 실제 미리보기를 표시한다.
   기존 built-in key와 활성 인스턴스/profile ID는 유지한다.

공통 built-in 디렉터리의 `pet.json`은 내부 ID
`kr.mapleroom.monglepet.builtin.mongle`, 이 문서의 제작자·설명과 13개 모션을
사용한다. 외부 웹 사용자 펫 ID와 편집 marker는 넣지 않는다. `preview.png`는
150×150이며 패키지의 기존 대표 이미지를 사용하거나 `기본` 첫 프레임에서
결정적으로 생성한다. 임의 리사이즈나 효과 보정은 하지 않는다.

## 앱 규칙 경계

1.0.3 권장 프로필은 기본 앱 사용 규칙을 포함하지 않는다. Windows도 Codex PFN이나
`exe:` 값을 추측해 넣지 않는다. 사용자가 앱 선택기로 만든 규칙과 저장된 식별자는
마이그레이션에서 그대로 보존하고, 앱 규칙 실행 자체의 기존 회귀 테스트만 유지한다.

## 버전과 배포 경계

공개된 Windows `1.3.0.13` 산출물을 새 자산으로 덮어쓰지 않는다. Windows 작업
계획에서 다음 Preview의 마케팅·Assembly·File·MSIX·설치기 버전을 먼저 확정하고
`WindowsDistributionTests` 기대값도 같은 변경에 갱신한다. 이번 Windows 작업은
`WINDOWS_MACOS_1_3_HANDOFF.md`의 편집기·호환성 동등성까지 모두 구현·검증한 뒤
새 GitHub Pre-release 게시와 원격 digest 검증까지 완료한다.

## 필수 자동 검증

- 13개 PNG의 SHA-256과 픽셀 크기
- 기본 모션, 모션 ID 13개, 총 53프레임, 시간과 atlas 범위
- fresh built-in 프로필의 모든 확정 옵션
- schema-v10의 세 이동 모드·도망가기 평상시 자유 이동 독립값과 휴대 표시 옵션 전체
- 이전 중립 기본값만 새 기본값으로 이관
- 사용자 수정 built-in 프로필 보존
- 설치 펫 기본 프로필이 종전 중립값을 유지
- settings 저장·재실행, 다중 built-in 인스턴스별 프로필 독립성
- 내장 펫 내보내기 금지와 일반 패키지 가져오기 fixture 회귀
- built-in content가 Debug·Release output, packaged loose AppX와 unpackaged publish에 모두 존재
- x64 Debug·Release 전체 테스트와 빌드

Windows 환경의 기본 검증 명령은 저장소 루트에서 다음과 같다.

```powershell
dotnet restore apps/windows/MonglePet.slnx
dotnet build apps/windows/MonglePet.slnx --configuration Debug --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Debug --no-build --no-restore --maxcpucount:1
dotnet build apps/windows/MonglePet.slnx --configuration Release --no-restore --maxcpucount:1
dotnet test apps/windows/MonglePet.slnx --configuration Release --no-build --no-restore --maxcpucount:1
```

## 실제 Windows QA

1. 깨끗한 설정에서 몽글이가 첫 펫으로 표시되고 `기본` 애니메이션을 반복한다.
2. 포인터 접근과 평상시 자유 이동에서 4방향 행동이 실제 이동 방향과 일치한다.
3. 쓰다듬을 때 `행복` 모션이 표시되고 원래 행동으로 복귀한다.
4. 60초 입력 없음에서 `자는 중`, 입력 복귀 시 즉시 기본 판단으로 돌아온다.
5. 2~6초 랜덤 머무르기가 목표 도착마다 한 번만 추첨되고 이동이 흔들리지 않는다.
6. 기존 수정 프로필·앱 규칙과 다중 인스턴스를 둔 채 앱 업데이트 후 설정이 보존된다.
7. 50%·혼합 DPI 화면에서 모든 프레임이 잘리지 않고 크기·투명도가 동일하다.
8. 완료 후 `AGENTS/project/PLATFORM_PARITY.md`를 동등 상태로 갱신한다.

## 완료 조건

- 공통 built-in 데이터, Windows 네이티브 loader·기본값·이관과 UI 표시가 구현됐다.
- Debug·Release 전체 xUnit과 빌드가 통과했다.
- packaged·unpackaged 실제 앱에서 자산·행동·이동·쓰다듬기와 업데이트 보존을 확인했다.
- 기본 앱 규칙을 추가하지 않고 사용자 앱 규칙과 일반 자동 규칙 회귀를 확인했다.
- 기존 `ReadOnlySample.monglepet` fixture와 일반 설치 펫 동작이 회귀하지 않았다.
- `AGENTS/project/TESTING.md`, 기능 작업 계획과 `PLATFORM_PARITY.md`를 갱신했다.
- macOS·Windows 교차 결과가 확인되기 전에는 플랫폼 동등 완료로 표시하지 않는다.
